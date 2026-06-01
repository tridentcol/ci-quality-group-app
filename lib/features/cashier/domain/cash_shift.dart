import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Estado del turno en el ledger `cash_shifts/{shiftId}`.
enum CashShiftStatus {
  open('open'),
  closed('closed');

  const CashShiftStatus(this.id);
  final String id;

  static CashShiftStatus fromId(String? id) {
    for (final s in CashShiftStatus.values) {
      if (s.id == id) return s;
    }
    return CashShiftStatus.open;
  }
}

/// Un turno de caja en el ledger append-only `cash_shifts/{shiftId}`.
///
/// Se crea con [CashShiftStatus.open] al abrir la caja y se actualiza una
/// única vez a [CashShiftStatus.closed] con el arqueo. Una vez cerrado es
/// inmutable (lo fuerzan las rules): refleja lo que se sabía al cerrar. Si
/// luego se anula un payment de su ventana, este doc NO cambia — el ajuste
/// se ve en los reportes en vivo, no en el cierre histórico.
///
/// La ventana del dinero es `(periodStart, closedAt]`: arranca donde
/// terminó el turno anterior (contigua) y termina en el cierre. El esperado
/// se congela al cerrar sumando los payments de esa ventana.
class CashShift {
  const CashShift({
    required this.id,
    required this.status,
    required this.businessDate,
    required this.openedBy,
    required this.openedByName,
    required this.openedAt,
    required this.openingFloat,
    required this.periodStart,
    this.closedBy,
    this.closedByName,
    this.closedAt,
    this.expectedCash,
    this.countedCash,
    this.cashDiscrepancy,
    this.cashDiscrepancyReason,
    this.expectedTransfer,
    this.confirmedTransfer,
    this.transferDiscrepancy,
    this.transferDiscrepancyReason,
    this.preOpenReceived,
    this.withdrawalAmount,
    this.remainingCash,
    this.paymentsCount,
    this.note,
  });

  final String id;
  final CashShiftStatus status;

  /// Etiqueta legible `YYYY-MM-DD` del turno (por defecto el día de la
  /// apertura). La ventana del dinero NO depende de esta etiqueta — sirve
  /// para mostrar y ordenar, sobre todo cuando el turno cruza la medianoche.
  final String businessDate;

  final String openedBy;
  final String openedByName;
  final DateTime openedAt;

  /// Base inicial declarada al abrir (precargada con el remanente del
  /// cierre anterior, editable por el cajero).
  final num openingFloat;

  /// Inicio de la ventana del dinero = cierre anterior (o [openedAt] si es
  /// el primer cierre histórico).
  final DateTime periodStart;

  final String? closedBy;
  final String? closedByName;

  /// Cierre = fin de la ventana del dinero. Null mientras está abierto.
  final DateTime? closedAt;

  /// `openingFloat` + Σ efectivo de payments en `(periodStart, closedAt]`.
  /// Congelado al cerrar.
  final num? expectedCash;

  /// Efectivo físico contado por el cajero al cerrar.
  final num? countedCash;

  /// `countedCash - expectedCash`. Positivo = sobra; negativo = falta.
  final num? cashDiscrepancy;

  /// Obligatoria si [cashDiscrepancy] != 0.
  final String? cashDiscrepancyReason;

  /// Σ transferencias de payments en la ventana. Congelado al cerrar.
  final num? expectedTransfer;

  /// Transferencias confirmadas por el cajero al cerrar.
  final num? confirmedTransfer;

  /// `confirmedTransfer - expectedTransfer`.
  final num? transferDiscrepancy;

  /// Obligatoria si [transferDiscrepancy] != 0.
  final String? transferDiscrepancyReason;

  /// Dinero recibido en `(periodStart, openedAt)` — mientras la caja estuvo
  /// cerrada. Informativo, para que el cajero entienda por qué el esperado
  /// puede ser mayor a lo que recibió en mano.
  final num? preOpenReceived;

  /// Retiro/consignación opcional al cerrar.
  final num? withdrawalAmount;

  /// `countedCash - (withdrawalAmount ?? 0)`. Lo que queda en el cajón;
  /// precarga la base del próximo turno.
  final num? remainingCash;

