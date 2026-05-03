import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../hours/data/hours_repository.dart';
import '../../hours/domain/hours_categories.dart';
import '../../sales/data/sales_repository.dart';
import '../data/metrics.dart';

/// Dashboard del admin con KPIs y gráficas.
///
/// Filtra por rango (default = mes corriente) y agrega en cliente sobre
/// los streams ya existentes de ventas y horas. Sin queries especiales,
/// sin agregación servidor, sin índices nuevos.
class AdminMetricsScreen extends ConsumerStatefulWidget {
  const AdminMetricsScreen({super.key});

  @override
  ConsumerState<AdminMetricsScreen> createState() =>
      _AdminMetricsScreenState();
}

class _AdminMetricsScreenState extends ConsumerState<AdminMetricsScreen> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (picked != null) {
      setState(() {
        _start = startOfDay(picked.start);
        _end = endOfDay(picked.end);
      });
    }
  }

  void _setPreset(_RangePreset preset) {
    final now = AppClock.now();
    setState(() {
      switch (preset) {
        case _RangePreset.today:
          _start = startOfDay(now);
          _end = endOfDay(now);
          break;
        case _RangePreset.week:
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          _start = startOfDay(weekStart);
          _end = endOfDay(now);
          break;
        case _RangePreset.month:
          _start = startOfMonth(now);
          _end = endOfMonth(now);
          break;
        case _RangePreset.last30:
          _start = startOfDay(now.subtract(const Duration(days: 29)));
          _end = endOfDay(now);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(
      salesByRangeProvider(SalesDateRange(start: _start, end: _end)),
    );
    final hoursAsync = ref.watch(
      hoursByRangeProvider(HoursDateRange(start: _start, end: _end)),
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Métricas y gráficas'),
        actions: [
          IconButton(
            tooltip: 'Filtrar fechas',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickRange,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _RangeBanner(
            start: _start,
            end: _end,
            onPreset: _setPreset,
          ),
          const SizedBox(height: 24),
          Text('VENTAS', style: _sectionStyle(theme)),
          const SizedBox(height: 8),
          salesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Error en ventas: $e'),
            data: (sales) {
              final m = SalesMetrics.compute(
                sales,
                rangeStart: _start,
                rangeEnd: _end,
              );
              return _SalesSection(metrics: m, rangeStart: _start);
            },
          ),
          const SizedBox(height: 24),
          Text('HORAS', style: _sectionStyle(theme)),
          const SizedBox(height: 8),
          hoursAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Error en horas: $e'),
            data: (entries) {
              final m = HoursMetrics.compute(entries);
              return _HoursSection(metrics: m);
            },
          ),
        ],
      ),
    );
  }

  TextStyle? _sectionStyle(ThemeData theme) =>
      theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
        letterSpacing: 1.2,
      );
}

enum _RangePreset { today, week, month, last30 }

class _RangeBanner extends StatelessWidget {
  const _RangeBanner({
    required this.start,
    required this.end,
    required this.onPreset,
  });

  final DateTime start;
  final DateTime end;
  final ValueChanged<_RangePreset> onPreset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatDate(start)} – ${formatDate(end)}',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            'Resumen del periodo',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PresetChip(label: 'Hoy', onTap: () => onPreset(_RangePreset.today)),
                const SizedBox(width: 8),
                _PresetChip(
                    label: 'Esta semana',
                    onTap: () => onPreset(_RangePreset.week)),
                const SizedBox(width: 8),
                _PresetChip(
                    label: 'Este mes',
                    onTap: () => onPreset(_RangePreset.month)),
                const SizedBox(width: 8),
                _PresetChip(
                    label: 'Últimos 30 días',
                    onTap: () => onPreset(_RangePreset.last30)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: c),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // FittedBox evita que valores largos como $1,234,567,890 desborden
            // el card y se monten encima de la sección de abajo.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fila de hasta 3 KPI cards con altura consistente. En pantallas
