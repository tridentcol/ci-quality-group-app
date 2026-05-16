import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/master_list.dart';

/// Configuración de propagación de un cambio en una lista maestra a las
/// colecciones que la referencian por valor (no por id). Cada lista que
/// admita rename/merge automático tiene una entrada aquí.
///
/// Una lista puede impactar:
///   - una colección **principal** (`primary`) — usada por merge/rename
///     tools para listar referencias y proponer canónicos.
///   - cero o más colecciones **secundarias** (`secondaries`) — típicamente
///     subcolecciones que también guardan el value (ej. `payments`).
class ListPropagation {
  const ListPropagation({
    required this.primary,
    this.secondaries = const [],
  });

  final ListTarget primary;
  final List<ListTarget> secondaries;
}

class ListTarget {
  const ListTarget({
    required this.collection,
    required this.field,
    this.itemKey,
    this.isCollectionGroup = false,
  });

  /// Nombre de la colección (`sales`, `workers`) o del último segmento
  /// si es collection group (`payments`).
  final String collection;

  /// Campo del documento a actualizar (`material`, `role`, ...).
  final String field;

  /// Si los docs ALSO guardan este value dentro de un array `items[]`
  /// (caso de `material`/`materialVariant`/`unit` en `Sale.items`),
  /// el key del campo dentro de cada item del array. Null si no aplica.
  final String? itemKey;

  /// Si es `true`, la query se hace con `collectionGroup(collection)`
  /// en vez de `collection(collection)`. Necesario para subcolecciones
  /// como `payments` que viven bajo `sales/{saleId}/payments/`.
  final bool isCollectionGroup;
}

/// Tabla canónica de propagaciones. Cuando agregás una lista maestra
/// nueva y querés que sus rename/merge propaguen a otra colección,
/// sumá la entrada acá.
const Map<String, ListPropagation> _propagationByListId = {
  'providers': ListPropagation(
    primary: ListTarget(collection: 'sales', field: 'providerName'),
  ),
  'payers': ListPropagation(
    primary: ListTarget(collection: 'sales', field: 'payerName'),
    secondaries: [
      ListTarget(
        collection: 'payments',
        field: 'payerName',
        isCollectionGroup: true,
      ),
    ],
  ),
  'materials': ListPropagation(
    primary: ListTarget(
      collection: 'sales',
      field: 'material',
      itemKey: 'material',
    ),
  ),
  // `lamina_brands` es el listId histórico para tipos/subvariantes.
  // El display name es "Tipos de materiales" — funciona para cualquier
  // material, no solo lámina.
  'lamina_brands': ListPropagation(
    primary: ListTarget(
      collection: 'sales',
      field: 'materialVariant',
      itemKey: 'materialVariant',
    ),
  ),
  'units': ListPropagation(
    primary: ListTarget(
      collection: 'sales',
      field: 'unit',
      itemKey: 'unit',
    ),
  ),
  'payment_methods': ListPropagation(
    primary: ListTarget(collection: 'sales', field: 'paymentMethod'),
    secondaries: [
      ListTarget(
        collection: 'payments',
        field: 'paymentMethod',
        isCollectionGroup: true,
      ),
    ],
  ),
  'transfer_destinations': ListPropagation(
    primary: ListTarget(collection: 'sales', field: 'transferDestination'),
    secondaries: [
      ListTarget(
        collection: 'payments',
        field: 'transferDestination',
        isCollectionGroup: true,
      ),
    ],
  ),
  // `worker_roles` no afecta a `sales` — vive en `workers.role`.
  'worker_roles': ListPropagation(
    primary: ListTarget(collection: 'workers', field: 'role'),
  ),
};

bool listSupportsMerge(String listId) =>
    _propagationByListId.containsKey(listId);

/// Devuelve la propagación completa de un listId. Lo usan `renameItem`
/// (esta clase) y `applyMerges` (en `duplicate_service.dart`) para saber
/// dónde escribir los updates.
ListPropagation? propagationFor(String listId) =>
    _propagationByListId[listId];

/// Backwards-compat: devuelve el campo del target primario solo cuando
/// éste apunta a `sales`. Para todo lo demás (workers, payments) devuelve
/// null. Los callers viejos que asumían "esto siempre es sales" siguen
/// funcionando sin cambios. Para soporte completo de propagación, usar
/// `propagationFor`.
String? saleFieldFor(String listId) {
  final prop = _propagationByListId[listId];
  if (prop == null) return null;
  return prop.primary.collection == 'sales' ? prop.primary.field : null;
}

/// Ejecuta la propagación de un cambio de value en TODOS los targets
/// (primary + secondaries) configurados para `listId`. Devuelve el total
/// de docs actualizados sumando todos los targets. Lo usan tanto
/// `renameItem` como `applyMerges` para evitar duplicar la lógica de
/// batch update.
Future<int> propagateValueChange(
  FirebaseFirestore firestore, {
  required String listId,
  required String oldValue,
  required String newValue,
}) async {
  final prop = _propagationByListId[listId];
  if (prop == null) return 0;
  var totalUpdated = 0;
  totalUpdated += await _applyToTarget(
    firestore,
    target: prop.primary,
    oldValue: oldValue,
    newValue: newValue,
  );
  for (final secondary in prop.secondaries) {
    totalUpdated += await _applyToTarget(
      firestore,
      target: secondary,
      oldValue: oldValue,
      newValue: newValue,
    );
  }
  return totalUpdated;
}