  /// Cantidad de payments incluidos en la ventana.
  final int? paymentsCount;

  final String? note;

  /// `YYYY-MM-DD` para usar como [businessDate] y orden estable.
  static String businessDateLabel(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  bool get isOpen => status == CashShiftStatus.open;

  bool get cashBalances => (cashDiscrepancy ?? 0) == 0;
  bool get transferBalances => (transferDiscrepancy ?? 0) == 0;

  /// `true` si el cierre cuadró en ambos métodos. Solo tiene sentido cuando
  /// el turno ya está cerrado.
  bool get balances => cashBalances && transferBalances;

  Map<String, dynamic> toMap() => {
        'status': status.id,
        'businessDate': businessDate,
        'openedBy': openedBy,
        'openedByName': openedByName,
        'openedAt': Timestamp.fromDate(AppClock.toInstant(openedAt)),
        'openingFloat': openingFloat,
        'periodStart': Timestamp.fromDate(AppClock.toInstant(periodStart)),
        if (closedBy != null) 'closedBy': closedBy,
        if (closedByName != null) 'closedByName': closedByName,
        if (closedAt != null)
          'closedAt': Timestamp.fromDate(AppClock.toInstant(closedAt!)),
        if (expectedCash != null) 'expectedCash': expectedCash,
        if (countedCash != null) 'countedCash': countedCash,
        if (cashDiscrepancy != null) 'cashDiscrepancy': cashDiscrepancy,
        if (cashDiscrepancyReason != null)
          'cashDiscrepancyReason': cashDiscrepancyReason,
        if (expectedTransfer != null) 'expectedTransfer': expectedTransfer,
        if (confirmedTransfer != null) 'confirmedTransfer': confirmedTransfer,
        if (transferDiscrepancy != null)
          'transferDiscrepancy': transferDiscrepancy,
        if (transferDiscrepancyReason != null)
          'transferDiscrepancyReason': transferDiscrepancyReason,
        if (preOpenReceived != null) 'preOpenReceived': preOpenReceived,
        if (withdrawalAmount != null) 'withdrawalAmount': withdrawalAmount,
        if (remainingCash != null) 'remainingCash': remainingCash,
        if (paymentsCount != null) 'paymentsCount': paymentsCount,
        if (note != null) 'note': note,
      };

  factory CashShift.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data()!;
    return CashShift(
      id: snap.id,
      status: CashShiftStatus.fromId(data['status'] as String?),
      businessDate: data['businessDate'] as String? ?? '',
      openedBy: data['openedBy'] as String? ?? '',
      openedByName: data['openedByName'] as String? ?? '',
      openedAt: _readDate(data['openedAt']) ?? AppClock.now(),
      openingFloat: (data['openingFloat'] as num?) ?? 0,
      periodStart:
          _readDate(data['periodStart']) ?? _readDate(data['openedAt']) ??
              AppClock.now(),
      closedBy: data['closedBy'] as String?,
      closedByName: data['closedByName'] as String?,
      closedAt: _readDate(data['closedAt']),
      expectedCash: data['expectedCash'] as num?,
      countedCash: data['countedCash'] as num?,
      cashDiscrepancy: data['cashDiscrepancy'] as num?,
      cashDiscrepancyReason: data['cashDiscrepancyReason'] as String?,
      expectedTransfer: data['expectedTransfer'] as num?,
      confirmedTransfer: data['confirmedTransfer'] as num?,
      transferDiscrepancy: data['transferDiscrepancy'] as num?,
      transferDiscrepancyReason: data['transferDiscrepancyReason'] as String?,
      preOpenReceived: data['preOpenReceived'] as num?,
      withdrawalAmount: data['withdrawalAmount'] as num?,
      remainingCash: data['remainingCash'] as num?,
      paymentsCount: (data['paymentsCount'] as num?)?.toInt(),
      note: data['note'] as String?,
    );
  }

  static DateTime? _readDate(dynamic raw) {
    if (raw is Timestamp) return AppClock.fromInstant(raw.toDate());
    return null;
  }
}
