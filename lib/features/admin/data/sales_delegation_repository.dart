import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/clock.dart';
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
  SalesDelegationRepository(this._firestore);

  final FirebaseFirestore _firestore;

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
    });
  }

  /// Desactiva la delegación. Conserva los campos de la activación previa
  /// (quién/cuándo activó, expiresAt original) para trazabilidad y agrega
  /// los `deactivated*`. Una nueva activate posterior resetea todo.
  Future<void> deactivate({required AppUser actor}) async {
    final now = AppClock.now();
    await _firestore.runTransaction((txn) async {
      await txn.get(_docRef);
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
    });
  }
}

final salesDelegationRepositoryProvider =
    Provider<SalesDelegationRepository>((ref) {
  return SalesDelegationRepository(FirebaseFirestore.instance);
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
