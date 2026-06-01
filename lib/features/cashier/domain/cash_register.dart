import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Estado runtime de la caja: singleton en `settings/cash_register`.
///
/// Es la "verdad rápida" de si hay un turno abierto, quién lo abrió y cuál
/// es la ventana del dinero en curso. El detalle de cada turno vive en
/// `cash_shifts/{shiftId}`; este doc solo guarda lo necesario para el
/// banner global, los botones de la pantalla y la precarga de la base.
///
/// `periodStart` materializa la **ventana contigua**: cada turno reconcilia
/// el dinero recibido desde el cierre anterior (`lastClosedAt`) hasta su
/// propio cierre. Así ningún movimiento se pierde aunque la caja se cierre
/// temprano, tarde o cruce la medianoche.
class CashRegister {
  const CashRegister({
    required this.isOpen,
    this.openShiftId,
    this.openedBy,
    this.openedByName,
    this.openedAt,
    this.openingFloat,
    this.periodStart,
    this.lastClosedAt,
    this.lastRemainingCash,
  });

  /// `true` mientras hay un turno abierto.
  final bool isOpen;

  /// Id del doc en `cash_shifts` del turno abierto. Null si está cerrada.
  final String? openShiftId;

  final String? openedBy;
  final String? openedByName;
  final DateTime? openedAt;

  /// Base inicial declarada al abrir el turno vigente.
  final num? openingFloat;

  /// Inicio de la ventana del dinero del turno abierto = `closedAt` del
  /// cierre anterior (o `openedAt` si es el primer cierre histórico).
  final DateTime? periodStart;

  /// `closedAt` del último cierre. Semilla del `periodStart` de la próxima
  /// apertura — lo que hace contigua la ventana.
  final DateTime? lastClosedAt;

  /// `remainingCash` del último cierre. Precarga la base del próximo turno
  /// (lo que quedó físicamente en el cajón).
  final num? lastRemainingCash;

  factory CashRegister.closed() => const CashRegister(isOpen: false);

  Map<String, dynamic> toMap() => {
        'isOpen': isOpen,
        if (openShiftId != null) 'openShiftId': openShiftId,
        if (openedBy != null) 'openedBy': openedBy,
        if (openedByName != null) 'openedByName': openedByName,
        if (openedAt != null)
          'openedAt': Timestamp.fromDate(AppClock.toInstant(openedAt!)),
        if (openingFloat != null) 'openingFloat': openingFloat,
        if (periodStart != null)
          'periodStart': Timestamp.fromDate(AppClock.toInstant(periodStart!)),
        if (lastClosedAt != null)
          'lastClosedAt': Timestamp.fromDate(AppClock.toInstant(lastClosedAt!)),
        if (lastRemainingCash != null) 'lastRemainingCash': lastRemainingCash,
      };

  factory CashRegister.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (!snap.exists) return CashRegister.closed();
    final data = snap.data()!;
    return CashRegister(
      isOpen: (data['isOpen'] as bool?) ?? false,
      openShiftId: data['openShiftId'] as String?,
      openedBy: data['openedBy'] as String?,
      openedByName: data['openedByName'] as String?,
      openedAt: _readDate(data['openedAt']),
      openingFloat: data['openingFloat'] as num?,
      periodStart: _readDate(data['periodStart']),
      lastClosedAt: _readDate(data['lastClosedAt']),
      lastRemainingCash: data['lastRemainingCash'] as num?,
    );
  }

  static DateTime? _readDate(dynamic raw) {
    if (raw is Timestamp) return AppClock.fromInstant(raw.toDate());
    return null;
  }
}
