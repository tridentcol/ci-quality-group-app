import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/kpi_card.dart';
import 'admin_shell.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../../hours/data/hours_repository.dart';
import '../../hours/domain/hours_categories.dart';
import '../../sales/data/sales_repository.dart';
import '../data/metrics.dart';

enum _MetricsView { sales, hours }

/// Dashboard del admin con KPIs y gráficas.
///
/// Está dividido en dos vistas (Ventas / Horas) seleccionables con un
/// SegmentedButton en la parte superior. Cada vista mantiene su propio
/// rango de fechas; al cambiar de vista el rango se reinicia al mes
/// corriente para que la consulta sea limpia.
class AdminMetricsScreen extends ConsumerStatefulWidget {
  const AdminMetricsScreen({super.key});

  @override
  ConsumerState<AdminMetricsScreen> createState() => _AdminMetricsScreenState();
}

class _AdminMetricsScreenState extends ConsumerState<AdminMetricsScreen> {
  _MetricsView _view = _MetricsView.sales;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _resetRangeToCurrentMonth();
  }

  void _resetRangeToCurrentMonth() {
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  void _switchView(_MetricsView v) {
    if (v == _view) return;
    setState(() {
      _view = v;
      _resetRangeToCurrentMonth();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawerOrNull(context, '/admin'),
      appBar: AppBar(
        title: const Text('Métricas y gráficas'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_MetricsView>(
                segments: const [
                  ButtonSegment(
                    value: _MetricsView.sales,
                    label: Text('Ventas'),
                    icon: Icon(Icons.receipt_long_outlined),
                  ),
                  ButtonSegment(
                    value: _MetricsView.hours,
                    label: Text('Horas'),
                    icon: Icon(Icons.schedule_outlined),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => _switchView(s.first),
              ),
            ),
          ),
          RangeFilterBar(
            start: _start,
            end: _end,
            onChanged: (r) => setState(() {
              _start = r.start;
              _end = r.end;
            }),
          ),
          Expanded(
            child: _view == _MetricsView.sales
                ? _SalesView(start: _start, end: _end)
                : _HoursView(start: _start, end: _end),
          ),
        ],
      ),
    );
  }
}

/// Vista que renderiza KPIs y gráficas de ventas para el rango dado.
class _SalesView extends ConsumerWidget {
  const _SalesView({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = SalesDateRange(start: start, end: end);
    final metricsAsync = ref.watch(salesMetricsProvider(range));
    // Publicar el rango actual para que la card de "Clientes" pueda
    // leer su provider sin tener que pasarle el rango por constructor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(_currentRangeProvider) != range) {
        ref.read(_currentRangeProvider.notifier).state = range;
      }
    });
    return metricsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorView(error: e),
      data: (m) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [_SalesSection(metrics: m, rangeStart: start)],
      ),
    );
  }
}

/// Vista que renderiza KPIs y gráficas de horas para el rango dado.
class _HoursView extends ConsumerWidget {
  const _HoursView({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(
      hoursMetricsProvider(HoursDateRange(start: start, end: end)),
    );
    return metricsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorView(error: e),
      data: (m) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [_HoursSection(metrics: m)],
      ),
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
    if (metrics.count == 0 &&
        metrics.pendingCount == 0 &&
        metrics.receivableCount == 0 &&
        metrics.lossCount == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('Sin ventas en el rango.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),),),
          ),
        ),
      );
    }

    return Column(
      children: [
        KpiRow(cards: [
          KpiCard(
            label: 'Cobrado',
            value: formatCop(metrics.total),
            icon: Icons.payments_outlined,
          ),
          KpiCard(
            label: 'Procesadas',
            value: '${metrics.count}',
            subtitle: 'ventas',
            icon: Icons.receipt_long_outlined,
          ),
          KpiCard(
            label: 'Ticket prom.',
            value: metrics.count > 0
                ? formatCop((metrics.total / metrics.count).round())
                : '—',
            icon: Icons.functions,
          ),
        ],),
        const SizedBox(height: 12),
        KpiRow(cards: [
          KpiCard(
            label: 'Pendientes en caja',
            value: formatCop(metrics.pendingTotal),
            subtitle:
                '${metrics.pendingCount} solicitud${metrics.pendingCount == 1 ? '' : 'es'}',
            icon: Icons.hourglass_empty,
            color: AppColors.warning,
          ),
          KpiCard(
            label: 'Por cobrar',
            value: formatCop(metrics.receivableTotal),
            subtitle:
                '${metrics.receivableCount} venta${metrics.receivableCount == 1 ? '' : 's'}',
            icon: Icons.account_balance_outlined,
            color: AppColors.info,
          ),
          KpiCard(
            label: 'Pérdidas',
            value: formatCop(metrics.lossTotal),
            subtitle:
                '${metrics.lossCount} venta${metrics.lossCount == 1 ? '' : 's'}',
            icon: Icons.error_outline,
            color: AppColors.danger,
          ),
        ],),
        const SizedBox(height: 16),
        if (metrics.dailyTotals.length >= 2)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cobrado por día', style: theme.textTheme.titleMedium),
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
        // Resumen de clientes (nuevos vs recurrentes). Tap → pantalla
        // detallada con KPIs, lista, filtros.
        _ClientsSummaryCard(rangeStart: rangeStart),
        const SizedBox(height: 16),
        _DonutCard(
          title: 'Por método de pago',
          data: metrics.byMethod,
        ),
        const SizedBox(height: 16),
        if (metrics.byMaterial.isNotEmpty)
          _MaterialsSummaryCard(metrics: metrics),
        if (metrics.topPayers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top quien recibe', style: theme.textTheme.titleMedium),
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
}

/// Helper top-level: usado por _SalesSection y _MaterialsSummaryCard.
List<MapEntry<String, num>> _sortedEntries(Map<String, num> m) {
  final l = m.entries.toList();
  l.sort((a, b) => b.value.compareTo(a.value));
  return l;
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
              interval:
                  (metrics.dailyTotals.length / 5).clamp(1, 10).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= metrics.dailyTotals.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dayFmt.format(metrics.dailyTotals[i].day),
                      style: theme.textTheme.labelSmall,),
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
    final colors = AppColors.chartPaletteFor(theme.brightness);

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
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),),),
          ),
        ),
      );
    }

    final paidCategories =
        HoursCategory.values.where((c) => c != HoursCategory.lunch).toList();
    final maxMinutes = paidCategories
        .map((c) => metrics.byCategory[c]!.inMinutes)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        KpiRow(cards: [
          KpiCard(
            label: 'Horas pagas',
            value: formatHours(metrics.totalPaid),
            icon: Icons.timer,
          ),
          KpiCard(
            label: 'Trabajadores',
            value: '${metrics.uniqueWorkers}',
            subtitle: 'con registro',
            icon: Icons.engineering_outlined,
          ),
          KpiCard(
            label: 'Abiertos',
            value: '${metrics.openCount}',
            subtitle: 'sin cerrar',
            icon: Icons.lock_open,
            color: metrics.openCount > 0
                ? AppColors.warning
                : theme.colorScheme.primary,
          ),
        ],),
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
                    formatter: (v) => formatHours(Duration(minutes: v.toInt())),
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

