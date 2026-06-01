import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/clock.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../sales/domain/payment.dart';
import '../domain/cash_register.dart';
import '../domain/cash_register_config.dart';
import '../domain/cash_shift.dart';

/// Resultado del cálculo del esperado de una ventana de caja. `cash` y
/// `transfer` ya incluyen (o no) la base según quién lo pida: el esperado
/// en vivo y el del cierre la suman aparte.
typedef ExpectedTotals = ({
  num cash,
  num transfer,
  num preOpen,
  int count,
});

/// Acceso al cierre de caja. Tres documentos:
///   - `settings/cash_register`     → estado runtime (singleton).
///   - `settings/cash_register_config` → hora de cierre (admin-only).
///   - `cash_shifts/{shiftId}`      → ledger append-only de turnos.
///
/// El esperado se calcula leyendo los `payments` de la ventana
/// `(periodStart, until]` con un collection group query (mismo criterio que
/// `SalesMetrics`). Esa lectura corre FUERA de `runTransaction` porque las
/// transacciones no admiten queries de subcolección — igual que
/// `SalesRepository.deleteSale`. La transacción solo sincroniza el singleton
/// con el doc del turno para que ambos queden siempre consistentes.
class CashShiftRepository {
  CashShiftRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _registerRef => _firestore
      .collection(FirestorePaths.settings)
      .doc(FirestorePaths.cashRegisterSettings);

  DocumentReference<Map<String, dynamic>> get _configRef => _firestore
      .collection(FirestorePaths.settings)
      .doc(FirestorePaths.cashRegisterConfigSettings);

  CollectionReference<Map<String, dynamic>> get _shiftsCol =>
      _firestore.collection(FirestorePaths.cashShifts);

  /// Estado de la caja. Si el doc no existe (nunca se abrió), emite
  /// [CashRegister.closed].
  Stream<CashRegister> watchRegister() {
    return _registerRef.snapshots().map(CashRegister.fromSnapshot);
  }

