import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_match.dart';
import '../domain/master_list.dart';
import 'master_lists_repository.dart'
    show ListPropagation, propagateValueChange, propagationFor;

// La tabla canónica de propagaciones (`propagationFor`) y la función
// `propagateValueChange` viven en `master_lists_repository` para que
// `renameItem` y `applyMerges` compartan la misma lógica de propagación
// y no se desincronicen. Aquí solo se importan.

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
        .fold<int>(0, (acc, it) => acc + (refCounts[it.value] ?? 0));
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

/// Resultado de [DuplicateService.findClusters]: además de los clusters
/// devuelve cuántos valores se "rescataron" del log de ventas y se
/// agregaron al catálogo (porque la versión vieja de la app no
/// guardaba sugerencias automáticamente).
class FindClustersResult {
  const FindClustersResult({
    required this.clusters,
    required this.backfilled,
    required this.totalCatalogItems,
  });

  final List<DuplicateCluster> clusters;

  /// Cantidad de items que se agregaron al catálogo durante el sync,
  /// porque aparecían en `sales` pero faltaban en `master_lists/items`.
  final int backfilled;

  /// Total de items en el catálogo después del backfill.
  final int totalCatalogItems;
}

class DuplicateService {
  DuplicateService(this._firestore);
  final FirebaseFirestore _firestore;

  /// Detecta clusters de items duplicados en [listId].
  ///
  /// **Sincronización**: antes de detectar duplicados, lee `sales` y
  /// busca valores referenciados en `<saleField>` que NO estén en el
  /// catálogo. Los crea como `userSuggested:true` para que aparezcan
  /// en el detector. Esto es necesario porque la v1.0.0 de la app
  /// tenía un bug que solo guardaba sugerencias al presionar Enter,
  /// nunca al cambiar de campo — así que muchísimos nombres digitados
  /// quedaron solo en `sales` sin formalizar en el catálogo.
  ///
  /// Para 1000 ventas son ~1 MB de descarga; aceptable porque el botón
  /// solo lo toca el admin esporádicamente.
  Future<FindClustersResult> findClusters({
    required String listId,
  }) async {
    final ListPropagation? prop = propagationFor(listId);
    if (prop == null) {
      throw StateError('Lista "$listId" no admite merge automático.');
    }
    final target = prop.primary;

    // 1. Items existentes en el catálogo
    final itemsSnap = await _firestore
        .collection('master_lists')
        .doc(listId)
        .collection('items')
        .get();
    final existingItems = itemsSnap.docs
        .map(MasterListItem.fromSnapshot)
        .where((it) => it.active)
        .toList();
    final existingValues = existingItems.map((it) => it.value).toSet();

    // 2. Conteo de referencias en la colección primary del listId
    //    (sales para casi todas, workers para `worker_roles`). Un solo
    //    `.get()`, conteo en RAM. Si la lista guarda el value también
    //    dentro de un array `items[]` (caso material/variant/unit en
    //    Sale), también contamos referencias secundarias — pero
    //    deduplicamos por doc, así "esta venta referencia LAMINA" cuenta
    //    1 aunque LAMINA aparezca en items[0] y items[1].
    final docsSnap = await _firestore.collection(target.collection).get();
    final refCounts = <String, int>{};
    for (final d in docsSnap.docs) {
      final data = d.data();
      final valuesInDoc = <String>{};
      final topValue = data[target.field] as String?;
      if (topValue != null && topValue.isNotEmpty) {
        valuesInDoc.add(topValue);
      }
      if (target.itemKey != null) {
        final rawItems = data['items'] as List?;
        if (rawItems != null) {
          for (final m in rawItems) {
            final iv = (m as Map)[target.itemKey] as String?;
            if (iv != null && iv.isNotEmpty) valuesInDoc.add(iv);
          }
        }
      }
      for (final v in valuesInDoc) {
        refCounts[v] = (refCounts[v] ?? 0) + 1;
      }
    }

    // 3. BACKFILL: cualquier value en sales que NO esté en el catálogo,
    //    se inserta como userSuggested:true. Sin esto, ventas viejas
    //    con typos quedan invisibles para el detector.
    final missingValues =
        refCounts.keys.where((v) => !existingValues.contains(v)).toList();

    final backfilledItems = <MasterListItem>[];
    if (missingValues.isNotEmpty) {
      const chunkSize = 400; // Firestore batch limit
      for (var i = 0; i < missingValues.length; i += chunkSize) {
        final chunk = missingValues.skip(i).take(chunkSize).toList();
        final batch = _firestore.batch();
        for (final value in chunk) {
          final ref = _firestore
              .collection('master_lists')
              .doc(listId)
              .collection('items')
              .doc();
          final newItem = MasterListItem(
            id: ref.id,
            value: value,
            userSuggested: true,
          );
          batch.set(ref, newItem.toMap());
          backfilledItems.add(newItem);
        }
        await batch.commit();
      }
    }

    final items = [...existingItems, ...backfilledItems];
    if (items.length < 2) {
      return FindClustersResult(
        clusters: const [],
        backfilled: backfilledItems.length,
        totalCatalogItems: items.length,
      );
    }

    // 4. Pares parecidos (O(n²) pero n suele ser <200 incluso después
    //    del backfill — es admin tool, lo soporta)
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
    if (pairs.isEmpty) {
      return FindClustersResult(
        clusters: const [],
        backfilled: backfilledItems.length,
        totalCatalogItems: items.length,
      );
    }

    // 5. Cierre transitivo con union-find
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

    return FindClustersResult(
      clusters: clusters,
      backfilled: backfilledItems.length,
      totalCatalogItems: items.length,
    );
  }

