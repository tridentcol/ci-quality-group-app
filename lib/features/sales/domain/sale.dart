import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Una venta registrada en la app.
///
/// Los campos "core" (los del formato original) son tipados; los campos
/// adicionales que el admin agregue al esquema dinámico se guardan en
/// `customFields` y se exportan al xlsx por nombre.
class Sale {
  const Sale({
    required this.id,
    required this.consecutive,
    required this.date,
    required this.documentType,
    required this.documentNumber,
    required this.providerName,
    required this.material,
    required this.materialVariant,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.totalValue,
    required this.paymentMethod,
    required this.payerName,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.editableUntil,
    this.customFields = const {},
  });

  final String id;

  /// Consecutivo legible (ej. `CQG-001`).
  final String consecutive;

  final DateTime date;

  /// `Cédula` o `NIT`.
  final String documentType;
  final String documentNumber;

  final String providerName;

  /// `LAMINA`, `CHATARRA`, `CHATARRA TUBERIA` o lo que el admin agregue.
  final String material;

  /// Sub-tipo cuando aplique (ej. `PEDRO`, `TIPO QUALITY`, `KINGSPAN` para LAMINA).
  final String? materialVariant;

  /// `Kilogramos` por defecto, gestionado por lista maestra.
  final String unit;
  final num quantity;
  final num unitPrice;
  final num totalValue;

  /// `Efectivo` o `Transferencia` (gestionado por lista maestra).
  final String paymentMethod;

  final String payerName;

  /// uid del usuario que creó la venta.
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Hasta cuándo el usuario que la creó puede editarla. 24 h después de
  /// crearla, solo el admin puede modificar.
  final DateTime? editableUntil;

  /// Campos agregados dinámicamente por el admin (clave = id del campo en el
  /// esquema; valor = primitivo serializable: String / num / bool / Timestamp).
  final Map<String, dynamic> customFields;

  Map<String, dynamic> toMap() => {
        'consecutive': consecutive,
        'date': Timestamp.fromDate(AppClock.toInstant(date)),
        'documentType': documentType,
        'documentNumber': documentNumber,
        'providerName': providerName,
        'material': material,
        'materialVariant': materialVariant,
        'unit': unit,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalValue': totalValue,
        'paymentMethod': paymentMethod,
        'payerName': payerName,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(AppClock.toInstant(createdAt)),
        'updatedAt': updatedAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(updatedAt!)),
        'editableUntil': editableUntil == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(editableUntil!)),
        'customFields': customFields,
      };

  factory Sale.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return Sale(
      id: snap.id,
      consecutive: data['consecutive'] as String,
      date: AppClock.fromInstant((data['date'] as Timestamp).toDate()),
      documentType: data['documentType'] as String,
      documentNumber: data['documentNumber'] as String,
      providerName: data['providerName'] as String,
      material: data['material'] as String,
      materialVariant: data['materialVariant'] as String?,
      unit: data['unit'] as String,
      quantity: data['quantity'] as num,
      unitPrice: data['unitPrice'] as num,
      totalValue: data['totalValue'] as num,
      paymentMethod: data['paymentMethod'] as String,
      payerName: data['payerName'] as String,
      createdBy: data['createdBy'] as String,
      createdByName: data['createdByName'] as String,
      createdAt:
          AppClock.fromInstant((data['createdAt'] as Timestamp).toDate()),
      updatedAt: data['updatedAt'] == null
          ? null
          : AppClock.fromInstant((data['updatedAt'] as Timestamp).toDate()),
      editableUntil: data['editableUntil'] == null
          ? null
          : AppClock.fromInstant((data['editableUntil'] as Timestamp).toDate()),
      customFields:
          Map<String, dynamic>.from(data['customFields'] as Map? ?? const {}),
    );
  }
}
