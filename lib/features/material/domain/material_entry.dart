import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Tipo de movimiento. `ingreso` = compra que entra a bodega (empresa
/// proveedora, lista maestra `material_providers`). `salida` = material
/// que sale (empresa cliente, reusa la lista maestra `providers` que ya
/// usa Ventas — decisión de Carlos: son independientes de las ventas
/// comerciales, pero el catálogo de clientes es el mismo).
enum MaterialMovementType {
  ingreso('ingreso'),
  salida('salida');

  const MaterialMovementType(this.id);
  final String id;

  String get label =>
      this == MaterialMovementType.ingreso ? 'Ingreso' : 'Salida';

  /// Label del campo de contraparte: "Proveedor" en ingreso, "Cliente"
  /// en salida.
  String get counterpartyLabel =>
      this == MaterialMovementType.ingreso ? 'Proveedor' : 'Cliente';

  static MaterialMovementType fromId(String? id) {
    for (final t in MaterialMovementType.values) {
      if (t.id == id) return t;
    }
    return MaterialMovementType.ingreso;
  }
}

/// Un movimiento de material de bodega: ingreso (compra a un proveedor)
/// o salida (despacho a un cliente), totalmente independiente de
/// `sales`. Consecutivo `ING-XXX`/`SAL-XXX` generado atómicamente,
/// mismo patrón que `Sale.consecutive` (contador propio por tipo).
class MaterialEntry {
  const MaterialEntry({
    required this.id,
    required this.consecutive,
    this.type = MaterialMovementType.ingreso,
    required this.date,
    required this.material,
    this.materialVariant,
    required this.quantity,
    required this.unit,
    this.providerName,
    this.clientName,
    this.originDescription,
    this.vehicleRef,
    required this.materialPhotoUrl,
    this.originPhotoUrl,
    this.notes,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.editableUntil,
  });

  final String id;
  final String consecutive;
  final MaterialMovementType type;
  final DateTime date;

  final String material;
  final String? materialVariant;
  final num quantity;
  final String unit;

  /// Empresa proveedora. Solo cuando `type == ingreso`. De la lista
  /// maestra `material_providers`.
  final String? providerName;

  /// Empresa cliente/destino. Solo cuando `type == salida`. Reusa la
  /// lista maestra `providers` (la misma "Clientes" de Ventas).
  final String? clientName;

  /// La contraparte del movimiento sin importar el tipo — proveedor en
  /// ingreso, cliente en salida. Lo que usan el dashboard y el correo
  /// para agregar "por empresa".
  String get counterpartyName =>
      type == MaterialMovementType.ingreso
          ? (providerName ?? '')
          : (clientName ?? '');

  /// Texto libre: de dónde viene (ingreso) o hacia dónde va (salida) el
  /// material, ej. "Barranquilla — Recicladora XYZ".
  final String? originDescription;

  /// Placa o número de vagón, opcional.
  final String? vehicleRef;

  /// Foto del material/vagón. Requerida — sube a Storage antes de crear
  /// el doc.
  final String materialPhotoUrl;

  /// Foto de procedencia. Opcional.
  final String? originPhotoUrl;

  final String? notes;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Ventana fija de edición (`createdAt + 24h`), mismo patrón que
  /// `Sale.editableUntil` — se fija al crear y nunca se reasigna.
  final DateTime? editableUntil;

  bool get isEditable =>
      editableUntil == null || AppClock.now().isBefore(editableUntil!);

  String get displayLabel =>
      materialVariant != null ? '$material · $materialVariant' : material;

  Map<String, dynamic> toMap() => {
        'consecutive': consecutive,
        'type': type.id,
        'date': Timestamp.fromDate(AppClock.toInstant(date)),
        'material': material,
        'materialVariant': materialVariant,
        'quantity': quantity,
        'unit': unit,
        'providerName': providerName,
        'clientName': clientName,
        'originDescription': originDescription,
        'vehicleRef': vehicleRef,
        'materialPhotoUrl': materialPhotoUrl,
        'originPhotoUrl': originPhotoUrl,
        'notes': notes,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(AppClock.toInstant(createdAt)),
        'updatedAt': updatedAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(updatedAt!)),
        'editableUntil': editableUntil == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(editableUntil!)),
      };

  factory MaterialEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data()!;
    return MaterialEntry(
      id: snap.id,
      consecutive: (data['consecutive'] as String?) ?? '',
      type: MaterialMovementType.fromId(data['type'] as String?),
      date: AppClock.fromInstant((data['date'] as Timestamp).toDate()),
      material: (data['material'] as String?) ?? '',
      materialVariant: data['materialVariant'] as String?,
      quantity: (data['quantity'] as num?) ?? 0,
      unit: (data['unit'] as String?) ?? '',
      providerName: data['providerName'] as String?,
      clientName: data['clientName'] as String?,
      originDescription: data['originDescription'] as String?,
      vehicleRef: data['vehicleRef'] as String?,
      materialPhotoUrl: (data['materialPhotoUrl'] as String?) ?? '',
      originPhotoUrl: data['originPhotoUrl'] as String?,
      notes: data['notes'] as String?,
      createdBy: (data['createdBy'] as String?) ?? '',
      createdByName: (data['createdByName'] as String?) ?? '',
      createdAt:
          AppClock.fromInstant((data['createdAt'] as Timestamp).toDate()),
      updatedAt: data['updatedAt'] == null
          ? null
          : AppClock.fromInstant((data['updatedAt'] as Timestamp).toDate()),
      editableUntil: data['editableUntil'] == null
          ? null
          : AppClock.fromInstant(
              (data['editableUntil'] as Timestamp).toDate(),
            ),
    );
  }
}