/// Helper interno: encuentra todos los docs de `target` que tengan el
/// `oldValue` y los reescribe en batches de 400.
Future<int> _applyToTarget(
  FirebaseFirestore firestore, {
  required ListTarget target,
  required String oldValue,
  required String newValue,
}) async {
  final Query<Map<String, dynamic>> query = target.isCollectionGroup
      ? firestore
          .collectionGroup(target.collection)
          .where(target.field, isEqualTo: oldValue)
      : firestore
          .collection(target.collection)
          .where(target.field, isEqualTo: oldValue);
  final snap = await query.get();
  if (snap.docs.isEmpty) return 0;

  const chunkSize = 400; // Firestore batch limit es 500
  for (var i = 0; i < snap.docs.length; i += chunkSize) {
    final chunk = snap.docs.skip(i).take(chunkSize).toList();
    final batch = firestore.batch();
    for (final doc in chunk) {
      final update = <String, dynamic>{target.field: newValue};
      if (target.itemKey != null) {
        // El value también puede vivir dentro de `items[]` (caso de
        // material/variant/unit en `Sale`). Re-escribimos cada item
        // que matchee para mantener consistencia con el mirror top-level.
        final rawItems = doc.data()['items'] as List?;
        if (rawItems != null) {
          final updated = rawItems
              .map((m) => Map<String, dynamic>.from(m as Map))
              .map((m) {
            if ((m[target.itemKey!] as String?) == oldValue) {
              m[target.itemKey!] = newValue;
            }
            return m;
          }).toList();
          update['items'] = updated;
        }
      }
      batch.update(doc.reference, update);
    }
    await batch.commit();
  }
  return snap.docs.length;
}

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
    // Filtramos `active` y ordenamos por `value` en memoria para no requerir
    // un índice compuesto en Firestore. Las listas maestras son pequeñas
    // (decenas de items), así que el costo es despreciable.
    Query<Map<String, dynamic>> query = _itemsCol(listId);
    if (parent != null) {
      query = query.where('parent', isEqualTo: parent);
    }
    return query.snapshots().map((snap) {
      final items = snap.docs
          .map(MasterListItem.fromSnapshot)
          .where((item) => item.active)
          .toList()
        ..sort(
            (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),);
      return items;
    });
  }

  Future<List<MasterListItem>> fetchItemsOnce(
    String listId, {
    String? parent,
  }) async {
    Query<Map<String, dynamic>> query = _itemsCol(listId);
    if (parent != null) {
      query = query.where('parent', isEqualTo: parent);
    }
    final snap = await query.get();
    final items = snap.docs
        .map(MasterListItem.fromSnapshot)
        .where((item) => item.active)
        .toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return items;
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

  /// Renombra el `value` de un item del catálogo Y propaga el cambio a
  /// todas las ventas que referencian el value viejo. Usado cuando el
  /// admin edita un item con el lápiz ✏️ — corregir mayúsculas, agregar
  /// algo entre paréntesis, arreglar acentos, etc.
  ///
  /// Diferencia con `updateItem`:
  ///   - `updateItem` solo toca el documento del catálogo (sin tocar
  ///     ventas históricas). Útil cuando quieres aprobar una sugerencia
  ///     o cambiar parent/active sin afectar histórico.
  ///   - `renameItem` también busca todas las `sales` con el value
  ///     viejo y las reescribe al value nuevo. Esto mantiene la
  ///     consistencia entre catálogo y ventas — métricas, exports,
  ///     dropdowns muestran el nombre correcto en todo lado.
  ///
  /// Devuelve cuántas ventas se actualizaron (0 si la lista no afecta
  /// ventas o si nadie referencia el value viejo).
  ///
  /// Si el listId no está en `_saleFieldByListId` (ej. `worker_roles`),
  /// solo se renombra el catálogo — las "ventas" no aplican.
  Future<int> renameItem({
    required String listId,
    required String itemId,
    required String oldValue,
    required String newValue,
  }) async {
    final cleaned = newValue.trim();
    if (cleaned.isEmpty) return 0;
    if (cleaned == oldValue) return 0;

    // 1. Update del item en el catálogo. De paso lo marcamos como NO
    //    sugerencia (admin lo formalizó al editarlo).
    await _itemsCol(listId).doc(itemId).update({
      'value': cleaned,
      'userSuggested': false,
    });

    // 2. Propagar a todas las colecciones que referencian este value.
    //    Cubre primary (sales o workers) + secondaries (payments
    //    collectionGroup si aplica). Si la lista no tiene propagación
    //    registrada, devuelve 0.
    return propagateValueChange(
      _firestore,
      listId: listId,
      oldValue: oldValue,
      newValue: cleaned,
    );
  }

  /// Crea o actualiza la metadata (nombre, descripción, allowFreeText) de las
  /// listas base. Se llama desde el panel admin al entrar a "Listas maestras".
  ///
  /// La metadata se hace upsert siempre, así rebautizar etiquetas en código
  /// se propaga a las instalaciones existentes. Los items solo se crean en
  /// la primera ejecución para no duplicarlos.
  ///
  /// Una bandera `_didSeed` evita reescribir las listas en cada visita al
  /// panel: la primera entrada exitosa de la sesión hace el upsert; las
  /// siguientes son no-op. Si falla a mitad (permission-denied, offline)
  /// la bandera NO se setea, así el siguiente intento puede reintentar.
  Future<void> seedDefaults({bool force = false}) async {
    if (_didSeed && !force) return;
    final defaults = _defaultListsSeed();
    for (final spec in defaults) {
      final id = spec['id'] as String;
      final existing = await _listsCol.doc(id).get();

      await _listsCol.doc(id).set({
        'name': spec['name'],
        'allowFreeText': spec['allowFreeText'],
        'description': spec['description'],
      }, SetOptions(merge: true),);

      if (existing.exists) continue;

      final items = spec['items'] as List<String>;
      if (items.isEmpty) continue;
      final batch = _firestore.batch();
      for (final value in items) {
        final ref = _itemsCol(id).doc();
        batch.set(ref, MasterListItem(id: ref.id, value: value).toMap());
      }
      await batch.commit();
    }
    // Solo marcamos la bandera al completar exitosamente.
    _didSeed = true;
  }

  /// Reset usable desde el repo de Auth al cerrar sesión, para permitir que
  /// la próxima sesión vuelva a intentar el seed (por si la sesión anterior
  /// terminó con permisos diferentes).
  static void resetSeedFlag() {
    _didSeed = false;
  }

  static bool _didSeed = false;
}

