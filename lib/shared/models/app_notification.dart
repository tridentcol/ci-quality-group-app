import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import '../../core/utils/clock.dart';

/// Tipos de evento que generan una notificación in-app.
///
/// Cada tipo decide a quién va dirigido y qué ícono/título se renderea
/// en la lista. Los strings serializados se persisten en Firestore para
/// poder filtrar y agrupar; agregar un tipo nuevo es un cambio compatible
/// (los clientes viejos lo verán como `unknown`).
enum NotificationType {
  saleCreated('sale_created'),
  saleProcessed('sale_processed'),
  saleCanceled('sale_canceled'),
  saleReturnedToSales('sale_returned_to_sales'),
  saleMarkedLoss('sale_marked_loss'),
  paymentVoided('payment_voided'),
  unknown('unknown');

  const NotificationType(this.id);
  final String id;

  static NotificationType fromId(String? id) {
    if (id == null) return NotificationType.unknown;
    for (final t in NotificationType.values) {
      if (t.id == id) return t;
    }
    return NotificationType.unknown;
  }

  IconData get icon => switch (this) {
        NotificationType.saleCreated => Icons.receipt_long_outlined,
        NotificationType.saleProcessed => Icons.check_circle_outline,
        NotificationType.saleCanceled => Icons.cancel_outlined,
        NotificationType.saleReturnedToSales => Icons.undo_outlined,
        NotificationType.saleMarkedLoss => Icons.warning_amber_outlined,
        NotificationType.paymentVoided => Icons.history_outlined,
        NotificationType.unknown => Icons.notifications_outlined,
      };

  /// Color "acento" del item en la lista. Usa la paleta de la app para
  /// que coincida con StatePill y _CashierSaleCard.
  Color accentFor(ColorScheme scheme) => switch (this) {
        NotificationType.saleCreated => const Color(0xFFE6A100),
        NotificationType.saleProcessed => const Color(0xFF2E7D32),
        NotificationType.saleCanceled =>
          scheme.onSurface.withValues(alpha: 0.55),
        NotificationType.saleReturnedToSales => const Color(0xFFE6A100),
        NotificationType.saleMarkedLoss => scheme.error,
        NotificationType.paymentVoided => scheme.error,
        NotificationType.unknown => scheme.primary,
      };
}

/// Notificación in-app. Una sola colección plana `notifications/{id}`,
/// con targets duales por uid o por rol (Firestore no permite OR en
/// `where`, por eso necesitamos los dos arrays — la unión se resuelve
/// en cliente con dos streams paralelos).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.saleId,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
    this.targetUids = const [],
    this.targetRoles = const [],
    this.readBy = const [],
    this.data = const {},
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;

  /// Id de la venta asociada. Lo usa el sheet para navegar al recurso al
  /// tocar el item.
  final String? saleId;

  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  /// uids específicos que reciben la notif. Combina con [targetRoles] via OR.
  final List<String> targetUids;

  /// Roles que reciben la notif (ej. `cajero`, `admin`). Combina con
  /// [targetUids] via OR.
  final List<String> targetRoles;

  /// uids que ya marcaron como leída.
  final List<String> readBy;

  /// Payload extra para navegación o agrupación. Se persiste tal cual.
  final Map<String, dynamic> data;

  bool isReadBy(String uid) => readBy.contains(uid);

  /// Determina si esta notif aplica al usuario dado por uid+rol. Se usa
  /// para dedup en cliente cuando los dos streams (uids/roles) traen el
  /// mismo doc.
  bool reaches({required String uid, required AppRole role}) {
    if (targetUids.contains(uid)) return true;
    return targetRoles.contains(role.id);
  }

  Map<String, dynamic> toMap() => {
        'type': type.id,
        'title': title,
        'body': body,
        'saleId': saleId,
        'createdAt': Timestamp.fromDate(AppClock.toInstant(createdAt)),
        'createdBy': createdBy,
        'createdByName': createdByName,
        'targetUids': targetUids,
        'targetRoles': targetRoles,
        'readBy': readBy,
        'data': data,
      };

  factory AppNotification.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data()!;
    return AppNotification(
      id: snap.id,
      type: NotificationType.fromId(data['type'] as String?),
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      saleId: data['saleId'] as String?,
      createdAt:
          AppClock.fromInstant((data['createdAt'] as Timestamp).toDate()),
      createdBy: data['createdBy'] as String? ?? '',
      createdByName: data['createdByName'] as String? ?? '',
      targetUids: (data['targetUids'] as List?)?.cast<String>() ?? const [],
      targetRoles: (data['targetRoles'] as List?)?.cast<String>() ?? const [],
      readBy: (data['readBy'] as List?)?.cast<String>() ?? const [],
      data: Map<String, dynamic>.from(data['data'] as Map? ?? const {}),
    );
  }
}
