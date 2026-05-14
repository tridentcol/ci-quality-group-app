import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/firestore_paths.dart';
import '../../core/constants/roles.dart';
import '../../core/utils/clock.dart';
import '../../features/auth/data/auth_repository.dart';
import '../models/app_notification.dart';

/// Acceso a la colección `notifications`.
///
/// Triggers (writes): los repos de sales y cashier llaman a [emitInTxn]
/// dentro de su `runTransaction` para que el evento y la notif se
/// commiteen atómicamente. Para casos sin transacción se expone [emit].
///
/// Reads: dos queries paralelas (por uid y por rol) — Firestore no
/// permite OR en `where`. El merge + dedup + filtro por fecha se hacen
/// en cliente.
class NotificationsRepository {
  NotificationsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.notifications);

  /// Escribe la notif dentro de una transacción en curso. Devuelve la ref
  /// para que el caller pueda referenciarla si necesita (típicamente no).
  ///
  /// Usar este path desde repos que ya están adentro de runTransaction
  /// (caso de cashier). Cualquier escritura en una transacción que
  /// despacha un read después rompe — por eso este método solo hace
  /// `txn.set`. El doc no necesita un read previo.
  DocumentReference<Map<String, dynamic>> emitInTxn(
    Transaction txn, {
    required NotificationType type,
    required String title,
    required String body,
    String? saleId,
    required String actorUid,
    required String actorName,
    List<String> targetUids = const [],
    List<AppRole> targetRoles = const [],
    Map<String, dynamic> data = const {},
  }) {
    final ref = _col.doc();
    final notif = _build(
      id: ref.id,
      type: type,
      title: title,
      body: body,
      saleId: saleId,
      actorUid: actorUid,
      actorName: actorName,
      targetUids: targetUids,
      targetRoles: targetRoles,
      data: data,
    );
    txn.set(ref, notif.toMap());
    return ref;
  }

  /// Versión standalone (sin transacción). Para repos que generan la
  /// notif como side-effect de una operación que no es transaccional
  /// (ej. comentarios futuros, settings changes, etc.).
  Future<AppNotification> emit({
    required NotificationType type,
    required String title,
    required String body,
    String? saleId,
    required String actorUid,
    required String actorName,
    List<String> targetUids = const [],
    List<AppRole> targetRoles = const [],
    Map<String, dynamic> data = const {},
  }) async {
    final ref = _col.doc();
    final notif = _build(
      id: ref.id,
      type: type,
      title: title,
      body: body,
      saleId: saleId,
      actorUid: actorUid,
      actorName: actorName,
      targetUids: targetUids,
      targetRoles: targetRoles,
      data: data,
    );
    await ref.set(notif.toMap());
    return notif;
  }

  AppNotification _build({
    required String id,
    required NotificationType type,
    required String title,
    required String body,
    String? saleId,
    required String actorUid,
    required String actorName,
    required List<String> targetUids,
    required List<AppRole> targetRoles,
    required Map<String, dynamic> data,
  }) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      saleId: saleId,
      createdAt: AppClock.now(),
      createdBy: actorUid,
      createdByName: actorName,
      targetUids: targetUids,
      targetRoles: targetRoles.map((r) => r.id).toList(),
      data: data,
    );
  }

  /// Stream de las notifs visibles al usuario dado. Merge de:
  ///   1. `targetUids array-contains uid`
  ///   2. `targetRoles array-contains role.id`
  /// Dedupe por id, sort desc por createdAt, recorta a los últimos 30 días
  /// para que el sheet no crezca indefinido (las notifs antiguas se
  /// quedan en backend pero ya no se muestran).
  Stream<List<AppNotification>> watchForUser({
    required String uid,
    required AppRole role,
  }) {
    final byUid = _col
        .where('targetUids', arrayContains: uid)
        .snapshots()
        .map(_decode);
    final byRole = _col
        .where('targetRoles', arrayContains: role.id)
        .snapshots()
        .map(_decode);
    return _merge(byUid, byRole);
  }

  Stream<List<AppNotification>> _merge(
    Stream<List<AppNotification>> a,
    Stream<List<AppNotification>> b,
  ) {
    final controller = StreamController<List<AppNotification>>();
    List<AppNotification> latestA = const [];
    List<AppNotification> latestB = const [];
    var hasA = false;
    var hasB = false;

    void push() {
      if (!hasA && !hasB) return;
      final byId = <String, AppNotification>{};
      for (final n in latestA) {
        byId[n.id] = n;
      }
      for (final n in latestB) {
        byId[n.id] = n;
      }
      final cutoff = AppClock.now().subtract(const Duration(days: 30));
      final list = byId.values
          .where((n) => n.createdAt.isAfter(cutoff))
          .toList()
        ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
      controller.add(list);
    }

    final subA = a.listen(
      (data) {
        latestA = data;
        hasA = true;
        push();
      },
      onError: controller.addError,
    );
    final subB = b.listen(
      (data) {
        latestB = data;
        hasB = true;
        push();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await subA.cancel();
      await subB.cancel();
    };

    return controller.stream;
  }

  List<AppNotification> _decode(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(AppNotification.fromSnapshot).toList();

  /// Marca una notif como leída para el uid dado (idempotente — usa
  /// arrayUnion).
  Future<void> markAsRead({required String id, required String uid}) {
    return _col.doc(id).update({
      'readBy': FieldValue.arrayUnion([uid]),
    });
  }

  /// Marca todas las notifs dadas como leídas para el uid en un batch.
  Future<void> markAllAsRead({
    required Iterable<String> ids,
    required String uid,
  }) async {
    final batch = _firestore.batch();
    for (final id in ids) {
      batch.update(_col.doc(id), {
        'readBy': FieldValue.arrayUnion([uid]),
      });
    }
    await batch.commit();
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(FirebaseFirestore.instance);
});

/// Stream de notificaciones del usuario actual. Si no hay sesión o
/// perfil resuelto devuelve lista vacía (no rompe la UI).
final myNotificationsProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) {
  ref.watch(authStateProvider);
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  if (profile == null) return Stream.value(const []);
  return ref.watch(notificationsRepositoryProvider).watchForUser(
        uid: profile.uid,
        role: profile.role,
      );
});

/// Cantidad de no leídas (derived). Se usa en el badge del bell.
final unreadNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  final list = ref.watch(myNotificationsProvider).valueOrNull ?? const [];
  if (profile == null) return 0;
  return list.where((n) => !n.isReadBy(profile.uid)).length;
});
