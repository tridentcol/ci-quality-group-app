import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/services/notifications_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../domain/sales_delegation.dart';
import '../domain/sales_delegation_history_entry.dart';

/// Doc id fijo del singleton dentro de `settings/`.
const String _delegationDocId = 'sales_delegation';

/// Acceso al modo "delegación caja". El singleton vive en
/// `settings/sales_delegation`; cada activación/desactivación produce una
/// entry en la subcolección append-only `history/`.
///
/// Toda operación pasa por `runTransaction` para que doc principal e
/// history queden siempre consistentes: si el set del doc falla, la entry
/// no se crea, y viceversa.
class SalesDelegationRepository {
  SalesDelegationRepository(this._firestore, this._notifications);

  final FirebaseFirestore _firestore;
  final NotificationsRepository _notifications;

  DocumentReference<Map<String, dynamic>> get _docRef => _firestore
      .collection(FirestorePaths.settings)
      .doc(_delegationDocId);

  CollectionReference<Map<String, dynamic>> get _historyCol =>
      _docRef.collection('history');

  /// Stream del singleton. Cuando el doc no existe (caso inicial) emite
  /// [SalesDelegation.inactive] para que la UI no tenga que ramificar.
  Stream<SalesDelegation> watch() {
    return _docRef.snapshots().map((snap) {
      if (!snap.exists) return SalesDelegation.inactive();
      return SalesDelegation.fromSnapshot(snap);
    });
  }

  /// Últimas N entries del historial, más recientes primero.
  Stream<List<SalesDelegationHistoryEntry>> watchHistory({int limit = 20}) {
    return _historyCol
        .orderBy('at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map(SalesDelegationHistoryEntry.fromSnapshot).toList(),);
  }

  /// Activa la delegación. [startsAt] puede ser futuro (programación) o
  /// null para vigencia inmediata. [expiresAt] puede ser null (sin
  /// vencimiento). Escribe el singleton + entry en history en una sola
  /// transacción.
  Future<void> activate({
    required AppUser actor,
    DateTime? startsAt,
    DateTime? expiresAt,
    String? note,
  }) async {
    final now = AppClock.now();
    final cleanedNote = note?.trim();
    final effectiveStart = startsAt ?? now;
    await _firestore.runTransaction((txn) async {
      await txn.get(_docRef);
      final docData = SalesDelegation(
        active: true,
        activatedBy: actor.uid,
        activatedByName: actor.fullName,
        activatedAt: now,
        startsAt: startsAt,
        expiresAt: expiresAt,
        note: (cleanedNote != null && cleanedNote.isNotEmpty)
            ? cleanedNote
            : null,
      ).toMap();
      // `set` sin merge: arranca un ciclo limpio (los campos `deactivated*`
      // del ciclo anterior no deben sobrevivir a una nueva activación).
      txn.set(_docRef, docData);
      txn.set(_historyCol.doc(), SalesDelegationHistoryEntry(
        id: '',
        action: SalesDelegationAction.activated,
        actorUid: actor.uid,
        actorName: actor.fullName,
        at: now,
        startsAt: effectiveStart.isAfter(now) ? startsAt : null,
        expiresAt: expiresAt,
        note: (cleanedNote != null && cleanedNote.isNotEmpty)
            ? cleanedNote
            : null,
      ).toMap(),);
      _notifications.emitInTxn(
        txn,
        type: NotificationType.delegationActivated,
        title: 'Modo delegación caja activado',
        body: _buildActivatedBody(
          actor: actor,
          startsAt: effectiveStart.isAfter(now) ? startsAt : null,
          expiresAt: expiresAt,
        ),
        actorUid: actor.uid,
        actorName: actor.fullName,
        // Cajero y admin reciben la señal — el sales que va a usar la
        // delegación se entera por el banner global, no por la bell.
        targetRoles: const [AppRole.cajero, AppRole.admin],
      );
    });
  }

  /// Desactiva la delegación. Conserva los campos de la activación previa
  /// (quién/cuándo activó, expiresAt original) para trazabilidad y agrega
  /// los `deactivated*`. Una nueva activate posterior resetea todo.
  Future<void> deactivate({required AppUser actor}) async {
    final now = AppClock.now();
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(_docRef);
      // Si nunca se activó (doc inexistente), `txn.update` revienta con
      // un mensaje de servidor opaco. Disparamos un StateError claro
      // para que la UI muestre algo útil con friendlyError.
      if (!snap.exists) {
        throw StateError('No hay delegación caja activa para desactivar.');
      }
      txn.update(_docRef, {
        'active': false,
        'deactivatedBy': actor.uid,
        'deactivatedByName': actor.fullName,
        'deactivatedAt': Timestamp.fromDate(AppClock.toInstant(now)),
      });
      txn.set(_historyCol.doc(), SalesDelegationHistoryEntry(
        id: '',
        action: SalesDelegationAction.deactivated,
        actorUid: actor.uid,
        actorName: actor.fullName,
        at: now,
      ).toMap(),);
      _notifications.emitInTxn(
        txn,
        type: NotificationType.delegationDeactivated,
        title: 'Modo delegación caja desactivado',
        body: '${actor.fullName} cerró la delegación caja.',
        actorUid: actor.uid,
        actorName: actor.fullName,
        targetRoles: const [AppRole.cajero, AppRole.admin],
      );
    });
  }

  static String _buildActivatedBody({
    required AppUser actor,
    DateTime? startsAt,
    DateTime? expiresAt,
  }) {
    final parts = <String>['${actor.fullName} habilitó delegación caja'];
    if (startsAt != null) {
      parts.add('desde ${formatDateTime(startsAt)}');
    }
    if (expiresAt != null) {
      parts.add('hasta ${formatDateTime(expiresAt)}');
    } else if (startsAt == null) {
      parts.add('sin vencimiento');
    }
    return '${parts.join(' ')}.';
  }
}

final salesDelegationRepositoryProvider =
    Provider<SalesDelegationRepository>((ref) {
  return SalesDelegationRepository(
    FirebaseFirestore.instance,
    ref.watch(notificationsRepositoryProvider),
  );
});

final salesDelegationProvider =
    StreamProvider.autoDispose<SalesDelegation>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(salesDelegationRepositoryProvider).watch();
});

final salesDelegationHistoryProvider = StreamProvider.autoDispose<
    List<SalesDelegationHistoryEntry>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(salesDelegationRepositoryProvider).watchHistory();
});