/// Card resumen de clientes en el dashboard del admin. Lee del
/// `clientMetricsProvider` para mostrar nuevos vs recurrentes en el
/// rango actual. Tap en cualquier parte → abre el breakdown detallado.
class _ClientsSummaryCard extends ConsumerWidget {
  const _ClientsSummaryCard({required this.rangeStart});
  final DateTime rangeStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Ojo: el rango lo manejan los _SalesView/_HoursView. Aquí
    // necesitamos los stats actuales — los recibimos vía un selector
    // del provider que sabemos que ya está cargado para esta fecha.
    // Como el tab activo en _SalesView ya hizo `salesByRangeProvider`,
    // re-watcheamos `allSalesProvider` que es independiente.
    final state = ref.watch(_clientsCardStateProvider);

    return state.when(
      loading: () => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Error cargando clientes: $e',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
      data: (metrics) {
        if (metrics.totalClientsInRange == 0) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('Sin clientes activos en el rango.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),),
              ),
            ),
          );
        }
        final newRate = (metrics.newClientRate * 100).toStringAsFixed(0);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/admin/metrics/clients'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Clientes',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ClientsSplitTile(
                        count: metrics.recurrentClientsCount,
                        revenue: metrics.recurrentClientsRevenue,
                        label: 'Recurrentes',
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      _ClientsSplitTile(
                        count: metrics.newClientsCount,
                        revenue: metrics.newClientsRevenue,
                        label: 'Nuevos',
                        color: theme.colorScheme.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Row(
                      children: [
                        if (metrics.recurrentClientsCount > 0)
                          Expanded(
                            flex: metrics.recurrentClientsCount,
                            child: Container(
                              height: 8,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        if (metrics.newClientsCount > 0)
                          Expanded(
                            flex: metrics.newClientsCount,
                            child: Container(
                              height: 8,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$newRate% de los clientes activos del rango son nuevos. '
                    'Toca para ver el detalle.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClientsSplitTile extends StatelessWidget {
  const _ClientsSplitTile({
    required this.count,
    required this.revenue,
    required this.label,
    required this.color,
  });
  final int count;
  final num revenue;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.1,
              ),
            ),
            Text(
              formatCop(revenue),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card resumen del breakdown por material (con tap-to-expand). Misma
/// estructura visual que la previa pero con InkWell para abrir el
/// detalle. Mantiene la lista corta acá; el detalle muestra todo.
class _MaterialsSummaryCard extends StatelessWidget {
  const _MaterialsSummaryCard({required this.metrics});
  final SalesMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _sortedEntries(metrics.byMaterial);
    final maxValue =
        metrics.byMaterial.values.reduce((a, b) => a > b ? a : b);
    final preview = entries.take(4).toList();
    final hasMore = entries.length > preview.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/admin/metrics/materials'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child:
                        Text('Por material', style: theme.textTheme.titleMedium),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...preview.map(
                (e) => _BarRow(
                  label: e.key,
                  value: e.value,
                  max: maxValue,
                  formatter: formatCop,
                ),
              ),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '… y ${entries.length - preview.length} material'
                    '${entries.length - preview.length == 1 ? '' : 'es'} '
                    'más. Toca para ver todo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Provider local que envuelve `clientMetricsProvider` con el rango
/// que está mostrando _SalesView. Como _ClientsSummaryCard NO tiene
/// acceso directo al state de _SalesView, leemos el último rango
/// publicado vía `_currentRangeProvider`.
final _currentRangeProvider =
    StateProvider<SalesDateRange?>((ref) => null);

final _clientsCardStateProvider =
    Provider.autoDispose<AsyncValue<ClientMetrics>>((ref) {
  final range = ref.watch(_currentRangeProvider);
  if (range == null) {
    return const AsyncValue.data(
      ClientMetrics(
        totalClientsInRange: 0,
        newClientsCount: 0,
        recurrentClientsCount: 0,
        newClientsRevenue: 0,
        recurrentClientsRevenue: 0,
        byClient: [],
      ),
    );
  }
  return ref.watch(clientMetricsProvider(range));
});