List<Map<String, dynamic>> _defaultListsSeed() => [
      {
        'id': 'providers',
        'name': 'Clientes',
        'allowFreeText': true,
        'description': 'Personas o empresas a las que se les vende material.',
        'items': <String>[],
      },
      {
        'id': 'payers',
        'name': 'Quién recibe',
        'allowFreeText': true,
        'description': 'Quién recibe efectivamente el pago de una venta.',
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
        // El listId queda `lamina_brands` por compatibilidad con la
        // base de datos en producción (las ventas históricas referencian
        // este listId implícitamente vía el campo materialVariant).
        // El display name pasó a ser genérico "Tipos de materiales" —
        // ahora cualquier material principal puede tener subtipos, no
        // solo LAMINA. Los items existentes (PEDRO, TIPO QUALITY,
        // KINGSPAN) heredan parent=null; el admin puede asignarles
        // su material padre desde el detalle de la lista.
        'id': 'lamina_brands',
        'name': 'Tipos de materiales',
        'allowFreeText': true,
        'description':
            'Subtipos por material principal (ej. tipos de lámina, '
                'variantes de chatarra). Cada subtipo puede asignarse al '
                'material al que pertenece.',
        'items': <String>['PEDRO', 'TIPO QUALITY', 'KINGSPAN'],
      },
      {
        'id': 'payment_methods',
        'name': 'Métodos de pago',
        'allowFreeText': false,
        'description': 'Cómo se recibe el pago. No se permite captura libre.',
        'items': <String>['Efectivo', 'Transferencia', 'Mixto'],
      },
      {
        'id': 'transfer_destinations',
        'name': 'Destinos de transferencia',
        'allowFreeText': true,
        'description':
            'Bancos / billeteras receptoras cuando el pago es por '
                'transferencia (total o parcial). El admin puede agregar '
                'destinos nuevos sin tocar código.',
        'items': <String>[
          'Bancolombia',
          'Nequi',
          'Daviplata',
          'Bancolombia Ahorro a la Mano',
        ],
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

final masterListsProvider = StreamProvider.autoDispose<List<MasterList>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(masterListsRepositoryProvider).watchLists();
});

/// Stream reactivo a la metadata de UNA lista. Lo usa MasterListField para
/// saber si la lista permite captura libre. Reemplaza al FutureBuilder
/// previo que solo leía el documento una vez (y no se enteraba cuando el
/// admin cambiaba `allowFreeText` en otro dispositivo).
final masterListMetaProvider =
    StreamProvider.family.autoDispose<MasterList?, String>((ref, listId) {
  ref.watch(authStateProvider);
  return FirebaseFirestore.instance
      .collection(FirestorePaths.masterLists)
      .doc(listId)
      .snapshots()
      .map((snap) => snap.exists ? MasterList.fromSnapshot(snap) : null);
});

final masterListItemsProvider = StreamProvider.family
    .autoDispose<List<MasterListItem>, MasterListItemsQuery>((ref, query) {
  ref.watch(authStateProvider);
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
