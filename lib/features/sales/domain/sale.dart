import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Workflow informativo de una solicitud de venta. Sales lo ve para
/// saber si puede entregar material. Cajero lo controla. NO indica
/// nada sobre si la venta se cobró o no — para eso está
/// [SaleFinancialStatus], que es una dimensión independiente.
///
/// Transiciones permitidas:
///   generada    → enProceso | cancelada
///   enProceso   → generada (devolver) | procesada | cancelada
///   procesada   → terminal
///   cancelada   → terminal
enum SaleState {
  generada('generada'),
  enProceso('en_proceso'),
  procesada('procesada'),
  cancelada('cancelada');

  const SaleState(this.id);

  /// Valor serializado en Firestore. Usa snake_case para que el doc
  /// se lea natural desde la consola y queries.
  final String id;

  static SaleState fromId(String? id) {
    if (id == null) return SaleState.procesada;
    for (final s in SaleState.values) {
      if (s.id == id) return s;
    }
    return SaleState.procesada;
  }
}

/// Estado financiero derivado de los pagos acumulados.
///
/// `lost` es absorbente: una vez que se marca pérdida (lossAmount > 0)
/// el status queda `lost` aunque después se cobre. Admin puede revertirlo
/// manualmente si hace falta.
enum SaleFinancialStatus {
  pending('pending'),
  partiallyPaid('partiallyPaid'),
  paid('paid'),
  lost('lost');

  const SaleFinancialStatus(this.id);
  final String id;

