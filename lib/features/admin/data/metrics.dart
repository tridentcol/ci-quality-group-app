import '../../sales/domain/sale.dart';
import '../../hours/domain/hours_categories.dart';
import '../../hours/domain/hours_entry.dart';

/// Resumen agregado de ventas para mostrar en el dashboard del admin.
class SalesMetrics {
  const SalesMetrics({
    required this.total,
    required this.count,
    required this.byMethod,
    required this.byMaterial,
    required this.dailyTotals,
    required this.topPayers,
  });

  /// Total facturado en el rango.
  final num total;

  /// Cantidad de ventas en el rango.
  final int count;

  /// Distribución por método de pago.
  final Map<String, num> byMethod;

  /// Distribución por material.
  final Map<String, num> byMaterial;

  /// Lista ordenada (oldest → newest) de pares fecha/total para gráfica de
  /// línea o barras temporales.
  final List<({DateTime day, num total})> dailyTotals;

  /// Top quienes reciben (nombre, monto).
  final List<({String name, num amount})> topPayers;

  static SalesMetrics empty() => const SalesMetrics(
        total: 0,
        count: 0,
        byMethod: {},
        byMaterial: {},
        dailyTotals: [],
        topPayers: [],
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
    for (final s in sales) {
      total += s.totalValue;
      byMethod.update(s.paymentMethod, (v) => v + s.totalValue,
          ifAbsent: () => s.totalValue);
      final mat = s.materialVariant != null
          ? '${s.material} · ${s.materialVariant}'
          : s.material;
      byMaterial.update(mat, (v) => v + s.totalValue,
          ifAbsent: () => s.totalValue);
      byPayer.update(s.payerName, (v) => v + s.totalValue,
          ifAbsent: () => s.totalValue);
      final dayKey = _ordinal(s.date);
      byDay.update(dayKey, (v) => v + s.totalValue,
          ifAbsent: () => s.totalValue);
    }

    // Genera la serie diaria continua, rellenando con 0 los días sin ventas.
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
      count: sales.length,
      byMethod: byMethod,
      byMaterial: byMaterial,
      dailyTotals: dailyTotals,
      topPayers: topPayers.take(5).toList(),
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
        .map((e) =>
            (name: workerNames[e.key] ?? e.key, total: e.value))
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
