import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/services/notifications_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../sales/domain/payment.dart';
import '../../sales/domain/sale.dart';

/// Operaciones que el rol caja (o admin actuando como caja) ejecuta sobre
/// una venta. Workflow (toma/proceso/devolución/cancelación) + motor
/// financiero (abonos, pérdida, plazo). Todo lo que toca agregados va en
/// `runTransaction` para no dejar el doc del padre desincronizado con su
/// subcolección de payments.
class CashierRepository {
  CashierRepository(this._firestore, this._notifications);

  final FirebaseFirestore _firestore;
  final NotificationsRepository _notifications;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.sales);

  /// Soft lock: cajero levanta una solicitud `generada` a `en_proceso`.
  /// Si otro cajero ya la tomó (state != generada) lanza StateError.
  Future<void> takeRequest({
    required String saleId,
    required AppUser actor,
  }) async {
    await _firestore.runTransaction((txn) async {
      final ref = _col.doc(saleId);
      final snap = await txn.get(ref);
      _ensureExists(snap, saleId);
      final state = SaleState.fromId(snap.data()?['state'] as String?);
      if (state != SaleState.generada) {
        throw StateError(
          'Esta solicitud ya no está pendiente (estado actual: ${state.id}).',
        );
      }
      txn.update(ref, {
        'state': SaleState.enProceso.id,
        'updatedAt': _now(),
      });
    });
  }

  /// `en_proceso` → `procesada`. NO requiere pago. Sales podrá entregar
  /// material desde el momento que cajero confirme acá.
  Future<void> processRequest({
    required String saleId,
    required AppUser actor,
  }) async {
    await _firestore.runTransaction((txn) async {
      final ref = _col.doc(saleId);
      final snap = await txn.get(ref);
      _ensureExists(snap, saleId);
      final data = snap.data()!;
      final state = SaleState.fromId(data['state'] as String?);
      if (state != SaleState.enProceso) {
        throw StateError(
          'Esta solicitud no está en proceso (estado actual: ${state.id}).',
        );
      }
      final now = _now();
      txn.update(ref, {
        'state': SaleState.procesada.id,
        'processedBy': actor.uid,
        'processedByName': actor.fullName,
        'processedAt': now,
        'updatedAt': now,
      });
      _notifications.emitInTxn(
        txn,
        type: NotificationType.saleProcessed,
        title: 'Solicitud procesada',
        body: _saleHeadline(data),
        saleId: saleId,
        actorUid: actor.uid,
        actorName: actor.fullName,
        targetUids: [data['createdBy'] as String],
      );
    });
  }

  /// `en_proceso` → `generada`. El cajero devuelve la solicitud para que
  /// sales la corrija. `reason` opcional (queda como nota en el doc para
  /// que sales sepa por qué).
  Future<void> returnToSales({
    required String saleId,
    required AppUser actor,
    String? reason,
  }) async {
    await _firestore.runTransaction((txn) async {
      final ref = _col.doc(saleId);
      final snap = await txn.get(ref);
      _ensureExists(snap, saleId);
      final data = snap.data()!;
      final state = SaleState.fromId(data['state'] as String?);
      if (state != SaleState.enProceso) {
        throw StateError(
          'Solo se puede devolver una solicitud en proceso '
          '(estado actual: ${state.id}).',
        );
      }
      final trimmedReason = reason?.trim();
      txn.update(ref, {
        'state': SaleState.generada.id,
        'updatedAt': _now(),
        if (trimmedReason != null && trimmedReason.isNotEmpty)
          'returnReason': trimmedReason,
      });
      // El creador (sales) necesita enterarse — si no, la solicitud
      // reaparece en su lista sin pista de por qué cajero la rechazó.
      // Este es el único loop colaborativo bidireccional del workflow.
      _notifications.emitInTxn(
        txn,
        type: NotificationType.saleReturnedToSales,
        title: 'Solicitud devuelta',
        body: _saleHeadline(data, reason: trimmedReason),
        saleId: saleId,
        actorUid: actor.uid,
        actorName: actor.fullName,
        targetUids: [data['createdBy'] as String],
      );
    });
  }

  /// Cualquier no-terminal → `cancelada`. La razón es obligatoria para
  /// quedar registrada en el doc.
  Future<void> cancelRequest({
    required String saleId,
    required AppUser actor,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('La razón es obligatoria al cancelar.');
    }
    await _firestore.runTransaction((txn) async {
      final ref = _col.doc(saleId);
      final snap = await txn.get(ref);
      _ensureExists(snap, saleId);
      final data = snap.data()!;
      final state = SaleState.fromId(data['state'] as String?);
      if (state == SaleState.procesada || state == SaleState.cancelada) {
        throw StateError(
          'Esta solicitud ya está en un estado final '
          '(estado actual: ${state.id}).',
        );
      }
      final now = _now();
      txn.update(ref, {
        'state': SaleState.cancelada.id,
        'canceledBy': actor.uid,
        'canceledByName': actor.fullName,
        'canceledAt': now,
        'cancelReason': trimmed,
        'updatedAt': now,
      });
      _notifications.emitInTxn(
        txn,
        type: NotificationType.saleCanceled,
        title: 'Solicitud cancelada',
        body: _saleHeadline(data, reason: trimmed),
        saleId: saleId,
        actorUid: actor.uid,
        actorName: actor.fullName,
        targetUids: [data['createdBy'] as String],
      );
    });
  }

  /// Registra un abono contra una venta. Crea el doc en la subcolección
  /// `payments` y recalcula los agregados denormalizados del padre
  /// (`paidAmount`, `outstandingBalance`, `financialStatus`) en la misma
  /// transacción. Permite sobrepago (la UI advierte).
  ///
  /// No permitido si la solicitud fue cancelada. Sí permitido si ya está
  /// marcada como pérdida — la UI muestra warning pero deja registrar.
  Future<SalePayment> registerPayment({
    required String saleId,
    required num amount,
    required String paymentMethod,
    num? cashAmount,
    num? transferAmount,
    String? transferDestination,
    String? payerName,
    String? notes,
    required AppUser actor,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('El abono debe ser mayor a cero.');
    }
    return _firestore.runTransaction((txn) async {
      final saleRef = _col.doc(saleId);
      final saleSnap = await txn.get(saleRef);
      _ensureExists(saleSnap, saleId);
      final data = saleSnap.data()!;
      final state = SaleState.fromId(data['state'] as String?);
      if (state == SaleState.cancelada) {
        throw StateError(
          'No se puede registrar un abono en una solicitud cancelada.',
        );
      }
      final totalValue = data['totalValue'] as num;
      final currentPaid = (data['paidAmount'] as num?) ?? 0;
      final currentLoss = (data['lossAmount'] as num?) ?? 0;
      final newPaid = currentPaid + amount;
      final newOutstanding = totalValue - newPaid - currentLoss;
      // Regla "lost absorbe": si ya hay lossAmount > 0, el status sigue
      // siendo lost aunque después se cobre.
      final newStatus = Sale.computeFinancialStatus(
        totalValue: totalValue,
        paidAmount: newPaid,
        lossAmount: currentLoss,
      );

      final paymentRef = saleRef.collection('payments').doc();
      final now = AppClock.now();
      final payment = SalePayment(
        id: paymentRef.id,
        amount: amount,
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        transferAmount: transferAmount,
        transferDestination: transferDestination,
        payerName: payerName,
        registeredBy: actor.uid,
        registeredByName: actor.fullName,
        registeredAt: now,
        notes: notes,
      );
      txn.set(paymentRef, payment.toMap());
      txn.update(saleRef, {
        'paidAmount': newPaid,
        'outstandingBalance': newOutstanding,
        'financialStatus': newStatus.id,
        'updatedAt': _now(),
      });
      return payment;
    });
  }

  /// Anula un abono. Solo admin (rule + assertion). Borra el doc y
  /// recalcula los agregados del padre. La razón es obligatoria a nivel
  /// UX pero no se persiste — el delete es la traza.
  Future<void> voidPayment({
    required String saleId,
    required String paymentId,
    required String reason,
    required AppUser actor,
  }) async {
    if (actor.role != AppRole.admin) {
      throw StateError('Solo el administrador puede anular pagos.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('La razón es obligatoria para anular un pago.');
    }
    await _firestore.runTransaction((txn) async {
      final saleRef = _col.doc(saleId);
      final paymentRef = saleRef.collection('payments').doc(paymentId);
      final saleSnap = await txn.get(saleRef);
      final paymentSnap = await txn.get(paymentRef);
      _ensureExists(saleSnap, saleId);
      if (!paymentSnap.exists) {
        throw StateError('El abono ya no existe.');
      }
      final paymentData = paymentSnap.data()!;
      final amountVoided = paymentData['amount'] as num;
      final paymentRegisteredBy = paymentData['registeredBy'] as String?;
      final data = saleSnap.data()!;
      final totalValue = data['totalValue'] as num;
      final currentPaid = (data['paidAmount'] as num?) ?? 0;
      final currentLoss = (data['lossAmount'] as num?) ?? 0;
      final newPaidRaw = currentPaid - amountVoided;
      final newPaid = newPaidRaw < 0 ? 0 : newPaidRaw;
      final newOutstanding = totalValue - newPaid - currentLoss;
      final newStatus = Sale.computeFinancialStatus(
        totalValue: totalValue,
        paidAmount: newPaid,
        lossAmount: currentLoss,
      );
      txn.delete(paymentRef);
      txn.update(saleRef, {
        'paidAmount': newPaid,
        'outstandingBalance': newOutstanding,
        'financialStatus': newStatus.id,
        'updatedAt': _now(),
      });
      // Avisamos al cajero que registró el abono. Sin esto, ve que el
      // balance cambió "de la nada" y puede registrarlo de nuevo creyendo
      // que se perdió la operación. Si el admin anuló un pago propio
      // (mismo uid) la notif queda redundante pero inocua — el filtro
      // se vería en cliente y no vale la pena complicar la regla.
      if (paymentRegisteredBy != null && paymentRegisteredBy.isNotEmpty) {
        _notifications.emitInTxn(
          txn,
          type: NotificationType.paymentVoided,
          title: 'Abono anulado',
          body:
              '${data['consecutive']} — ${data['providerName']}, '
              'abono de ${formatCop(amountVoided)} '
              'anulado por ${actor.fullName}: ${reason.trim()}',
          saleId: saleId,
          actorUid: actor.uid,
          actorName: actor.fullName,
          targetUids: [paymentRegisteredBy],
        );
      }
    });
  }

  /// Marca el saldo pendiente como pérdida. `lossAmount` se incrementa en
  /// el outstandingBalance al momento de marcar y `financialStatus` queda
  /// `lost` (absorbente — registerPayment posterior no lo cambia).
  ///
  /// Permitido en cualquier momento mientras `outstandingBalance > 0`,
  /// incluso si state == cancelada.
  Future<void> markAsLoss({
    required String saleId,
    required String reason,
    required AppUser actor,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('La razón es obligatoria al marcar pérdida.');
    }
    await _firestore.runTransaction((txn) async {
      final saleRef = _col.doc(saleId);
      final saleSnap = await txn.get(saleRef);
      _ensureExists(saleSnap, saleId);
      final data = saleSnap.data()!;
      final totalValue = data['totalValue'] as num;
      final currentPaid = (data['paidAmount'] as num?) ?? 0;
      final currentLoss = (data['lossAmount'] as num?) ?? 0;
      final currentOutstanding = totalValue - currentPaid - currentLoss;
      if (currentOutstanding <= 0) {
        throw StateError(
          'No hay saldo pendiente para marcar como pérdida.',
        );
      }
      final newLoss = currentLoss + currentOutstanding;
      final now = AppClock.now();
      txn.update(saleRef, {
        'lossAmount': newLoss,
        'outstandingBalance': 0,
        'financialStatus': SaleFinancialStatus.lost.id,
        'markedAsLossBy': actor.uid,
        'markedAsLossByName': actor.fullName,
        'markedAsLossAt':
            Timestamp.fromDate(AppClock.toInstant(now)),
        'lossReason': reason.trim(),
        'updatedAt': Timestamp.fromDate(AppClock.toInstant(now)),
      });
      // Solo admin recibe la notif — sales no necesita enterarse y se
      // evita ruido cuando es una venta vieja que ya entregó material.
      _notifications.emitInTxn(
        txn,
        type: NotificationType.saleMarkedLoss,
        title: 'Saldo marcado como pérdida',
        body:
            '${data['consecutive']} — ${data['providerName']}, '
            '${formatCop(currentOutstanding)} '
            '(${reason.trim()})',
        saleId: saleId,
        actorUid: actor.uid,
        actorName: actor.fullName,
        targetRoles: const [AppRole.admin],
      );
    });
  }

  /// Edita o quita el plazo de pago (`creditDueDate`). Pasar `null` lo
  /// borra. Sin lógica automática — solo persiste el campo; la UI usa
  /// ese valor para destacar deudas vencidas.
  Future<void> updateCreditDueDate({
    required String saleId,
    required DateTime? date,
  }) async {
    await _col.doc(saleId).update({
      'creditDueDate': date == null
          ? null
          : Timestamp.fromDate(AppClock.toInstant(date)),
      'updatedAt': _now(),
    });
  }

  void _ensureExists(
    DocumentSnapshot<Map<String, dynamic>> snap,
    String saleId,
  ) {
    if (!snap.exists) {
      throw StateError('La venta $saleId ya no existe.');
    }
  }

  Timestamp _now() => Timestamp.fromDate(AppClock.toInstant(AppClock.now()));

  /// Cuerpo estándar de notifs sobre una venta. `data` es el map crudo
  /// de Firestore — leemos los campos por nombre para no tener que
  /// deserializar el `Sale` completo dentro del runTransaction.
  String _saleHeadline(Map<String, dynamic> data, {String? reason}) {
    final consecutive = data['consecutive'] as String? ?? '';
    final provider = data['providerName'] as String? ?? '';
    final total = (data['totalValue'] as num?) ?? 0;
    final base = '$consecutive — $provider, ${formatCop(total)}';
    if (reason == null || reason.isEmpty) return base;
    return '$base ($reason)';
  }
}