  static SaleFinancialStatus fromId(String? id) {
    if (id == null) return SaleFinancialStatus.paid;
    for (final s in SaleFinancialStatus.values) {
      if (s.id == id) return s;
    }
    return SaleFinancialStatus.paid;
  }
}

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
    this.state = SaleState.procesada,
    this.paidAmount = 0,
    this.lossAmount = 0,
    this.outstandingBalance = 0,
    this.financialStatus = SaleFinancialStatus.paid,
    this.creditDueDate,
    this.processedBy,
    this.processedByName,
    this.processedAt,
    this.canceledBy,
    this.canceledByName,
    this.canceledAt,
    this.cancelReason,
    this.markedAsLossBy,
    this.markedAsLossByName,
    this.markedAsLossAt,
    this.lossReason,
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
  /// Ventas creadas por sales en el flujo nuevo arrancan con `''` —
  /// el método de pago lo decide cajero al registrar el primer abono.
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

  // -------- Workflow (estado de la solicitud) --------

  /// Estado workflow informativo para sales. Default `procesada` mantiene
  /// retro-compatibilidad: las ventas viejas (anteriores al flujo de caja)
  /// no tenían estado y se entregaban siempre.
  final SaleState state;

  /// uid del cajero/admin que confirmó la venta como `procesada`. `null`
  /// para ventas viejas sin workflow o que aún no llegaron a procesada.
  final String? processedBy;
  final String? processedByName;
  final DateTime? processedAt;

  final String? canceledBy;
  final String? canceledByName;
  final DateTime? canceledAt;

  /// Razón obligatoria al cancelar. `null` si la venta no fue cancelada.
  final String? cancelReason;

  // -------- Financiero (independiente del workflow) --------

  /// Suma de abonos confirmados. Denormalizado en el doc padre para
  /// queries y métricas sin tener que recorrer la subcolección.
  final num paidAmount;

  /// Saldo castigado contablemente (pérdida). Se absorbe al
  /// financialStatus aunque después se cobre algo.
  final num lossAmount;

  /// `totalValue - paidAmount - lossAmount`. Denormalizado por las
  /// mismas razones que `paidAmount`.
  final num outstandingBalance;

  /// Derivado por [computeFinancialStatus]. Se guarda explícito en el doc
  /// para poder filtrar con `where('financialStatus', isEqualTo: ...)`.
  final SaleFinancialStatus financialStatus;

  /// Plazo opcional para cobrar. Si está y queda en el pasado, la venta
  /// aparece como vencida en el tab "Deudas" del cajero. Sin lógica
  /// automática — solo es información visual.
  final DateTime? creditDueDate;

  // -------- Trazabilidad pérdida --------

  final String? markedAsLossBy;
  final String? markedAsLossByName;
  final DateTime? markedAsLossAt;

  /// Razón obligatoria al marcar pérdida.
  final String? lossReason;

  // -------- Helpers --------

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

  /// `true` cuando el workflow no puede avanzar más (procesada o cancelada).
  bool get isWorkflowFinal =>
      state == SaleState.procesada || state == SaleState.cancelada;

  /// Calcula el `financialStatus` desde los agregados monetarios.
  ///
  /// Regla "lost absorbe": si `lossAmount > 0` queda `lost` aunque
  /// después se cobre todo. Admin puede revertir borrando la marca.
  static SaleFinancialStatus computeFinancialStatus({
    required num totalValue,
    required num paidAmount,
    required num lossAmount,
  }) {
    if (lossAmount > 0) return SaleFinancialStatus.lost;
    if (paidAmount <= 0) return SaleFinancialStatus.pending;
    if (paidAmount >= totalValue) return SaleFinancialStatus.paid;
    return SaleFinancialStatus.partiallyPaid;
  }

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
        'state': state.id,
        'paidAmount': paidAmount,
        'lossAmount': lossAmount,
        'outstandingBalance': outstandingBalance,
        'financialStatus': financialStatus.id,
        'creditDueDate': creditDueDate == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(creditDueDate!)),
        'processedBy': processedBy,
        'processedByName': processedByName,
        'processedAt': processedAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(processedAt!)),
        'canceledBy': canceledBy,
        'canceledByName': canceledByName,
        'canceledAt': canceledAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(canceledAt!)),
        'cancelReason': cancelReason,
        'markedAsLossBy': markedAsLossBy,
        'markedAsLossByName': markedAsLossByName,
        'markedAsLossAt': markedAsLossAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(markedAsLossAt!)),
        'lossReason': lossReason,
      };

  factory Sale.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    final totalValue = data['totalValue'] as num;
    // Backwards-compat: las ventas sin `state` son del flujo viejo,
    // donde el material se entregaba al instante y el pago se registraba
    // junto con la venta. Las interpretamos como procesada/pagada.
    final stateId = data['state'] as String?;
    final state = SaleState.fromId(stateId);
    final hasNewSchema = stateId != null;
    final paidAmount =
        (data['paidAmount'] as num?) ?? (hasNewSchema ? 0 : totalValue);
    final lossAmount = (data['lossAmount'] as num?) ?? 0;
    final outstandingBalance = (data['outstandingBalance'] as num?) ??
        (totalValue - paidAmount - lossAmount);
    final financialStatusId = data['financialStatus'] as String?;
    final financialStatus = financialStatusId != null
        ? SaleFinancialStatus.fromId(financialStatusId)
        : computeFinancialStatus(
            totalValue: totalValue,
            paidAmount: paidAmount,
            lossAmount: lossAmount,
          );
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
      totalValue: totalValue,
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
      state: state,
      paidAmount: paidAmount,
      lossAmount: lossAmount,
      outstandingBalance: outstandingBalance,
      financialStatus: financialStatus,
      creditDueDate: data['creditDueDate'] == null
          ? null
          : AppClock.fromInstant(
              (data['creditDueDate'] as Timestamp).toDate(),
            ),
      processedBy: data['processedBy'] as String?,
      processedByName: data['processedByName'] as String?,
      processedAt: data['processedAt'] == null
          ? null
          : AppClock.fromInstant(
              (data['processedAt'] as Timestamp).toDate(),
            ),
      canceledBy: data['canceledBy'] as String?,
      canceledByName: data['canceledByName'] as String?,
      canceledAt: data['canceledAt'] == null
          ? null
          : AppClock.fromInstant(
              (data['canceledAt'] as Timestamp).toDate(),
            ),
      cancelReason: data['cancelReason'] as String?,
      markedAsLossBy: data['markedAsLossBy'] as String?,
      markedAsLossByName: data['markedAsLossByName'] as String?,
      markedAsLossAt: data['markedAsLossAt'] == null
          ? null
          : AppClock.fromInstant(
              (data['markedAsLossAt'] as Timestamp).toDate(),
            ),
      lossReason: data['lossReason'] as String?,
    );
  }
}
