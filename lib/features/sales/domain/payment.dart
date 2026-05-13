import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Un abono registrado contra una venta. Vive en la subcolección
/// `sales/{saleId}/payments/{paymentId}`.
///
/// Toda creación / borrado de un payment va en un `runTransaction` que
/// también recalcula los agregados denormalizados del doc padre
/// (`paidAmount`, `outstandingBalance`, `financialStatus`). Esa atomicidad
/// es la que mantiene la consistencia entre subcolección y agregados —
/// si se pierde, las métricas mienten.
class SalePayment {
  const SalePayment({
    required this.id,
    required this.amount,
    required this.paymentMethod,
    required this.registeredBy,
    required this.registeredByName,
    required this.registeredAt,
    this.cashAmount,
    this.transferAmount,
    this.transferDestination,
    this.payerName,
    this.notes,
  });

  final String id;

  /// Monto total del abono (`cashAmount + transferAmount` cuando es mixto).
  final num amount;

  /// `Efectivo` | `Transferencia` | `Mixto`. Misma convención que en
  /// `Sale.paymentMethod` legacy.
  final String paymentMethod;

  /// Solo se setea cuando el método incluye efectivo.
  final num? cashAmount;

  /// Solo se setea cuando el método incluye transferencia.
  final num? transferAmount;

  /// Banco/billetera. Requerido cuando `transferAmount > 0`. Gestionado
  /// por la lista maestra `transfer_destinations`.
  final String? transferDestination;

  /// Quién en caja recibió este abono. Lista maestra `payers`. Reemplaza
  /// al `payerName` del doc padre (que en el flujo nuevo queda vacío),
  /// porque ahora cada abono puede ser cobrado por una persona distinta.
  final String? payerName;

  /// uid del cajero/admin que registró el abono.
  final String registeredBy;

  /// Nombre cacheado para mostrar en la timeline sin extra lookup.
  final String registeredByName;
  final DateTime registeredAt;

  /// Notas opcionales del cajero (ej. "abono parcial, completa mañana").
  final String? notes;

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'paymentMethod': paymentMethod,
        'cashAmount': cashAmount,
        'transferAmount': transferAmount,
        'transferDestination': transferDestination,
        'payerName': payerName,
        'registeredBy': registeredBy,
        'registeredByName': registeredByName,
        'registeredAt': Timestamp.fromDate(AppClock.toInstant(registeredAt)),
        'notes': notes,
      };

  factory SalePayment.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data()!;
    return SalePayment(
      id: snap.id,
      amount: data['amount'] as num,
      paymentMethod: data['paymentMethod'] as String,
      cashAmount: data['cashAmount'] as num?,
      transferAmount: data['transferAmount'] as num?,
      transferDestination: data['transferDestination'] as String?,
      payerName: data['payerName'] as String?,
      registeredBy: data['registeredBy'] as String,
      registeredByName: data['registeredByName'] as String,
      registeredAt:
          AppClock.fromInstant((data['registeredAt'] as Timestamp).toDate()),
      notes: data['notes'] as String?,
    );
  }
}
