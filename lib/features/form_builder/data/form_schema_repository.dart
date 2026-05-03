import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/clock.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/form_schema.dart';

/// Acceso a la colección `form_schemas`. Hay un documento por módulo
/// (`sales`, en el futuro `hours`). Cada doc contiene la versión vigente
/// y la lista ordenada de campos.
///
/// El admin puede:
///  - Reordenar campos.
///  - Cambiar `label`, `helperText`, `required`, `visibleToRoles`.
///  - Agregar campos nuevos no-core.
///  - Eliminar campos no-core.
///  - Restaurar al esquema por defecto (defaultSalesSchema).
///
/// Los campos `coreField=true` no se pueden eliminar (la app los necesita
/// para mapear a los campos tipados de `Sale`). Sí se puede ocultar a roles
/// (`visibleToRoles=[]`) y reordenar.
class FormSchemaRepository {
  FormSchemaRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.formSchemas);

  /// Stream del esquema vigente para un módulo. Si no existe, hace seed
  /// con el default UNA sola vez y lo emite. La bandera `_seeded` evita
  /// reescribir el doc si Firestore re-emite un snapshot `!exists`
  /// (ej. el admin lo borra remoto mientras otro cliente está escuchando).
  Stream<FormSchema> watchSchema(String module) {
    return _col.doc(module).snapshots().asyncMap((snap) async {
      if (snap.exists) return FormSchema.fromSnapshot(snap);
      final defaults = _defaultFor(module);
      if (!_seeded.contains(module)) {
        _seeded.add(module);
        try {
          await _col.doc(module).set(defaults.toMap());
        } catch (_) {
          // Si falla el seed, removemos para permitir reintento posterior.
          _seeded.remove(module);
          rethrow;
        }
      }
      return FormSchema(
        id: module,
        module: defaults.module,
        version: defaults.version,
        fields: defaults.fields,
        updatedAt: defaults.updatedAt,
        updatedBy: defaults.updatedBy,
      );
    });
  }

  static final Set<String> _seeded = <String>{};

  Future<FormSchema?> getSchema(String module) async {
    final snap = await _col.doc(module).get();
    if (!snap.exists) return null;
    return FormSchema.fromSnapshot(snap);
  }

  /// Reemplaza el esquema entero. Incrementa `version` para que
  /// instalaciones con cache antiguo lo refresquen.
  Future<void> saveSchema({
    required String module,
    required List<FieldDefinition> fields,
    required String updatedBy,
    required int previousVersion,
  }) async {
    final ordered = [...fields]..sort((a, b) => a.order.compareTo(b.order));
    final normalized = <FieldDefinition>[];
    for (var i = 0; i < ordered.length; i++) {
      final f = ordered[i];
      normalized.add(FieldDefinition(
        id: f.id,
        label: f.label,
        type: f.type,
        required: f.required,
        visibleToRoles: f.visibleToRoles,
        editableByRoles: f.editableByRoles,
        options: f.options,
        masterListId: f.masterListId,
        formula: f.formula,
        placeholder: f.placeholder,
        helperText: f.helperText,
        defaultValue: f.defaultValue,
        order: i + 1,
        coreField: f.coreField,
      ));
    }
    final next = FormSchema(
      id: module,
      module: module,
      version: previousVersion + 1,
      fields: normalized,
      updatedAt: AppClock.now(),
      updatedBy: updatedBy,
    );
    await _col.doc(module).set(next.toMap());
  }

  /// Reescribe el esquema con el default del módulo. Útil como botón de
  /// "restaurar".
  Future<void> resetToDefaults({
    required String module,
    required String updatedBy,
  }) async {
    final defaults = _defaultFor(module);
    await saveSchema(
      module: module,
      fields: defaults.fields,
      updatedBy: updatedBy,
      previousVersion: defaults.version - 1,
    );
  }

  FormSchema _defaultFor(String module) {
    switch (module) {
      case 'sales':
        return FormSchema.defaultSalesSchema();
      default:
        throw ArgumentError('Módulo de formulario desconocido: $module');
    }
  }
}

final formSchemaRepositoryProvider = Provider<FormSchemaRepository>((ref) {
  return FormSchemaRepository(FirebaseFirestore.instance);
});

/// Stream del esquema activo por módulo. AutoDispose porque solo se
/// consume mientras alguien renderiza el formulario o el editor.
final formSchemaProvider =
    StreamProvider.family.autoDispose<FormSchema, String>((ref, module) {
  ref.watch(authStateProvider);
  return ref.watch(formSchemaRepositoryProvider).watchSchema(module);
});