  /// Sincroniza el catálogo de [listId] con valores que aparecen en la
  /// colección primary (`sales` o `workers`) pero no estaban registrados
  /// como items. Devuelve cuántos se agregaron. Útil como botón
  /// independiente del merge tool, para que el admin pueble el catálogo
  /// sin necesariamente entrar a fusionar.
  Future<int> syncCatalogFromSales({required String listId}) async {
    final prop = propagationFor(listId);
    if (prop == null) {
      throw StateError('Lista "$listId" no se sincroniza con su colección.');
    }
    final target = prop.primary;

    final itemsSnap = await _firestore
        .collection('master_lists')
        .doc(listId)
        .collection('items')
        .get();
    final existingValues = itemsSnap.docs
        .map(MasterListItem.fromSnapshot)
        .where((it) => it.active)
        .map((it) => it.value)
        .toSet();

    final docsSnap = await _firestore.collection(target.collection).get();
    final missing = <String>{};
    for (final d in docsSnap.docs) {
      final data = d.data();
      final v = data[target.field] as String?;
      if (v != null && v.isNotEmpty && !existingValues.contains(v)) {
        missing.add(v);
      }
      // También captura values de items[] secundarios si aplica.
      if (target.itemKey != null) {
        final rawItems = data['items'] as List?;
        if (rawItems != null) {
          for (final m in rawItems) {
            final iv = (m as Map)[target.itemKey] as String?;
            if (iv != null && iv.isNotEmpty && !existingValues.contains(iv)) {
              missing.add(iv);
            }
          }
        }
      }
    }

    if (missing.isEmpty) return 0;

    const chunkSize = 400;
    final values = missing.toList();
    for (var i = 0; i < values.length; i += chunkSize) {
      final chunk = values.skip(i).take(chunkSize).toList();
      final batch = _firestore.batch();
      for (final value in chunk) {
        final ref = _firestore
            .collection('master_lists')
            .doc(listId)
            .collection('items')
            .doc();
        final newItem = MasterListItem(
          id: ref.id,
          value: value,
          userSuggested: true,
        );
        batch.set(ref, newItem.toMap());
      }
      await batch.commit();
    }
    return missing.length;
  }

  /// Ejecuta los merges en orden. Por cada request:
  ///   - Para cada duplicate: propaga el cambio de value a TODAS las
  ///     colecciones registradas para este `listId` (primary + secondaries)
  ///     usando `propagateValueChange`, que reescribe en batches.
  ///   - Borra el item duplicado del catálogo.
  ///
  /// Si algo falla a mitad de camino, los merges previos quedan aplicados
  /// (no es transaccional global porque las queries son demasiado grandes
  /// para una sola transacción de Firestore). El resumen devuelto refleja
  /// solo lo que efectivamente se aplicó.
  ///
  /// El nombre del campo `salesUpdated` en el resultado se conserva por
  /// retro-compatibilidad con la UI; representa "docs actualizados" en
  /// todas las colecciones (sales + workers + payments según aplique).
  Future<DuplicateMergeResult> applyMerges({
    required String listId,
    required List<DuplicateMergeRequest> requests,
  }) async {
    if (propagationFor(listId) == null) {
      throw StateError('Lista "$listId" no admite merge automático.');
    }

    var docsUpdated = 0;
    var itemsDeleted = 0;

    for (final req in requests) {
      for (final dup in req.duplicates) {
        // 1. Propagar el cambio de value a todas las colecciones
        //    referenciadas (primary + secondaries). Esto cubre `sales`
        //    + `payments` collectionGroup para `payers`/`payment_methods`/
        //    `transfer_destinations`, y `workers` para `worker_roles`.
        docsUpdated += await propagateValueChange(
          _firestore,
          listId: listId,
          oldValue: dup.value,
          newValue: req.canonical.value,
        );

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
      salesUpdated: docsUpdated,
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
