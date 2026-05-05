import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_match.dart';
import '../domain/master_list.dart';

/// Mapeo de listId → campo del documento `sales` que lo referencia. Cuando
/// el admin fusiona items de una de estas listas, además de borrar los
/// duplicados del catálogo se reescriben las ventas existentes para que
/// apunten al canónico (sino quedarían con un nombre "huérfano").
///
/// Si una lista no está en este map, su botón "Detectar duplicados" no
/// aparece — la limpieza tendría que ser manual con el delete de cada
/// item, sin actualizar las ventas históricas.
const Map<String, String> _saleFieldByListId = {
  'payers': 'payerName',
  'providers': 'providerName',
  'materials': 'material',
  'material_variants': 'materialVariant',
  'units': 'unit',
  'payment_methods': 'paymentMethod',
};

bool listSupportsMerge(String listId) =>
    _saleFieldByListId.containsKey(listId);

String? saleFieldFor(String listId) => _saleFieldByListId[listId];

/// Un grupo de items que probablemente representan la misma entidad
/// (típicamente una persona escrita con typos distintos). Se construye
/// por cierre transitivo de pares similares: si A~B y B~C, los tres
/// forman un cluster aunque A y C no se parezcan directamente.
class DuplicateCluster {
  DuplicateCluster({
    required this.items,
    required this.refCounts,
  });

  /// Todos los items del cluster.
  final List<MasterListItem> items;

  /// Cuántas ventas apuntan a cada `value` del cluster. Sirve para
  /// sugerir como canónico al más usado y para mostrar el "costo" del
  /// merge ("se actualizarán 12 ventas").
  final Map<String, int> refCounts;

  /// El item que el sistema sugiere como canónico:
  ///  1. El que tiene más ventas apuntándole (la mayoría ya está
  ///     "votando" por ese spelling).
  ///  2. En empate, el que NO es sugerencia de un usuario (más oficial).
  ///  3. En empate, alfabético.
  MasterListItem get suggestedCanonical {
    final sorted = [...items];
    sorted.sort((a, b) {
      final cmpRefs = (refCounts[b.value] ?? 0)
          .compareTo(refCounts[a.value] ?? 0);
      if (cmpRefs != 0) return cmpRefs;
      if (a.userSuggested != b.userSuggested) {
        return a.userSuggested ? 1 : -1;
      }
      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });
    return sorted.first;
  }

  int totalSalesAffected(MasterListItem canonical) {
    return items
        .where((it) => it.id != canonical.id)
        .fold<int>(0, (sum, it) => sum + (refCounts[it.value] ?? 0));
  }
}

class DuplicateMergeRequest {
  const DuplicateMergeRequest({
    required this.canonical,
    required this.duplicates,
  });

  /// Item que se conserva — todos los duplicados se redirigen aquí.
  final MasterListItem canonical;

  /// Items que se eliminarán y cuyas referencias en `sales` se actualizan
  /// al `canonical.value`.
  final List<MasterListItem> duplicates;
}

class DuplicateMergeResult {
  const DuplicateMergeResult({
    required this.salesUpdated,
    required this.itemsDeleted,
  });
  final int salesUpdated;
  final int itemsDeleted;
}

/// Calcula la "mejor" distancia entre dos strings probando distintas
/// normalizaciones. Sirve para detectar pares parecidos.
int _bestDistance(String a, String b) {
  return [
    levenshtein(normalizeForMatch(a), normalizeForMatch(b)),
    levenshtein(normalizeAggressive(a), normalizeAggressive(b)),
    levenshtein(normalizePhonetic(a), normalizePhonetic(b)),
  ].reduce(math.min);
}

int _threshold(String a, String b) {
  final maxLen = math.max(a.length, b.length);
  return math.max(1, math.min(4, (maxLen * 0.25).ceil()));
}

class DuplicateService {
  DuplicateService(this._firestore);
  final FirebaseFirestore _firestore;

