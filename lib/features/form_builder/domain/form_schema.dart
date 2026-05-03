import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Tipo de campo soportado por el constructor de formularios.
enum FieldType {
  text,
  multiline,
  number,
  decimal,
  date,
  datetime,
  toggle,
  dropdown,
  /// Dropdown enlazado a una lista maestra (proveedores, pagadores, etc.).
  masterListReference,
  /// Campo calculado por fórmula simple (`{quantity} * {unitPrice}`).
  computed;

  static FieldType fromId(String id) =>
      FieldType.values.firstWhere((t) => t.name == id);
}

/// Definición de un campo dentro del esquema de un formulario dinámico.
class FieldDefinition {
  const FieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.visibleToRoles = const ['admin', 'sales', 'hours'],
    this.editableByRoles = const ['admin', 'sales', 'hours'],
    this.options = const [],
    this.masterListId,
    this.formula,
    this.placeholder,
    this.helperText,
    this.defaultValue,
    this.order = 0,
    this.coreField = false,
  });

  /// Identificador estable del campo (no cambia aunque se renombre el label).
  final String id;
  final String label;
  final FieldType type;
  final bool required;

  /// Roles que pueden ver este campo. Permite al admin ocultar campos a
  /// quien diligencia ventas u horas.
  final List<String> visibleToRoles;

  /// Roles que pueden modificarlo. Subconjunto de `visibleToRoles`.
  final List<String> editableByRoles;

  /// Opciones literales para `dropdown`.
  final List<String> options;

  /// Id de la lista maestra para `masterListReference`.
  final String? masterListId;

  /// Fórmula para `computed` (sintaxis simple: `{fieldId} * {fieldId}` etc.).
  final String? formula;

  final String? placeholder;
  final String? helperText;
  final dynamic defaultValue;
  final int order;

  /// `true` si es un campo del modelo base (no se puede borrar, solo ocultar).
  final bool coreField;

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type.name,
        'required': required,
        'visibleToRoles': visibleToRoles,
        'editableByRoles': editableByRoles,
        'options': options,
        'masterListId': masterListId,
        'formula': formula,
        'placeholder': placeholder,
        'helperText': helperText,
        'defaultValue': defaultValue,
        'order': order,
        'coreField': coreField,
      };

  factory FieldDefinition.fromMap(Map<String, dynamic> map) => FieldDefinition(
        id: map['id'] as String,
        label: map['label'] as String,
        type: FieldType.fromId(map['type'] as String),
        required: (map['required'] as bool?) ?? false,
        visibleToRoles: List<String>.from(
          map['visibleToRoles'] as List? ?? const ['admin', 'sales', 'hours'],
        ),
        editableByRoles: List<String>.from(
          map['editableByRoles'] as List? ?? const ['admin', 'sales', 'hours'],
        ),
        options: List<String>.from(map['options'] as List? ?? const []),
        masterListId: map['masterListId'] as String?,
        formula: map['formula'] as String?,
        placeholder: map['placeholder'] as String?,
        helperText: map['helperText'] as String?,
        defaultValue: map['defaultValue'],
        order: (map['order'] as num?)?.toInt() ?? 0,
        coreField: (map['coreField'] as bool?) ?? false,
      );
}

/// Esquema completo de un formulario (ventas u horas).
class FormSchema {
  const FormSchema({
    required this.id,
    required this.module,
    required this.version,
    required this.fields,
    required this.updatedAt,
    this.updatedBy,
  });

  final String id;

  /// `sales` o `hours`.
  final String module;

  final int version;
  final List<FieldDefinition> fields;
  final DateTime updatedAt;
  final String? updatedBy;

  Map<String, dynamic> toMap() => {
        'module': module,
        'version': version,
        'fields': fields.map((f) => f.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(AppClock.toInstant(updatedAt)),
        'updatedBy': updatedBy,
      };

  factory FormSchema.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return FormSchema(
      id: snap.id,
      module: data['module'] as String,
      version: (data['version'] as num).toInt(),
      fields: (data['fields'] as List)
          .map((f) => FieldDefinition.fromMap(f as Map<String, dynamic>))
          .toList(),
      updatedAt:
          AppClock.fromInstant((data['updatedAt'] as Timestamp).toDate()),
      updatedBy: data['updatedBy'] as String?,
    );
  }

  /// Esquema base de ventas según el formato original de CI Quality Group.
  /// Sirve como punto de partida si Firestore aún no tiene esquema guardado.
  static FormSchema defaultSalesSchema() => FormSchema(
        id: 'sales_v1',
        module: 'sales',
        version: 1,
        updatedAt: AppClock.now(),
        fields: [
          const FieldDefinition(
            id: 'date',
            label: 'Fecha',
            type: FieldType.date,
            required: true,
            order: 1,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'documentType',
            label: 'Tipo de documento',
            type: FieldType.dropdown,
            options: ['Cédula', 'NIT'],
            required: true,
            order: 2,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'documentNumber',
            label: 'Número de documento',
            type: FieldType.text,
            required: true,
            order: 3,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'providerName',
            label: 'Nombre del cliente',
            type: FieldType.masterListReference,
            masterListId: 'providers',
            required: true,
            order: 4,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'material',
            label: 'Material',
            type: FieldType.masterListReference,
            masterListId: 'materials',
            required: true,
            order: 5,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'materialVariant',
            label: 'Tipo de lámina',
            type: FieldType.masterListReference,
            masterListId: 'lamina_brands',
            required: false,
            order: 6,
            coreField: true,
            helperText: 'Solo aplica cuando el material es LAMINA.',
          ),
          const FieldDefinition(
            id: 'unit',
            label: 'Unidad de medida',
            type: FieldType.masterListReference,
            masterListId: 'units',
            required: true,
            order: 7,
            coreField: true,
            visibleToRoles: ['admin'],
            editableByRoles: ['admin'],
            defaultValue: 'Kilogramos',
          ),
          const FieldDefinition(
            id: 'quantity',
            label: 'Cantidad',
            type: FieldType.decimal,
            required: true,
            order: 8,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'unitPrice',
            label: 'Valor unitario',
            type: FieldType.number,
            required: true,
            order: 9,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'totalValue',
            label: 'Valor total',
            type: FieldType.computed,
            formula: '{quantity} * {unitPrice}',
            order: 10,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'paymentMethod',
            label: 'Método de pago',
            type: FieldType.masterListReference,
            masterListId: 'payment_methods',
            required: true,
            order: 11,
            coreField: true,
          ),
          const FieldDefinition(
            id: 'payerName',
            label: 'Quién recibe',
            type: FieldType.masterListReference,
            masterListId: 'payers',
            required: true,
            order: 12,
            coreField: true,
          ),
        ],
      );
}
