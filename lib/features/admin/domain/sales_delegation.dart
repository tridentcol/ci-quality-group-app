import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Estado del modo "delegación caja": singleton que vive en
/// `settings/sales_delegation`. Cuando está vigente, el rol sales puede
/// registrar el pago de una venta en el mismo submit del formulario.
///
/// `active` es la intención del admin; la vigencia REAL se evalúa con
/// [isCurrentlyActive], que respeta tanto el inicio programado
/// ([startsAt]) como el vencimiento ([expiresAt]).
class SalesDelegation {
  const SalesDelegation({
    required this.active,
    this.activatedBy,
    this.activatedByName,
    this.activatedAt,
    this.startsAt,
    this.expiresAt,
    this.note,
    this.deactivatedBy,
    this.deactivatedByName,
    this.deactivatedAt,
  });

  final bool active;
  final String? activatedBy;
  final String? activatedByName;
  final DateTime? activatedAt;

  /// Cuándo empieza a estar vigente. Null = vigente desde [activatedAt].
  /// Si está programada para el futuro, [isCurrentlyActive] devuelve false
  /// hasta que llegue ese momento.
  final DateTime? startsAt;

  /// Cuándo deja de estar vigente. Null = sin vencimiento (manual).
  final DateTime? expiresAt;

  final String? note;
  final String? deactivatedBy;
  final String? deactivatedByName;
  final DateTime? deactivatedAt;

  /// Vigencia real considerando el reloj: el toggle puede estar en `true`
  /// pero todavía no haber empezado, o ya haber expirado. Las rules
  /// hacen la misma evaluación contra `request.time` (red de seguridad).
  bool get isCurrentlyActive {
    if (!active) return false;
    final now = AppClock.now();
    if (startsAt != null && startsAt!.isAfter(now)) return false;
    if (expiresAt != null && !expiresAt!.isAfter(now)) return false;
    return true;
  }

  /// `true` cuando el toggle está en `active` pero todavía no comenzó.
  bool get isScheduled {
    if (!active || startsAt == null) return false;
    return startsAt!.isAfter(AppClock.now());
  }

  /// `true` cuando el toggle quedó en `active` pero ya pasó [expiresAt].
  /// Caso cosmético — el admin puede limpiarlo desactivando manualmente.
  bool get hasExpired {
    if (!active || expiresAt == null) return false;
    return !expiresAt!.isAfter(AppClock.now());
  }

  factory SalesDelegation.inactive() => const SalesDelegation(active: false);

  Map<String, dynamic> toMap() => {
        'active': active,
        if (activatedBy != null) 'activatedBy': activatedBy,
        if (activatedByName != null) 'activatedByName': activatedByName,
        if (activatedAt != null)
          'activatedAt': Timestamp.fromDate(AppClock.toInstant(activatedAt!)),
        if (startsAt != null)
          'startsAt': Timestamp.fromDate(AppClock.toInstant(startsAt!)),
        if (expiresAt != null)
          'expiresAt': Timestamp.fromDate(AppClock.toInstant(expiresAt!)),
        if (note != null) 'note': note,
        if (deactivatedBy != null) 'deactivatedBy': deactivatedBy,
        if (deactivatedByName != null) 'deactivatedByName': deactivatedByName,
        if (deactivatedAt != null)
          'deactivatedAt':
              Timestamp.fromDate(AppClock.toInstant(deactivatedAt!)),
      };

  factory SalesDelegation.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (!snap.exists) return SalesDelegation.inactive();
    final data = snap.data()!;
    return SalesDelegation(
      active: (data['active'] as bool?) ?? false,
      activatedBy: data['activatedBy'] as String?,
      activatedByName: data['activatedByName'] as String?,
      activatedAt: _readDate(data['activatedAt']),
      startsAt: _readDate(data['startsAt']),
      expiresAt: _readDate(data['expiresAt']),
      note: data['note'] as String?,
      deactivatedBy: data['deactivatedBy'] as String?,
      deactivatedByName: data['deactivatedByName'] as String?,
      deactivatedAt: _readDate(data['deactivatedAt']),
    );
  }

  static DateTime? _readDate(dynamic raw) {
    if (raw is Timestamp) return AppClock.fromInstant(raw.toDate());
    return null;
  }
}
