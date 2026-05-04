import 'package:cloud_firestore/cloud_firestore.dart';

/// Lista maestra gestionada por el admin (proveedores, pagadores, materiales,
/// métodos de pago, unidades, marcas de lámina, cargos, etc.).
///
/// Las opciones se exponen vía dropdowns en los formularios pero también
/// admiten captura libre desde el cliente: si el usuario digita un nombre
/// nuevo, se guarda en `pending` (la app puede marcar la opción como
/// "sugerida por usuario" y el admin decide si la formaliza).
class MasterList {
  const MasterList({
    required this.id,
    required this.name,
    required this.allowFreeText,
    this.description,
  });

  /// Identificador estable (`providers`, `payers`, `materials`, ...).
  final String id;
  final String name;

  /// Si `true`, el formulario permite captura libre cuando la opción no exista.
  final bool allowFreeText;

  final String? description;

  Map<String, dynamic> toMap() => {
        'name': name,
        'allowFreeText': allowFreeText,
        'description': description,
      };

  factory MasterList.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return MasterList(
      id: snap.id,
      name: data['name'] as String,
      allowFreeText: (data['allowFreeText'] as bool?) ?? false,
      description: data['description'] as String?,
    );
  }
}

class MasterListItem {
  const MasterListItem({
    required this.id,
    required this.value,
    this.parent,
    this.metadata = const {},
    this.active = true,
    this.userSuggested = false,
  });

  final String id;
  final String value;

  /// Para listas anidadas (ej. marca de lámina cuyo padre es el material LAMINA).
  final String? parent;

  final Map<String, dynamic> metadata;
  final bool active;

  /// `true` cuando la opción fue agregada espontáneamente por un usuario.
  /// El admin puede revisar las sugerencias y formalizarlas.
  final bool userSuggested;

  Map<String, dynamic> toMap() => {
        'value': value,
        'parent': parent,
        'metadata': metadata,
        'active': active,
        'userSuggested': userSuggested,
      };

  factory MasterListItem.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap,) {
    final data = snap.data()!;
    return MasterListItem(
      id: snap.id,
      value: data['value'] as String,
      parent: data['parent'] as String?,
      metadata: Map<String, dynamic>.from(data['metadata'] as Map? ?? const {}),
      active: (data['active'] as bool?) ?? true,
      userSuggested: (data['userSuggested'] as bool?) ?? false,
    );
  }
}
