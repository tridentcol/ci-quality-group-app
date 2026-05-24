import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Acción registrada en la subcolección `settings/sales_delegation/history`.
/// Append-only: cada activación/desactivación crea una entry.
enum SalesDelegationAction {
  activated,
  deactivated;

  String get id => name;

  static SalesDelegationAction fromId(String? id) =>
      SalesDelegationAction.values.firstWhere(
        (a) => a.id == id,
        orElse: () => SalesDelegationAction.deactivated,
      );
}

class SalesDelegationHistoryEntry {
  const SalesDelegationHistoryEntry({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.actorName,
    required this.at,
    this.startsAt,
    this.expiresAt,
    this.note,
  });

  final String id;
  final SalesDelegationAction action;
  final String actorUid;
  final String actorName;
  final DateTime at;

  /// Solo presente cuando [action] == [SalesDelegationAction.activated] y
  /// el admin programó un inicio diferido.
  final DateTime? startsAt;

  /// Solo presente cuando [action] == [SalesDelegationAction.activated] y
  /// el admin eligió un vencimiento.
  final DateTime? expiresAt;

  /// Solo presente para activations con nota.
  final String? note;

  Map<String, dynamic> toMap() => {
        'action': action.id,
        'actorUid': actorUid,
        'actorName': actorName,
        'at': Timestamp.fromDate(AppClock.toInstant(at)),
        if (startsAt != null)
          'startsAt': Timestamp.fromDate(AppClock.toInstant(startsAt!)),
        if (expiresAt != null)
          'expiresAt': Timestamp.fromDate(AppClock.toInstant(expiresAt!)),
        if (note != null) 'note': note,
      };

  factory SalesDelegationHistoryEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data()!;
    return SalesDelegationHistoryEntry(
      id: snap.id,
      action: SalesDelegationAction.fromId(data['action'] as String?),
      actorUid: data['actorUid'] as String,
      actorName: data['actorName'] as String,
      at: _readDate(data['at']) ?? AppClock.now(),
      startsAt: _readDate(data['startsAt']),
      expiresAt: _readDate(data['expiresAt']),
      note: data['note'] as String?,
    );
  }

  static DateTime? _readDate(dynamic raw) {
    if (raw is Timestamp) return AppClock.fromInstant(raw.toDate());
    return null;
  }
}