  /// Detecta clusters de items duplicados en [listId]. Lee TODOS los
  /// items del catálogo + TODAS las ventas (para contar referencias).
  /// Para 1000 ventas son ~1 MB de descarga; aceptable porque el botón
  /// solo lo toca el admin esporádicamente.
  Future<List<DuplicateCluster>> findClusters({
    required String listId,
  }) async {
    final saleField = saleFieldFor(listId);
    if (saleField == null) {
      throw StateError('Lista "$listId" no admite merge automático.');
    }

    // 1. Items del catálogo
    final itemsSnap = await _firestore
        .collection('master_lists')
        .doc(listId)
        .collection('items')
        .get();
    final items = itemsSnap.docs
        .map(MasterListItem.fromSnapshot)
        .where((it) => it.active)
        .toList();
    if (items.length < 2) return const [];

    // 2. Conteo de referencias en sales (un solo .get(), conteo en RAM)
    final salesSnap = await _firestore.collection('sales').get();
    final refCounts = <String, int>{};
    for (final d in salesSnap.docs) {
      final v = d.data()[saleField] as String?;
      if (v == null || v.isEmpty) continue;
      refCounts[v] = (refCounts[v] ?? 0) + 1;
    }

    // 3. Pares parecidos (O(n²) pero n suele ser <200)
    final pairs = <_Pair>[];
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final a = items[i];
        final b = items[j];
        final d = _bestDistance(a.value, b.value);
        if (d <= _threshold(a.value, b.value)) {
          pairs.add(_Pair(a, b, d));
        }
      }
    }
    if (pairs.isEmpty) return const [];

    // 4. Cierre transitivo con union-find
    final parent = <String, String>{};
    String find(String x) {
      if (parent[x] == x) return x;
      final p = parent[x] ?? x;
      parent[x] = p == x ? x : find(p);
      return parent[x]!;
    }

    void union(String a, String b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (final p in pairs) {
      parent[p.a.id] ??= p.a.id;
      parent[p.b.id] ??= p.b.id;
      union(p.a.id, p.b.id);
    }

    final groupsById = <String, List<MasterListItem>>{};
    for (final p in pairs) {
      for (final it in [p.a, p.b]) {
        final root = find(it.id);
        groupsById.putIfAbsent(root, () => []);
        if (!groupsById[root]!.any((x) => x.id == it.id)) {
          groupsById[root]!.add(it);
        }
      }
    }

    final clusters = groupsById.values.map((groupItems) {
      final counts = <String, int>{
        for (final it in groupItems) it.value: refCounts[it.value] ?? 0,
      };
      return DuplicateCluster(items: groupItems, refCounts: counts);
    }).toList();

    // Orden estable: clusters con más ventas afectadas primero (más
    // urgentes), después los con más items.
    clusters.sort((x, y) {
      final cmpAffected = y.totalSalesAffected(y.suggestedCanonical).compareTo(
            x.totalSalesAffected(x.suggestedCanonical),
          );
      if (cmpAffected != 0) return cmpAffected;
      return y.items.length.compareTo(x.items.length);
    });

    return clusters;
  }

  /// Ejecuta los merges en orden. Por cada request:
  ///   - Para cada duplicate: query `sales` donde el campo == duplicate.value,
  ///     update todos a canonical.value en batches de 400.
  ///   - Borra el item duplicado del catálogo.
  ///
  /// Si algo falla a mitad de camino, los merges previos quedan aplicados
  /// (no es transaccional global porque las queries son demasiado grandes
  /// para una sola transacción de Firestore). El resumen devuelto refleja
  /// solo lo que efectivamente se aplicó.
  Future<DuplicateMergeResult> applyMerges({
    required String listId,
    required List<DuplicateMergeRequest> requests,
  }) async {
    final saleField = saleFieldFor(listId);
    if (saleField == null) {
      throw StateError('Lista "$listId" no admite merge automático.');
    }

    var salesUpdated = 0;
    var itemsDeleted = 0;

    for (final req in requests) {
      for (final dup in req.duplicates) {
        // 1. Encontrar y actualizar las ventas que apuntan al duplicado.
        final salesSnap = await _firestore
            .collection('sales')
            .where(saleField, isEqualTo: dup.value)
            .get();

        const chunkSize = 400; // Firestore batch limit es 500
        for (var i = 0; i < salesSnap.docs.length; i += chunkSize) {
          final chunk = salesSnap.docs.skip(i).take(chunkSize).toList();
          final batch = _firestore.batch();
          for (final doc in chunk) {
            batch.update(doc.reference, {saleField: req.canonical.value});
          }
          await batch.commit();
          salesUpdated += chunk.length;
        }

        // 2. Borrar el item duplicado del catálogo.
        await _firestore
            .collection('master_lists')
            .doc(listId)
            .collection('items')
            .doc(dup.id)
            .delete();
        itemsDeleted += 1;
      }
    }

    return DuplicateMergeResult(
      salesUpdated: salesUpdated,
      itemsDeleted: itemsDeleted,
    );
  }
}

class _Pair {
  const _Pair(this.a, this.b, this.distance);
  final MasterListItem a;
  final MasterListItem b;
  final int distance;
}

final duplicateServiceProvider = Provider<DuplicateService>((ref) {
  return DuplicateService(FirebaseFirestore.instance);
});