/// estrechas las apila en 2 columnas para evitar texto incrustado /
/// solapamientos con la sección siguiente.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 380;
        if (narrow) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in cards)
                SizedBox(
                  width: (constraints.maxWidth - 10) / 2,
                  child: c,
                ),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SalesSection extends StatelessWidget {
  const _SalesSection({required this.metrics, required this.rangeStart});
  final SalesMetrics metrics;
  final DateTime rangeStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (metrics.count == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('Sin ventas en el rango.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
        ),
      );
    }

    return Column(
      children: [
        _KpiRow(cards: [
          _KpiCard(
            label: 'Total',
            value: formatCop(metrics.total),
            icon: Icons.payments_outlined,
          ),
          _KpiCard(
            label: 'Cantidad',
            value: '${metrics.count}',
            subtitle: 'ventas',
            icon: Icons.receipt_long_outlined,
          ),
          _KpiCard(
            label: 'Ticket prom.',
            value: formatCop((metrics.total / metrics.count).round()),
            icon: Icons.calculate_outlined,
          ),
        ]),
        const SizedBox(height: 16),
        if (metrics.dailyTotals.length >= 2)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total por día', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: _SalesLineChart(metrics: metrics),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        _DonutCard(
          title: 'Por método de pago',
          data: metrics.byMethod,
        ),
        const SizedBox(height: 16),
        if (metrics.byMaterial.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Por material', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ..._sortedEntries(metrics.byMaterial).map(
                    (e) => _BarRow(
                      label: e.key,
                      value: e.value,
                      max: metrics.byMaterial.values
                          .reduce((a, b) => a > b ? a : b),
                      formatter: formatCop,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (metrics.topPayers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top quien recibe',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ...metrics.topPayers.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.15),
                                child: Text(
                                  '${e.key + 1}',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(e.value.name),
                              ),
                              Text(
                                formatCop(e.value.amount),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<MapEntry<String, num>> _sortedEntries(Map<String, num> m) {
    final l = m.entries.toList();
    l.sort((a, b) => b.value.compareTo(a.value));
    return l;
  }
}

class _SalesLineChart extends StatelessWidget {
  const _SalesLineChart({required this.metrics});
  final SalesMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = <FlSpot>[];
    for (var i = 0; i < metrics.dailyTotals.length; i++) {
      spots.add(FlSpot(i.toDouble(), metrics.dailyTotals[i].total.toDouble()));
    }
    final maxY = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    final niceMaxY = maxY == 0 ? 1.0 : maxY * 1.15;
    final dayFmt = DateFormat('d MMM', 'es_CO');

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: niceMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: niceMaxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: niceMaxY / 4,
              getTitlesWidget: (v, _) => Text(
                _shortMoney(v),
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (metrics.dailyTotals.length / 5).clamp(1, 10).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= metrics.dailyTotals.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dayFmt.format(metrics.dailyTotals[i].day),
                      style: theme.textTheme.labelSmall),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: theme.colorScheme.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  String _shortMoney(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}K';
    return '\$${v.toStringAsFixed(0)}';
  }
}

class _DonutCard extends StatelessWidget {
  const _DonutCard({required this.title, required this.data});
  final String title;
  final Map<String, num> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<num>(0, (a, b) => a + b.value);
    final colors = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      Colors.blueAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 32,
                      sectionsSpace: 2,
                      sections: [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value.toDouble(),
                            color: colors[i % colors.length],
                            radius: 22,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < entries.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: colors[i % colors.length],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entries[i].key,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.formatter,
  });

  final String label;
  final num value;
  final num max;
  final String Function(num) formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 8),
              Text(
                formatter(value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct.toDouble(),
              minHeight: 8,
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest,
              valueColor:
                  AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoursSection extends StatelessWidget {
  const _HoursSection({required this.metrics});
  final HoursMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (metrics.entriesCount == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('Sin registros de horas en el rango.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
        ),
      );
    }

    final paidCategories = HoursCategory.values
        .where((c) => c != HoursCategory.lunch)
        .toList();
    final maxMinutes = paidCategories
        .map((c) => metrics.byCategory[c]!.inMinutes)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        _KpiRow(cards: [
          _KpiCard(
            label: 'Horas pagas',
            value: formatHours(metrics.totalPaid),
            icon: Icons.timer_outlined,
          ),
          _KpiCard(
            label: 'Trabajadores',
            value: '${metrics.uniqueWorkers}',
            subtitle: 'con registro',
            icon: Icons.engineering_outlined,
          ),
          _KpiCard(
            label: 'Abiertos',
            value: '${metrics.openCount}',
            subtitle: 'sin cerrar',
            icon: Icons.lock_open_outlined,
            color: metrics.openCount > 0
                ? Colors.orange
                : theme.colorScheme.primary,
          ),
        ]),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Por categoría', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                ...paidCategories.map(
                  (c) => _BarRow(
                    label: c.label,
                    value: metrics.byCategory[c]!.inMinutes,
                    max: maxMinutes == 0 ? 1 : maxMinutes,
                    formatter: (v) =>
                        formatHours(Duration(minutes: v.toInt())),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (metrics.topWorkers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top trabajadores', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ...metrics.topWorkers.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.15),
                                child: Text(
                                  '${e.key + 1}',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(e.value.name)),
                              Text(
                                formatHours(e.value.total),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
