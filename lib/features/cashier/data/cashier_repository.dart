import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/clock.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../sales/domain/sale.dart';

/// Operaciones que el rol caja (o admin actuando como caja) ejecuta sobre
/// una venta. Todas van en `runTransaction` para no dejar el doc en un
/// estado inconsistente si dos cajeros la tocan a la vez.
///
/// El motor financiero (registrar abono, marcar pérdida, plazo) entra en
/// Fase 4 — este archivo solo cubre el workflow del estado.
class CashierRepository {
  CashierRepository(this._firestore);

  final FirebaseFirestore _firestore;

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
      final state = SaleState.fromId(snap.data()?['state'] as String?);
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
      final state = SaleState.fromId(snap.data()?['state'] as String?);
      if (state != SaleState.enProceso) {
        throw StateError(
          'Solo se puede devolver una solicitud en proceso '
          '(estado actual: ${state.id}).',
        );
      }
      txn.update(ref, {
        'state': SaleState.generada.id,
        'updatedAt': _now(),
        if (reason != null && reason.trim().isNotEmpty)
          'returnReason': reason.trim(),
      });
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
      final state = SaleState.fromId(snap.data()?['state'] as String?);
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
}

final cashierRepositoryProvider = Provider<CashierRepository>((ref) {
  return CashierRepository(FirebaseFirestore.instance);
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