  /// Configuración del cierre. Lazy default si el doc no existe.
  Stream<CashRegisterConfig> watchConfig() {
    return _configRef.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return const CashRegisterConfig.defaults();
      }
      return CashRegisterConfig.fromMap(snap.data()!);
    });
  }

  Future<void> saveConfig(CashRegisterConfig config) async {
    await _configRef.set(config.toMap(), SetOptions(merge: true));
  }

  /// El turno abierto, si hay uno. Se resuelve por el `openShiftId` del
  /// singleton para no depender de un query por `status`.
  Stream<CashShift?> watchOpenShift() {
    return watchRegister().asyncMap((register) async {
      final shiftId = register.openShiftId;
      if (!register.isOpen || shiftId == null) return null;
      final snap = await _shiftsCol.doc(shiftId).get();
      if (!snap.exists) return null;
      return CashShift.fromSnapshot(snap);
    });
  }

  /// Cierres ya cerrados, más recientes primero. Filtramos por `status` en
  /// memoria para no requerir un índice compuesto `status + businessDate`.
  Stream<List<CashShift>> watchClosedShifts({int limit = 50}) {
    return _shiftsCol
        .orderBy('businessDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(CashShift.fromSnapshot)
            .where((s) => s.status == CashShiftStatus.closed)
            .toList(),);
  }

  /// Suma el efectivo y la transferencia de los payments recibidos en
  /// `(periodStart, until]`. `preOpen` cuenta lo recibido en
  /// `(periodStart, openedAt)` — informativo. NO incluye la base: quien lo
  /// llame la suma según necesite.
  ///
  /// Mismo criterio de método que `SalesMetrics.compute` para no divergir:
  /// si el payment no trae `cashAmount`/`transferAmount` (abonos viejos),
  /// se infiere por `paymentMethod`.
  Future<ExpectedTotals> computeExpected({
    required DateTime periodStart,
    required DateTime openedAt,
    required DateTime until,
  }) async {
    final start = Timestamp.fromDate(AppClock.toInstant(periodStart));
    final end = Timestamp.fromDate(AppClock.toInstant(until));
    final snap = await _firestore
        .collectionGroup('payments')
        .where('registeredAt', isGreaterThan: start)
        .where('registeredAt', isLessThanOrEqualTo: end)
        .get();

    num cash = 0;
    num transfer = 0;
    num preOpen = 0;
    for (final doc in snap.docs) {
      final p = SalePayment.fromSnapshot(doc);
      final method = p.paymentMethod.toLowerCase();
      final pCash =
          p.cashAmount ?? (method == 'efectivo' ? p.amount : 0);
      final pTransfer =
          p.transferAmount ?? (method == 'transferencia' ? p.amount : 0);
      cash += pCash;
      transfer += pTransfer;
      if (p.registeredAt.isBefore(openedAt)) {
        preOpen += pCash + pTransfer;
      }
    }
    return (
      cash: cash,
      transfer: transfer,
      preOpen: preOpen,
      count: snap.docs.length,
    );
  }

  /// Esperado en vivo de la caja abierta (hasta ahora). Reusa
  /// [computeExpected] con `until = now` y suma la base al efectivo.
  Future<CashShiftExpectation> liveExpectation(CashRegister register) async {
    final periodStart = register.periodStart;
    final openedAt = register.openedAt;
    if (!register.isOpen || periodStart == null || openedAt == null) {
      return const CashShiftExpectation(
        expectedCash: 0,
        expectedTransfer: 0,
        preOpenReceived: 0,
        paymentsCount: 0,
      );
    }
    final base = register.openingFloat ?? 0;
    final totals = await computeExpected(
      periodStart: periodStart,
      openedAt: openedAt,
      until: AppClock.now(),
    );
    return CashShiftExpectation(
      expectedCash: base + totals.cash,
      expectedTransfer: totals.transfer,
      preOpenReceived: totals.preOpen,
      paymentsCount: totals.count,
    );
  }

  /// Abre la caja. La base [openingFloat] viene precargada con el remanente
  /// del último cierre (editable). El `periodStart` arranca donde terminó el
  /// turno anterior — ventana contigua — o en `now` si es el primero.
  Future<void> openShift({
    required AppUser actor,
    required num openingFloat,
    String? note,
  }) async {
    final now = AppClock.now();
    final shiftRef = _shiftsCol.doc();
    await _firestore.runTransaction((txn) async {
      final regSnap = await txn.get(_registerRef);
      final register = CashRegister.fromSnapshot(regSnap);
      if (register.isOpen) {
        throw StateError(
          'La caja ya está abierta'
          '${register.openedByName != null ? " por ${register.openedByName}" : ""}.',
        );
      }
      final periodStart = register.lastClosedAt ?? now;
      final cleanedNote = note?.trim();
      final shift = CashShift(
        id: shiftRef.id,
        status: CashShiftStatus.open,
        businessDate: CashShift.businessDateLabel(now),
        openedBy: actor.uid,
        openedByName: actor.fullName,
        openedAt: now,
        openingFloat: openingFloat,
        periodStart: periodStart,
        note: (cleanedNote != null && cleanedNote.isNotEmpty)
            ? cleanedNote
            : null,
      );
      txn.set(shiftRef, shift.toMap());
      // Merge para conservar `lastClosedAt`/`lastRemainingCash` del ciclo
      // anterior (los necesita la próxima apertura para precargar la base).
      txn.set(
        _registerRef,
        {
          'isOpen': true,
          'openShiftId': shiftRef.id,
          'openedBy': actor.uid,
          'openedByName': actor.fullName,
          'openedAt': Timestamp.fromDate(AppClock.toInstant(now)),
          'openingFloat': openingFloat,
          'periodStart':
              Timestamp.fromDate(AppClock.toInstant(periodStart)),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Cierra la caja con el arqueo. El esperado se calcula justo antes de la
  /// transacción (query a payments). Exige razón por cada método que no
  /// cuadre. Congela todos los campos en el doc del turno y devuelve el
  /// `CashShift` cerrado.
  Future<CashShift> closeShift({
    required AppUser actor,
    required num countedCash,
    required num confirmedTransfer,
    String? cashReason,
    String? transferReason,
    num? withdrawalAmount,
    String? note,
    String? businessDate,
  }) async {
    final now = AppClock.now();
    final regSnap = await _registerRef.get();
    final register = CashRegister.fromSnapshot(regSnap);
    final shiftId = register.openShiftId;
    final periodStart = register.periodStart;
    final openedAt = register.openedAt;
    if (!register.isOpen || shiftId == null || periodStart == null ||
        openedAt == null) {
      throw StateError('No hay caja abierta para cerrar.');
    }

    final base = register.openingFloat ?? 0;
    final totals = await computeExpected(
      periodStart: periodStart,
      openedAt: openedAt,
      until: now,
    );
    final expectedCash = base + totals.cash;
    final expectedTransfer = totals.transfer;
    final cashDiscrepancy = countedCash - expectedCash;
    final transferDiscrepancy = confirmedTransfer - expectedTransfer;

    final cleanedCashReason = cashReason?.trim();
    final cleanedTransferReason = transferReason?.trim();
    if (cashDiscrepancy != 0 &&
        (cleanedCashReason == null || cleanedCashReason.isEmpty)) {
      throw ArgumentError(
        'El efectivo no cuadra: indica una razón para la diferencia.',
      );
    }
    if (transferDiscrepancy != 0 &&
        (cleanedTransferReason == null || cleanedTransferReason.isEmpty)) {
      throw ArgumentError(
        'Las transferencias no cuadran: indica una razón para la diferencia.',
      );
    }
    final withdrawal = withdrawalAmount ?? 0;
    if (withdrawal < 0) {
      throw ArgumentError('El retiro no puede ser negativo.');
    }
    if (withdrawal > countedCash) {
      throw ArgumentError(
        'El retiro no puede ser mayor al efectivo contado.',
      );
    }
    final remainingCash = countedCash - withdrawal;
    final cleanedNote = note?.trim();

    final shiftRef = _shiftsCol.doc(shiftId);
    return _firestore.runTransaction<CashShift>((txn) async {
      final freshReg = CashRegister.fromSnapshot(await txn.get(_registerRef));
      if (!freshReg.isOpen || freshReg.openShiftId != shiftId) {
        throw StateError('La caja ya no está abierta. Vuelve a intentar.');
      }
      final shiftSnap = await txn.get(shiftRef);
      if (!shiftSnap.exists) {
        throw StateError('El turno de caja ya no existe.');
      }
      final openShift = CashShift.fromSnapshot(shiftSnap);

      final closed = CashShift(
        id: openShift.id,
        status: CashShiftStatus.closed,
        businessDate: (businessDate != null && businessDate.trim().isNotEmpty)
            ? businessDate.trim()
            : openShift.businessDate,
        openedBy: openShift.openedBy,
        openedByName: openShift.openedByName,
        openedAt: openShift.openedAt,
        openingFloat: openShift.openingFloat,
        periodStart: openShift.periodStart,
        closedBy: actor.uid,
        closedByName: actor.fullName,
        closedAt: now,
        expectedCash: expectedCash,
        countedCash: countedCash,
        cashDiscrepancy: cashDiscrepancy,
        cashDiscrepancyReason: cashDiscrepancy != 0 ? cleanedCashReason : null,
        expectedTransfer: expectedTransfer,
        confirmedTransfer: confirmedTransfer,
        transferDiscrepancy: transferDiscrepancy,
        transferDiscrepancyReason:
            transferDiscrepancy != 0 ? cleanedTransferReason : null,
        preOpenReceived: totals.preOpen,
        withdrawalAmount: withdrawal > 0 ? withdrawal : null,
        remainingCash: remainingCash,
        paymentsCount: totals.count,
        note: (cleanedNote != null && cleanedNote.isNotEmpty)
            ? cleanedNote
            : openShift.note,
      );
      txn.set(shiftRef, closed.toMap());
      txn.set(
        _registerRef,
        {
          'isOpen': false,
          'openShiftId': null,
          'openedBy': null,
          'openedByName': null,
          'openedAt': null,
          'openingFloat': null,
          'periodStart': null,
          'lastClosedAt': Timestamp.fromDate(AppClock.toInstant(now)),
          'lastRemainingCash': remainingCash,
        },
        SetOptions(merge: true),
      );
      return closed;
    });
  }
}

/// Esperado calculado para mostrar en vivo mientras la caja está abierta.
class CashShiftExpectation {
  const CashShiftExpectation({
    required this.expectedCash,
    required this.expectedTransfer,
    required this.preOpenReceived,
    required this.paymentsCount,
  });

  /// Incluye la base.
  final num expectedCash;
  final num expectedTransfer;
  final num preOpenReceived;
  final int paymentsCount;
}

final cashShiftRepositoryProvider = Provider<CashShiftRepository>((ref) {
  return CashShiftRepository(FirebaseFirestore.instance);
});

final cashRegisterProvider = StreamProvider.autoDispose<CashRegister>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(cashShiftRepositoryProvider).watchRegister();
});

final cashRegisterConfigProvider =
    StreamProvider.autoDispose<CashRegisterConfig>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(cashShiftRepositoryProvider).watchConfig();
});

final openCashShiftProvider = StreamProvider.autoDispose<CashShift?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(cashShiftRepositoryProvider).watchOpenShift();
});

final closedCashShiftsProvider =
    StreamProvider.autoDispose<List<CashShift>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(cashShiftRepositoryProvider).watchClosedShifts();
});
