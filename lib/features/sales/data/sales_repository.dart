import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/clock.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/sale.dart';

/// Acceso a la colección `sales`.
///
/// La generación del consecutivo `CQG-XXX` se hace dentro de una transacción
/// atómica de Firestore, lo que garantiza que dos ventas creadas al mismo
/// tiempo nunca obtengan el mismo número.
class SalesRepository {
  SalesRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.sales);

  DocumentReference<Map<String, dynamic>> get _counterRef => _firestore
      .collection(FirestorePaths.counters)
      .doc(FirestorePaths.salesCounter);

  /// Crea una nueva venta. El cliente arma la mayoría de campos; el
  /// repositorio se encarga del consecutivo, fechas de auditoría y la
  /// ventana de edición de 24 h.
  Future<Sale> createSale({
    required DateTime date,
    required String documentType,
    required String documentNumber,
    required String providerName,
    required String material,
    String? materialVariant,
    required String unit,
    required num quantity,
    required num unitPrice,
    required String paymentMethod,
    required String payerName,
    required String createdBy,
    required String createdByName,
    Map<String, dynamic> customFields = const {},
  }) async {
    final now = AppClock.now();
    final docRef = _col.doc();

    return _firestore.runTransaction<Sale>((txn) async {
      final counterSnap = await txn.get(_counterRef);
      final current = (counterSnap.data()?['value'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      final consecutive = _formatConsecutive(next);

      final totalValue = quantity * unitPrice;
      final sale = Sale(
        id: docRef.id,
        consecutive: consecutive,
        date: date,
        documentType: documentType,
        documentNumber: documentNumber,
        providerName: providerName,
        material: material,
        materialVariant: materialVariant,
        unit: unit,
        quantity: quantity,
        unitPrice: unitPrice,
        totalValue: totalValue,
        paymentMethod: paymentMethod,
        payerName: payerName,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: now,
        editableUntil: now.add(const Duration(hours: 24)),
        customFields: customFields,
      );

      txn.set(_counterRef, {'value': next}, SetOptions(merge: true));
      txn.set(docRef, sale.toMap());
      return sale;
    });
  }

  Future<void> updateSale(
    String id, {
    DateTime? date,
    String? documentType,
    String? documentNumber,
    String? providerName,
    String? material,
    String? materialVariant,
    String? unit,
    num? quantity,
    num? unitPrice,
    String? paymentMethod,
    String? payerName,
    Map<String, dynamic>? customFields,
  }) async {
    final patch = <String, dynamic>{
      if (date != null) 'date': Timestamp.fromDate(AppClock.toInstant(date)),
      if (documentType != null) 'documentType': documentType,
      if (documentNumber != null) 'documentNumber': documentNumber,
      if (providerName != null) 'providerName': providerName,
      if (material != null) 'material': material,
      if (materialVariant != null) 'materialVariant': materialVariant,
      if (unit != null) 'unit': unit,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unitPrice': unitPrice,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (payerName != null) 'payerName': payerName,
      if (customFields != null) 'customFields': customFields,
      'updatedAt': Timestamp.fromDate(AppClock.toInstant(AppClock.now())),
    };
    if (quantity != null || unitPrice != null) {
      // Recalculamos el total cuando cambia cantidad o precio.
      final snap = await _col.doc(id).get();
      final data = snap.data()!;
      final q = (quantity ?? data['quantity'] as num);
      final p = (unitPrice ?? data['unitPrice'] as num);
      patch['totalValue'] = q * p;
    }
    await _col.doc(id).update(patch);
  }

  Future<void> deleteSale(String id) => _col.doc(id).delete();

  Stream<List<Sale>> watchByDateRange(DateTime start, DateTime end) {
    return _col
        .where('date',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(AppClock.toInstant(start)),)
        .where('date',
            isLessThanOrEqualTo: Timestamp.fromDate(AppClock.toInstant(end)),)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Sale.fromSnapshot).toList());
  }

  Stream<List<Sale>> watchRecent({int limit = 50}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Sale.fromSnapshot).toList());
  }

  Future<Sale?> getSale(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return Sale.fromSnapshot(snap);
  }

  /// Stream reactivo a un solo doc. Lo usa SaleDetailScreen para que las
  /// ediciones se reflejen sin tener que invalidar el cache.
  Stream<Sale?> watchSale(String id) {
    return _col
        .doc(id)
        .snapshots()
        .map((snap) => snap.exists ? Sale.fromSnapshot(snap) : null);
  }

  static String _formatConsecutive(int value) {
    final padded = value.toString().padLeft(3, '0');
    return 'CQG-$padded';
  }
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(FirebaseFirestore.instance);
});

class SalesDateRange {
  const SalesDateRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is SalesDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final salesByRangeProvider =
    StreamProvider.family.autoDispose<List<Sale>, SalesDateRange>((ref, range) {
  ref.watch(authStateProvider);
  return ref
      .watch(salesRepositoryProvider)
      .watchByDateRange(range.start, range.end);
});

final recentSalesProvider = StreamProvider.autoDispose<List<Sale>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(salesRepositoryProvider).watchRecent();
});

/// Stream a una venta específica. Mantener actualizado en vivo (en lugar
/// de FutureProvider con cache) hace que al volver de editar se vea el
/// cambio inmediato.
final saleByIdProvider =
    StreamProvider.family.autoDispose<Sale?, String>((ref, id) {
  ref.watch(authStateProvider);
  return ref.watch(salesRepositoryProvider).watchSale(id);
});
