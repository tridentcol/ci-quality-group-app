import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../hours/data/hours_repository.dart';
import '../../hours/domain/hours_categories.dart';
import '../../hours/domain/hours_entry.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';

/// Resumen agregado de ventas para mostrar en el dashboard del admin.
///
/// Cambio crítico vs versiones anteriores: el `total` ahora representa
/// **dinero cobrado** (sum de `paidAmount`), no dinero facturado. Las
/// dimensiones que cuentan transacciones cerradas (`count`, `byMethod`,
/// `byMaterial`, `dailyTotals`, `topPayers`) se calculan SOLO sobre
/// ventas en `state == procesada`. Canceladas no entran. Los KPIs nuevos
/// (`pending*`, `receivable*`, `loss*`) capturan el resto del cuadro
/// financiero: cuánto queda en caja por procesar, cuánto está pendiente
/// de cobrar y cuánto se castigó como pérdida.
class SalesMetrics {
  const SalesMetrics({
    required this.total,
    required this.count,
    required this.byMethod,
    required this.byMaterial,
    required this.byPayer,
    required this.dailyTotals,
    required this.topPayers,
    required this.pendingCount,
    required this.pendingTotal,
    required this.receivableCount,
    required this.receivableTotal,
    required this.lossCount,
    required this.lossTotal,
  });

  /// Dinero efectivamente cobrado en el rango = sum(`paidAmount`) sobre
  /// TODAS las ventas en rango (incluye canceladas con abonos previos,
  /// porque ese cobro sigue siendo plata real).
  final num total;

  /// Ventas `procesada` en el rango. Lo que sales entregó.
  final int count;

  /// Distribución por método de pago (sobre procesadas).
  final Map<String, num> byMethod;

  /// Distribución por material (sobre procesadas).
  final Map<String, num> byMaterial;

  /// Distribución completa por payer (nombre → monto cobrado), para la
  /// pantalla `PayersBreakdownScreen`. `topPayers` deriva de acá.
  final Map<String, num> byPayer;

  /// Lista ordenada (oldest → newest) de pares fecha/total para gráfica de
  /// línea o barras temporales. Suma `paidAmount` de procesadas por día.
  final List<({DateTime day, num total})> dailyTotals;

  /// Top quienes reciben (nombre, monto cobrado). Slice de los primeros 5
  /// de `byPayer` ordenados por monto desc — para el card resumen.
  final List<({String name, num amount})> topPayers;

  /// Solicitudes pendientes de procesar (`generada` o `en_proceso`) en
  /// el rango. Indica trabajo en caja.
  final int pendingCount;
  final num pendingTotal;

  /// Ventas procesadas con saldo (`pending` o `partiallyPaid`) — plata
  /// que ya entregamos como material pero todavía no cobramos.
  final int receivableCount;
  final num receivableTotal;

  /// Ventas marcadas como pérdida en el rango.
  final int lossCount;
  final num lossTotal;

  static SalesMetrics empty() => const SalesMetrics(
        total: 0,
        count: 0,
        byMethod: {},
        byMaterial: {},
        byPayer: {},
        dailyTotals: [],
        topPayers: [],
        pendingCount: 0,
        pendingTotal: 0,
        receivableCount: 0,
        receivableTotal: 0,
        lossCount: 0,
        lossTotal: 0,
      );

