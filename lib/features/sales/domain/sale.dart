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
    this.cashAmount,
    this.transferAmount,
    this.transferDestination,
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

  /// Resumen del método de pago: `Efectivo`, `Transferencia` o `Mixto`.
  /// Se deriva de `cashAmount` y `transferAmount` al guardar (para no
  /// tener que filtrar por dos campos en queries / métricas viejas).
  /// Ventas históricas pueden tener solo este campo (sin desglose).
  final String paymentMethod;

  /// Monto pagado en efectivo. `null` en ventas viejas que solo
  /// tienen `paymentMethod`. Usar [cashPortion] para obtener el
  /// monto real con el fallback aplicado.
  final num? cashAmount;

  /// Monto pagado por transferencia. `null` en ventas viejas que
  /// solo tienen `paymentMethod`. Usar [transferPortion].
  final num? transferAmount;

  /// Banco/billetera receptor de la transferencia (`Bancolombia`,
  /// `Nequi`, etc.). `null` cuando no hay parte transferida o cuando
  /// la venta es vieja sin desglose. Gestionado por lista maestra
  /// `transfer_destinations`.
  final String? transferDestination;

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

  /// Monto efectivo "real" — usa `cashAmount` si existe, si no infiere
  /// del `paymentMethod` legacy: si era 'Efectivo' devuelve el total,
  /// si era 'Transferencia' devuelve 0, si era 'Mixto' (no debería
  /// pasar en ventas sin cashAmount) devuelve 0 conservadoramente.
  num get cashPortion {
    if (cashAmount != null) return cashAmount!;
    if (paymentMethod.toLowerCase() == 'efectivo') return totalValue;
    return 0;
  }

  /// Monto transferencia "real" — análogo a [cashPortion].
  num get transferPortion {
    if (transferAmount != null) return transferAmount!;
    if (paymentMethod.toLowerCase() == 'transferencia') return totalValue;
    return 0;
  }

  /// `true` si la venta tiene pago dividido (efectivo + transferencia
  /// con ambos > 0). Útil para decidir si mostrar el donut de breakdown.
  bool get isMixedPayment => cashPortion > 0 && transferPortion > 0;

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
        'cashAmount': cashAmount,
        'transferAmount': transferAmount,
        'transferDestination': transferDestination,
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
      cashAmount: data['cashAmount'] as num?,
      transferAmount: data['transferAmount'] as num?,
      transferDestination: data['transferDestination'] as String?,
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
