import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../domain/master_list.dart';

/// Acceso a las listas maestras gestionadas por el admin.
///
/// La estructura es:
///   master_lists/{listId}                 -> documento con metadatos
///   master_lists/{listId}/items/{itemId}  -> opciones individuales
///
/// El método [seedDefaults] crea las listas base la primera vez que el admin
/// entra al panel, para que ventas y horas tengan dropdowns funcionando.
class MasterListsRepository {
  MasterListsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _listsCol =>
      _firestore.collection(FirestorePaths.masterLists);

  CollectionReference<Map<String, dynamic>> _itemsCol(String listId) =>
      _firestore.collection(FirestorePaths.masterListItems(listId));

  Stream<List<MasterList>> watchLists() {
    return _listsCol.orderBy(FieldPath.documentId).snapshots().map(
          (snap) => snap.docs.map(MasterList.fromSnapshot).toList(),
        );
  }

  Future<MasterList?> getList(String listId) async {
    final snap = await _listsCol.doc(listId).get();
    if (!snap.exists) return null;
    return MasterList.fromSnapshot(snap);
  }

  Stream<List<MasterListItem>> watchItems(String listId, {String? parent}) {
    Query<Map<String, dynamic>> query = _itemsCol(listId)
        .where('active', isEqualTo: true)
        .orderBy('value');
    if (parent != null) {
      query = query.where('parent', isEqualTo: parent);
    }
    return query.snapshots().map(
          (snap) => snap.docs.map(MasterListItem.fromSnapshot).toList(),
        );
  }

  Future<List<MasterListItem>> fetchItemsOnce(
    String listId, {
    String? parent,
  }) async {
    Query<Map<String, dynamic>> query =
        _itemsCol(listId).where('active', isEqualTo: true).orderBy('value');
    if (parent != null) {
      query = query.where('parent', isEqualTo: parent);
    }
    final snap = await query.get();
    return snap.docs.map(MasterListItem.fromSnapshot).toList();
  }

  Future<void> upsertList(MasterList list) async {
    await _listsCol.doc(list.id).set(list.toMap(), SetOptions(merge: true));
  }

  Future<MasterListItem> addItem(
    String listId, {
    required String value,
    String? parent,
    bool userSuggested = false,
    Map<String, dynamic> metadata = const {},
  }) async {
    final ref = _itemsCol(listId).doc();
    final item = MasterListItem(
      id: ref.id,
      value: value.trim(),
      parent: parent,
      metadata: metadata,
      userSuggested: userSuggested,
    );
    await ref.set(item.toMap());
    return item;
  }

  Future<void> updateItem(
    String listId,
    String itemId, {
    String? value,
    String? parent,
    bool? active,
    bool? userSuggested,
  }) async {
    final patch = <String, dynamic>{
      if (value != null) 'value': value.trim(),
      if (parent != null) 'parent': parent,
      if (active != null) 'active': active,
      if (userSuggested != null) 'userSuggested': userSuggested,
    };
    if (patch.isEmpty) return;
    await _itemsCol(listId).doc(itemId).update(patch);
  }

  Future<void> deleteItem(String listId, String itemId) async {
    // Soft delete: lo marcamos inactivo para no romper referencias en ventas
    // ya registradas (que guardan el value como String, no el id).
    await _itemsCol(listId).doc(itemId).update({'active': false});
  }

  /// Crea las listas base si no existen todavía. Se llama desde el panel admin
  /// la primera vez que entra a "Listas maestras".
  Future<void> seedDefaults() async {
    final defaults = _defaultListsSeed();
    for (final spec in defaults) {
      final id = spec['id'] as String;
      final existing = await _listsCol.doc(id).get();
      if (existing.exists) continue;

      await _listsCol.doc(id).set({
        'name': spec['name'],
        'allowFreeText': spec['allowFreeText'],
        'description': spec['description'],
      });

      final items = spec['items'] as List<String>;
      final batch = _firestore.batch();
      for (final value in items) {
        final ref = _itemsCol(id).doc();
        batch.set(ref, MasterListItem(id: ref.id, value: value).toMap());
      }
      await batch.commit();
    }
  }
}

List<Map<String, dynamic>> _defaultListsSeed() => [
      {
        'id': 'providers',
        'name': 'Proveedores',
        'allowFreeText': true,
        'description': 'Personas o empresas a las que se les compra material.',
        'items': <String>[],
      },
      {
        'id': 'payers',
        'name': 'Quién paga',
        'allowFreeText': true,
        'description': 'Personas que efectivamente desembolsan en una venta.',
        'items': <String>[],
      },
      {
        'id': 'materials',
        'name': 'Materiales',
        'allowFreeText': true,
        'description': 'Tipos de material aceptados en las ventas.',
        'items': <String>['LAMINA', 'CHATARRA', 'CHATARRA TUBERIA'],
      },
      {
        'id': 'lamina_brands',
        'name': 'Tipos de lámina',
        'allowFreeText': true,
        'description': 'Marcas o variantes específicas para el material LAMINA.',
        'items': <String>['PEDRO', 'TIPO QUALITY', 'KINGSPAN'],
      },
      {
        'id': 'payment_methods',
        'name': 'Métodos de pago',
        'allowFreeText': false,
        'description': 'Cómo se recibe el pago. No se permite captura libre.',
        'items': <String>['Efectivo', 'Transferencia'],
      },
      {
        'id': 'units',
        'name': 'Unidades de medida',
        'allowFreeText': false,
        'description': 'Unidades aceptadas para la cantidad vendida.',
        'items': <String>['Kilogramos'],
      },
      {
        'id': 'worker_roles',
        'name': 'Cargos de trabajadores',
        'allowFreeText': true,
        'description': 'Cargos disponibles al registrar un trabajador.',
        'items': <String>['AUX. GESTOR DE RESIDUOS', 'CONDUCTOR'],
      },
    ];

final masterListsRepositoryProvider = Provider<MasterListsRepository>((ref) {
  return MasterListsRepository(FirebaseFirestore.instance);
});

final masterListsProvider = StreamProvider<List<MasterList>>((ref) {
  return ref.watch(masterListsRepositoryProvider).watchLists();
});

final masterListItemsProvider = StreamProvider.family
    .autoDispose<List<MasterListItem>, MasterListItemsQuery>((ref, query) {
  return ref
      .watch(masterListsRepositoryProvider)
      .watchItems(query.listId, parent: query.parent);
});

class MasterListItemsQuery {
  const MasterListItemsQuery({required this.listId, this.parent});

  final String listId;
  final String? parent;

  @override
  bool operator ==(Object other) =>
      other is MasterListItemsQuery &&
      other.listId == listId &&
      other.parent == parent;

  @override
  int get hashCode => Object.hash(listId, parent);
}