  factory SalesMetrics.compute(
    List<Sale> sales, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    if (sales.isEmpty) {
      return SalesMetrics.empty();
    }

    final byMethod = <String, num>{};
    final byMaterial = <String, num>{};
    final byPayer = <String, num>{};
    final byDay = <int, num>{};

    num total = 0;
    int procesadasCount = 0;
    int pendingCount = 0;
    num pendingTotal = 0;
    int receivableCount = 0;
    num receivableTotal = 0;
    int lossCount = 0;
    num lossTotal = 0;

    for (final s in sales) {
      total += s.paidAmount;

      if (s.state == SaleState.generada || s.state == SaleState.enProceso) {
        pendingCount++;
        pendingTotal += s.totalValue;
      }
      if (s.financialStatus == SaleFinancialStatus.lost) {
        lossCount++;
        lossTotal += s.lossAmount;
      }
      if (s.state == SaleState.procesada &&
          (s.financialStatus == SaleFinancialStatus.pending ||
              s.financialStatus == SaleFinancialStatus.partiallyPaid)) {
        receivableCount++;
        receivableTotal += s.outstandingBalance;
      }

      if (s.state != SaleState.procesada) continue;
      procesadasCount++;

      // El desglose Efectivo/Transferencia usa el método de pago
      // registrado en la venta (legacy admin) o queda en cero para
      // ventas del flujo nuevo donde el método se decide en cada
      // abono — esas no aportan al chart de método (limitación
      // documentada; si más adelante hace falta precisión, hay que
      // agregar collectionGroup query a payments).
      final ratio = s.totalValue == 0 ? 0 : s.paidAmount / s.totalValue;
      final cashShare = s.cashPortion * ratio;
      final transferShare = s.transferPortion * ratio;
      if (cashShare > 0) {
        byMethod.update(
          'Efectivo',
          (v) => v + cashShare,
          ifAbsent: () => cashShare,
        );
      }
      if (transferShare > 0) {
        byMethod.update(
          'Transferencia',
          (v) => v + transferShare,
          ifAbsent: () => transferShare,
        );
      }

      final mat = s.materialVariant != null
          ? '${s.material} · ${s.materialVariant}'
          : s.material;
      byMaterial.update(
        mat,
        (v) => v + s.paidAmount,
        ifAbsent: () => s.paidAmount,
      );
      byPayer.update(
        s.payerName,
        (v) => v + s.paidAmount,
        ifAbsent: () => s.paidAmount,
      );
      final dayKey = _ordinal(s.date);
      byDay.update(
        dayKey,
        (v) => v + s.paidAmount,
        ifAbsent: () => s.paidAmount,
      );
    }

    final dailyTotals = <({DateTime day, num total})>[];
    var cursor = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final last = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    while (!cursor.isAfter(last)) {
      final v = byDay[_ordinal(cursor)] ?? 0;
      dailyTotals.add((day: cursor, total: v));
      cursor = cursor.add(const Duration(days: 1));
    }

    final topPayers = byPayer.entries
        .map((e) => (name: e.key, amount: e.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return SalesMetrics(
      total: total,
      count: procesadasCount,
      byMethod: byMethod,
      byMaterial: byMaterial,
      byPayer: byPayer,
      dailyTotals: dailyTotals,
      topPayers: topPayers.take(5).toList(),
      pendingCount: pendingCount,
      pendingTotal: pendingTotal,
      receivableCount: receivableCount,
      receivableTotal: receivableTotal,
      lossCount: lossCount,
      lossTotal: lossTotal,
    );
  }
}

/// Resumen agregado de horas para el dashboard del admin.
class HoursMetrics {
  const HoursMetrics({
    required this.totalPaid,
    required this.entriesCount,
    required this.uniqueWorkers,
    required this.byCategory,
    required this.topWorkers,
    required this.openCount,
  });

  final Duration totalPaid;
  final int entriesCount;
  final int uniqueWorkers;
  final Map<HoursCategory, Duration> byCategory;
  final List<({String name, Duration total})> topWorkers;
  final int openCount;

  static HoursMetrics empty() => HoursMetrics(
        totalPaid: Duration.zero,
        entriesCount: 0,
        uniqueWorkers: 0,
        byCategory: {for (final c in HoursCategory.values) c: Duration.zero},
        topWorkers: const [],
        openCount: 0,
      );

  factory HoursMetrics.compute(List<HoursEntry> entries) {
    if (entries.isEmpty) return HoursMetrics.empty();

    final byCategory = <HoursCategory, Duration>{
      for (final c in HoursCategory.values) c: Duration.zero,
    };
    final byWorker = <String, Duration>{};
    final workerNames = <String, String>{};
    Duration totalPaid = Duration.zero;
    int openCount = 0;

    for (final e in entries) {
      if (e.isOpen) openCount++;
      totalPaid += e.breakdown.totalPaid;
      for (final c in HoursCategory.values) {
        byCategory[c] = byCategory[c]! + e.breakdown.get(c);
      }
      byWorker.update(
        e.workerId,
        (v) => v + e.breakdown.totalPaid,
        ifAbsent: () => e.breakdown.totalPaid,
      );
      workerNames[e.workerId] = e.workerName;
    }

    final topWorkers = byWorker.entries
        .map((e) => (name: workerNames[e.key] ?? e.key, total: e.value))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return HoursMetrics(
      totalPaid: totalPaid,
      entriesCount: entries.length,
      uniqueWorkers: byWorker.length,
      byCategory: byCategory,
      topWorkers: topWorkers.take(5).toList(),
      openCount: openCount,
    );
  }
}

int _ordinal(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// Resumen del breakdown de clientes para el dashboard del admin.
///
/// Distingue entre **clientes nuevos** (cuyo primer compra es dentro
/// del rango) y **clientes recurrentes** (que ya habían comprado
/// antes del rango). Sirve para evaluar fidelización vs adquisición:
/// si la mayoría son nuevos → enfocar marketing en retención; si son
/// recurrentes → la base es leal y conviene captar nuevos.
class ClientMetrics {
  const ClientMetrics({
    required this.totalClientsInRange,
    required this.newClientsCount,
    required this.recurrentClientsCount,
    required this.newClientsRevenue,
    required this.recurrentClientsRevenue,
    required this.byClient,
  });

  final int totalClientsInRange;
  final int newClientsCount;
  final int recurrentClientsCount;
  final num newClientsRevenue;
  final num recurrentClientsRevenue;

  /// Lista ordenada (DESC por revenue del rango) de cada cliente activo
  /// en el rango con sus stats.
  final List<ClientStat> byClient;

  num get totalRevenue => newClientsRevenue + recurrentClientsRevenue;

  /// Tasa de nuevos clientes — % del rango que son primera compra.
  /// 0 si no hay clientes.
  double get newClientRate {
    if (totalClientsInRange == 0) return 0;
    return newClientsCount / totalClientsInRange;
  }

  static ClientMetrics empty() => const ClientMetrics(
        totalClientsInRange: 0,
        newClientsCount: 0,
        recurrentClientsCount: 0,
        newClientsRevenue: 0,
        recurrentClientsRevenue: 0,
        byClient: [],
      );

  /// Computa el breakdown a partir de **todas** las ventas históricas
  /// (no solo las del rango) para poder distinguir nuevos vs recurrentes.
  factory ClientMetrics.compute(
    List<Sale> allSales, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    if (allSales.isEmpty) return ClientMetrics.empty();

    // Por cada cliente: fecha de primera compra (histórica) + stats
    // dentro del rango (revenue, count, primera y última en rango).
    final firstEverByClient = <String, DateTime>{};
    final inRangeStats = <String, _ClientRangeAccum>{};

    for (final s in allSales) {
      final name = s.providerName;
      // Primera compra histórica (mantenemos el min).
      firstEverByClient.update(
        name,
        (prev) => s.date.isBefore(prev) ? s.date : prev,
        ifAbsent: () => s.date,
      );

      // Stats del rango.
      if (!s.date.isBefore(rangeStart) && !s.date.isAfter(rangeEnd)) {
        inRangeStats.update(
          name,
          (acc) => acc.add(s),
          ifAbsent: () => _ClientRangeAccum(name: name).add(s),
        );
      }
    }

    if (inRangeStats.isEmpty) return ClientMetrics.empty();

    var newCount = 0;
    var recurrentCount = 0;
    num newRevenue = 0;
    num recurrentRevenue = 0;
    final perClient = <ClientStat>[];

    for (final entry in inRangeStats.entries) {
      final name = entry.key;
      final acc = entry.value;
      final firstEver = firstEverByClient[name]!;
      final isNew = !firstEver.isBefore(rangeStart);
      if (isNew) {
        newCount++;
        newRevenue += acc.revenue;
      } else {
        recurrentCount++;
        recurrentRevenue += acc.revenue;
      }
      perClient.add(ClientStat(
        name: name,
        salesCount: acc.count,
        revenue: acc.revenue,
        firstPurchaseEver: firstEver,
        firstPurchaseInRange: acc.firstInRange!,
        lastPurchaseInRange: acc.lastInRange!,
        isNew: isNew,
      ),);
    }
    perClient.sort((a, b) => b.revenue.compareTo(a.revenue));

    return ClientMetrics(
      totalClientsInRange: inRangeStats.length,
      newClientsCount: newCount,
      recurrentClientsCount: recurrentCount,
      newClientsRevenue: newRevenue,
      recurrentClientsRevenue: recurrentRevenue,
      byClient: perClient,
    );
  }
}

class ClientStat {
  const ClientStat({
    required this.name,
    required this.salesCount,
    required this.revenue,
    required this.firstPurchaseEver,
    required this.firstPurchaseInRange,
    required this.lastPurchaseInRange,
    required this.isNew,
  });
  final String name;
  final int salesCount;
  final num revenue;
  final DateTime firstPurchaseEver;
  final DateTime firstPurchaseInRange;
  final DateTime lastPurchaseInRange;

  /// `true` si la primera compra histórica del cliente cae DENTRO del
  /// rango analizado. Si el rango es "este mes" y el cliente compró
  /// por primera vez este mes, es nuevo. Si compró antes (cualquier
  /// fecha previa al inicio del rango), es recurrente.
  final bool isNew;
}

class _ClientRangeAccum {
  _ClientRangeAccum({required this.name});
  final String name;
  num revenue = 0;
  int count = 0;
  DateTime? firstInRange;
  DateTime? lastInRange;

  _ClientRangeAccum add(Sale s) {
    // Revenue del cliente = paidAmount (dinero cobrado), no facturado.
    // Consistente con SalesMetrics y con el panel post-Fase 5.
    revenue += s.paidAmount;
    count++;
    firstInRange = firstInRange == null || s.date.isBefore(firstInRange!)
        ? s.date
        : firstInRange;
    lastInRange = lastInRange == null || s.date.isAfter(lastInRange!)
        ? s.date
        : lastInRange;
    return this;
  }
}

/// Stream de TODAS las ventas históricas. Se usa para el breakdown de
/// clientes (necesita saber la fecha de primera compra de cada cliente,
/// que puede ser anterior al rango filtrado). Para volúmenes típicos
/// (<10K ventas) es liviano. Si crece mucho, conviene mover a una
/// agregación server-side via Cloud Functions.
final allSalesProvider = StreamProvider.autoDispose<List<Sale>>((ref) {
  final repo = ref.watch(salesRepositoryProvider);
  // Reuso watchByDateRange con un rango "amplio" para no tener que
  // agregar otro método al repository — desde 2020 hasta mañana.
  return repo.watchByDateRange(
    DateTime(2020),
    DateTime.now().add(const Duration(days: 1)),
  );
});

/// Métricas de clientes memoizadas por rango.
final clientMetricsProvider = Provider.family
    .autoDispose<AsyncValue<ClientMetrics>, SalesDateRange>((ref, range) {
  final all = ref.watch(allSalesProvider);
  return all.whenData((list) => ClientMetrics.compute(
        list,
        rangeStart: range.start,
        rangeEnd: range.end,
      ),);
});

/// Métricas de ventas memoizadas. Riverpod las recalcula solo cuando
/// `salesByRangeProvider` emite una lista nueva, no en cada `build()`
/// de la pantalla.
final salesMetricsProvider = Provider.family
    .autoDispose<AsyncValue<SalesMetrics>, SalesDateRange>((ref, range) {
  final sales = ref.watch(salesByRangeProvider(range));
  return sales.whenData((list) => SalesMetrics.compute(
        list,
        rangeStart: range.start,
        rangeEnd: range.end,
      ),);
});

/// Métricas de horas memoizadas (igual que las de ventas).
final hoursMetricsProvider = Provider.family
    .autoDispose<AsyncValue<HoursMetrics>, HoursDateRange>((ref, range) {
  final entries = ref.watch(hoursByRangeProvider(range));
  return entries.whenData(HoursMetrics.compute);
});
