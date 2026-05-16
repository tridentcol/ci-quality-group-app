import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/services/notifications_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/sale.dart';

/// Acceso a la colección `sales`.
///
/// La generación del consecutivo `CQG-XXX` se hace dentro de una transacción
/// atómica de Firestore, lo que garantiza que dos ventas creadas al mismo
/// tiempo nunca obtengan el mismo número.
class SalesRepository {
  SalesRepository(this._firestore, this._notifications);

  final FirebaseFirestore _firestore;
  final NotificationsRepository _notifications;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.sales);

  DocumentReference<Map<String, dynamic>> get _counterRef => _firestore
      .collection(FirestorePaths.counters)
      .doc(FirestorePaths.salesCounter);

  /// Crea una nueva venta. El cliente arma la mayoría de campos; el
  /// repositorio se encarga del consecutivo, fechas de auditoría y la
  /// ventana de edición de 24 h.
  ///
  /// `items` lleva al menos un material. El total se calcula como la
  /// suma de `quantity * unitPrice` de cada item — para que la venta
  /// quede consistente aunque el cliente envíe valores parciales.
  ///
  /// El `state` controla cómo arrancan los agregados financieros:
  ///   - `procesada` (default, flujo legacy admin) → la venta se considera
  ///     pagada al instante: paidAmount = totalValue, financialStatus = paid.
  ///   - `generada` (flujo nuevo sales) → es una solicitud sin pago todavía:
  ///     paidAmount = 0, outstandingBalance = totalValue, status = pending.
  /// El resto de estados no tienen sentido al crear y caen al default.
  Future<Sale> createSale({
    required DateTime date,
    required String documentType,
    required String documentNumber,
    required String providerName,
    required List<SaleItem> items,
    required String paymentMethod,
    num? cashAmount,
    num? transferAmount,
    String? transferDestination,
    required String payerName,
    required String createdBy,
    required String createdByName,
    SaleState state = SaleState.procesada,
  }) async {
    assert(items.isNotEmpty, 'createSale requiere al menos un item.');
    final now = AppClock.now();
    final docRef = _col.doc();

    return _firestore.runTransaction<Sale>((txn) async {
      final counterSnap = await txn.get(_counterRef);
      final current = (counterSnap.data()?['value'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      final consecutive = _formatConsecutive(next);

      final totalValue =
          items.fold<num>(0, (a, i) => a + i.quantity * i.unitPrice);
      // Para solicitudes nuevas (state=generada) el pago se registra
      // después desde caja. Para el flujo legacy (procesada) la venta
      // se considera cobrada al instante.
      final isRequest = state == SaleState.generada;
      final paidAmount = isRequest ? 0 : totalValue;
      final outstandingBalance = isRequest ? totalValue : 0;
      final financialStatus = isRequest
          ? SaleFinancialStatus.pending
          : SaleFinancialStatus.paid;
      final sale = Sale(
        id: docRef.id,
        consecutive: consecutive,
        date: date,
        documentType: documentType,
        documentNumber: documentNumber,
        providerName: providerName,
        items: items,
        totalValue: totalValue,
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        transferAmount: transferAmount,
        transferDestination: transferDestination,
        payerName: payerName,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: now,
        // editableUntil queda fijo desde `createdAt`; jamás se reasigna
        // en `updateSale` (la ventana es estable y le da a sales 24h
        // ciertas para corregir lo que cargó).
        editableUntil: now.add(const Duration(hours: 24)),
        state: state,
        paidAmount: paidAmount,
        lossAmount: 0,
        outstandingBalance: outstandingBalance,
        financialStatus: financialStatus,
      );

      txn.set(_counterRef, {'value': next}, SetOptions(merge: true));
      txn.set(docRef, sale.toMap());

      // Cuando es una solicitud nueva (state=generada), avisar a caja +
      // admin para que la procesen. El flujo legacy (state=procesada) no
      // requiere intervención y por eso no emite notif.
      if (isRequest) {
        _notifications.emitInTxn(
          txn,
          type: NotificationType.saleCreated,
          title: 'Nueva solicitud',
          body:
              '${sale.consecutive} — $providerName, ${formatCop(totalValue)}',
          saleId: sale.id,
          actorUid: createdBy,
          actorName: createdByName,
          targetRoles: const [AppRole.cajero, AppRole.admin],
        );
      }
      return sale;
    });
  }

  /// Actualiza una venta existente. NO toca `editableUntil` — la ventana
  /// se fija al crear y permanece estable.
  ///
  /// Cuando se pasa `items`, se reemplaza completo el array, se
  /// recalcula `totalValue` y se recomputan los agregados financieros
  /// denormalizados (`outstandingBalance`, `financialStatus`) dentro
  /// de una transacción — de lo contrario, una edición que cambia el
  /// total deja el saldo y el estado financiero stale hasta el próximo
  /// abono. Los campos mirror del primer item (`material`,
  /// `materialVariant`, `unit`, `quantity`, `unitPrice`) se
  /// re-sincronizan para que los queries indexados sigan apuntando al
  /// principal.
  Future<void> updateSale(
    String id, {
    DateTime? date,
    String? documentType,
    String? documentNumber,
    String? providerName,
    List<SaleItem>? items,
    String? paymentMethod,
    // Para los campos de pago dividido pasamos `setNullable*: true`
    // cuando explícitamente queremos limpiar el valor (ej. cambiar
    // de Mixto a Solo Efectivo borra el `transferDestination`).
    // Si queda en false, no tocamos el campo en el patch.
    num? cashAmount,
    bool clearCashAmount = false,
    num? transferAmount,
    bool clearTransferAmount = false,
    String? transferDestination,
    bool clearTransferDestination = false,
    String? payerName,
  }) async {
    final basePatch = <String, dynamic>{
      if (date != null) 'date': Timestamp.fromDate(AppClock.toInstant(date)),
      if (documentType != null) 'documentType': documentType,
      if (documentNumber != null) 'documentNumber': documentNumber,
      if (providerName != null) 'providerName': providerName,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (clearCashAmount) 'cashAmount': null
      else if (cashAmount != null) 'cashAmount': cashAmount,
      if (clearTransferAmount) 'transferAmount': null
      else if (transferAmount != null) 'transferAmount': transferAmount,
      if (clearTransferDestination) 'transferDestination': null
      else if (transferDestination != null)
        'transferDestination': transferDestination,
      if (payerName != null) 'payerName': payerName,
      'updatedAt': Timestamp.fromDate(AppClock.toInstant(AppClock.now())),
    };

    // Sin cambio de items: patch directo, no necesita lectura previa.
    if (items == null) {
      await _col.doc(id).update(basePatch);
      return;
    }

    assert(items.isNotEmpty, 'updateSale: items no puede quedar vacío.');
    final first = items.first;
    final newTotal =
        items.fold<num>(0, (a, i) => a + i.quantity * i.unitPrice);

    // Con cambio de items: transacción para leer paidAmount/lossAmount
    // y recomputar agregados atomicamente. Mismo patrón que registerPayment
    // en CashierRepository — así el saldo y el financialStatus de la
    // venta quedan consistentes con el nuevo total inmediatamente, sin
    // tener que esperar a que se registre un nuevo abono.
    await _firestore.runTransaction((txn) async {
      final ref = _col.doc(id);
      final snap = await txn.get(ref);
      if (!snap.exists) {
        throw StateError('La venta no existe.');
      }
      final data = snap.data()!;
      final paidAmount = (data['paidAmount'] as num?) ?? 0;
      final lossAmount = (data['lossAmount'] as num?) ?? 0;
      final newOutstanding = Sale.computeOutstandingBalance(
        totalValue: newTotal,
        paidAmount: paidAmount,
        lossAmount: lossAmount,
      );
      final newStatus = Sale.computeFinancialStatus(
        totalValue: newTotal,
        paidAmount: paidAmount,
        lossAmount: lossAmount,
      );

      txn.update(ref, {
        ...basePatch,
        'items': items.map((i) => i.toMap()).toList(),
        'material': first.material,
        'materialVariant': first.materialVariant,
        'unit': first.unit,
        'quantity': first.quantity,
        'unitPrice': first.unitPrice,
        'totalValue': newTotal,
        'outstandingBalance': newOutstanding,
        'financialStatus': newStatus.id,
      });
    });
  }

  /// Borra la venta + cascade delete de su subcolección `payments`.
  /// Sin esto los abonos quedan huérfanos en Firestore y aparecen como
  /// data fantasma en el collectionGroup query del dashboard (también
  /// pueden romper iteraciones que asuman `doc.reference.parent.parent`
  /// no nulo). Firestore no hace cascade automático.
  ///
  /// Usamos `WriteBatch` (no transaction) porque las transactions no
  /// admiten queries de subcolección. El batch es atómico hasta 500
  /// ops — suficiente para cualquier venta real (raramente >5 abonos).
  Future<void> deleteSale(String id) async {
    final ref = _col.doc(id);
    final payments = await ref.collection('payments').get();
    final batch = _firestore.batch();
    for (final doc in payments.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }

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

  /// Stream de ventas filtradas por un campo específico. Lo usa el
  /// dashboard del auditor: `watchByField('materialVariant', 'PEDRO')`
  /// devuelve TODAS las ventas históricas (sin rango) cuyo
  /// `materialVariant == 'PEDRO'`. El filtro de rango después se aplica
  /// en memoria sobre el resultado para no requerir un índice compuesto
  /// extra por cada combinación field+date.
  ///
  /// Nota: este filtro matchea solo el mirror del item principal
  /// (items[0]). Si la venta tiene un material secundario, no aparece
  /// para auditores filtrados por ese material — limitación aceptada
  /// para mantener el query indexado y barato.
  Stream<List<Sale>> watchByField(String field, String value) {
    return _col
        .where(field, isEqualTo: value)
        .snapshots()
        .map((snap) {
      final docs = snap.docs.map(Sale.fromSnapshot).toList();
      // Orden cronológico DESC en memoria (cabe holgado para el
      // volumen típico de un auditor — ~cientos de ventas máximo).
      docs.sort((a, b) => b.date.compareTo(a.date));
      return docs;
    });
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
  return SalesRepository(
    FirebaseFirestore.instance,
    ref.watch(notificationsRepositoryProvider),
  );
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

/// Argumentos para el filtro genérico por campo. Lo usa el dashboard
/// del auditor: el campo lo dicta su `auditFilter` (ej. materialVariant
/// = 'PEDRO').
class SalesFieldQuery {
  const SalesFieldQuery({required this.field, required this.value});
  final String field;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is SalesFieldQuery && other.field == field && other.value == value;

  @override
  int get hashCode => Object.hash(field, value);
}

final salesByFieldProvider =
    StreamProvider.family.autoDispose<List<Sale>, SalesFieldQuery>((ref, q) {
  ref.watch(authStateProvider);
  return ref.watch(salesRepositoryProvider).watchByField(q.field, q.value);
});

/// Stream a una venta específica. Mantener actualizado en vivo (en lugar
/// de FutureProvider con cache) hace que al volver de editar se vea el
/// cambio inmediato.
final saleByIdProvider =
    StreamProvider.family.autoDispose<Sale?, String>((ref, id) {
  ref.watch(authStateProvider);
  return ref.watch(salesRepositoryProvider).watchSale(id);
});