final cashierRepositoryProvider = Provider<CashierRepository>((ref) {
  return CashierRepository(
    FirebaseFirestore.instance,
    ref.watch(notificationsRepositoryProvider),
  );
});

/// Argumento para `salesByStatesProvider`: wrapper con `==`/`hashCode`
/// estable para que la `family` cachee correctamente sin sufrir igualdad
/// por identidad del `Set`.
class SalesByStatesQuery {
  const SalesByStatesQuery(this.states);
  final Set<SaleState> states;

  @override
  bool operator ==(Object other) =>
      other is SalesByStatesQuery &&
      other.states.length == states.length &&
      other.states.containsAll(states);

  @override
  int get hashCode => Object.hashAllUnordered(states);
}

/// Stream de TODAS las ventas con un `state` en un set específico. El
/// home de cajero compone los 3 tabs leyendo esta misma fuente con
/// distintos filtros aplicados en memoria. Firestore acepta `whereIn`
/// con hasta 30 valores; acá son a lo sumo 4 (los estados).
final salesByStatesProvider = StreamProvider.autoDispose
    .family<List<Sale>, SalesByStatesQuery>((ref, q) {
  ref.watch(authStateProvider);
  final col = FirebaseFirestore.instance.collection(FirestorePaths.sales);
  return col
      .where('state', whereIn: q.states.map((s) => s.id).toList())
      .snapshots()
      .map((snap) => snap.docs.map(Sale.fromSnapshot).toList());
});

/// Sets predefinidos para evitar re-instanciar el `SalesByStatesQuery`
/// en cada build (manteniendo el cache de Riverpod intacto).
const pendingStatesQuery = SalesByStatesQuery(<SaleState>{
  SaleState.generada,
  SaleState.enProceso,
});
const processedStatesQuery =
    SalesByStatesQuery(<SaleState>{SaleState.procesada});
const canceledStatesQuery =
    SalesByStatesQuery(<SaleState>{SaleState.cancelada});

/// Lista reactiva de abonos para una venta, ordenada del más reciente al
/// más antiguo. La pantalla de pagos la consume directamente.
final paymentsBySaleProvider = StreamProvider.autoDispose
    .family<List<SalePayment>, String>((ref, saleId) {
  ref.watch(authStateProvider);
  return FirebaseFirestore.instance
      .collection(FirestorePaths.sales)
      .doc(saleId)
      .collection('payments')
      .orderBy('registeredAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(SalePayment.fromSnapshot).toList());
});
