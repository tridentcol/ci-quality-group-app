import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../../shared/widgets/kpi_card.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';

/// Dashboard exclusivo para usuarios con rol `auditor`. Muestra solo
/// las ventas que matchean el `auditFilter` configurado por el admin
/// (ej. socio de láminas tipo PEDRO ve solo ventas con
/// materialVariant == "PEDRO").
///
/// Estructura:
///   - Hero banner con total facturado del rango
///   - RangeFilterBar para seleccionar período
///   - 4 KPI cards: total, # ventas, ticket promedio, cantidad vendida
///   - Gráfica de tendencia diaria
///   - Lista cronológica de ventas (sin info de cliente/método/etc)
///   - (Future) export Excel filtrado
///
/// Si la query trae mucho data se recorta en memoria al rango. Para
/// volúmenes típicos (<1000 ventas históricas) es performante.
class AuditorDashboardScreen extends ConsumerStatefulWidget {
  const AuditorDashboardScreen({super.key});

  @override
  ConsumerState<AuditorDashboardScreen> createState() =>
      _AuditorDashboardScreenState();
}

class _AuditorDashboardScreenState
    extends ConsumerState<AuditorDashboardScreen> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);

    return profile.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: AppErrorView(error: e),
      ),
      data: (user) {
        if (user == null || user.role != AppRole.auditor) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('Acceso denegado.'),
            ),
          );
        }
        final filter = user.auditFilter;
        if (filter == null) {
          return Scaffold(
            appBar: _buildAppBar(context, ref, user),
            body: const _NoFilterState(),
          );
        }
        return _buildDashboard(context, ref, user, filter);
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) {
    return AppBar(
      title: Text('Hola, ${user.fullName}'),
      actions: [
        const ThemeModeIconButton(),
        IconButton(
          tooltip: 'Cerrar sesión',
          icon: const Icon(Icons.logout_outlined),
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ],
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
    AuditFilter filter,
  ) {
    final salesAsync = ref.watch(
      salesByFieldProvider(
        SalesFieldQuery(field: filter.field, value: filter.value),
      ),
    );

    return Scaffold(
      appBar: _buildAppBar(context, ref, user),
      body: salesAsync.when(
        loading: () => const SkeletonList(),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(
            salesByFieldProvider(
              SalesFieldQuery(field: filter.field, value: filter.value),
            ),
          ),
        ),
        data: (allSales) {
          // Filtrar por rango en memoria.
          final inRange = allSales.where((s) {
            return !s.date.isBefore(_start) && !s.date.isAfter(_end);
          }).toList();

          final total = inRange.fold<num>(0, (acc, s) => acc + s.totalValue);
          final count = inRange.length;
          final avgTicket = count > 0 ? total / count : 0;
          final qtyByUnit = _aggregateQuantityByUnit(inRange);
          final daily = _dailyTotals(inRange, _start, _end);
          final allTimeBest = _bestDayAllTime(allSales);

          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
            children: [
                    HeroBanner(
                      title: '${filter.fieldLabel}: ${filter.value} · '
                          '${formatDate(_start)} – ${formatDate(_end)}',
                      primaryValue: formatCop(total),
                      secondary:
                          '$count venta${count == 1 ? '' : 's'} en el rango',
                      icon: Icons.show_chart,
                    ),
                    RangeFilterBar(
                      start: _start,
                      end: _end,
                      onChanged: (r) => setState(() {
                        _start = r.start;
                        _end = r.end;
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: KpiRow(
                        cards: [
                          KpiCard(
                            label: 'Total facturado',
                            value: formatCop(total),
                            icon: Icons.attach_money_outlined,
                          ),
                          KpiCard(
                            label: 'Ventas',
                            value: '$count',
                            subtitle: 'en el rango',
                            icon: Icons.receipt_long_outlined,
                          ),
                          KpiCard(
                            label: 'Ticket promedio',
                            value: formatCop(avgTicket),
                            icon: Icons.trending_up_outlined,
                          ),
                        ],
                      ),
                    ),
                    if (qtyByUnit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: KpiRow(
                          cards: [
                            for (final entry in qtyByUnit.entries)
                              KpiCard(
                                label: 'Cantidad · ${entry.key}',
                                value: _formatQuantity(entry.value),
                                icon: Icons.scale_outlined,
                              ),
                          ],
                        ),
                      ),
                    if (allTimeBest != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: KpiCard(
                          label: 'Mejor día (histórico)',
                          value: formatCop(allTimeBest.total),
                          subtitle: formatDate(allTimeBest.day),
                          icon: Icons.emoji_events_outlined,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: _DailyTrendCard(daily: daily),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Ventas del rango',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (inRange.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Sin ventas en el rango',
                          message:
                              'Cambia el rango de fechas para ver más datos.',
                        ),
                      )
                    else
                      ...inRange.map(
                        (s) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: _AuditorSaleRow(sale: s),
                        ),
                      ),
                  ],
                );
        },
      ),
    );
  }

  /// Agrupa la quantity por unit (kg, unidad, etc). Retorna un mapa
  /// `{ 'kg': 350, 'unidades': 12 }` que se renderiza como KPIs separados.
  Map<String, num> _aggregateQuantityByUnit(List<Sale> sales) {
    final out = <String, num>{};
    for (final s in sales) {
      out.update(s.unit, (v) => v + s.quantity, ifAbsent: () => s.quantity);
    }
    return out;
  }

  /// Genera la serie diaria continua en el rango (rellena ceros).
  List<({DateTime day, num total})> _dailyTotals(
    List<Sale> sales,
    DateTime start,
    DateTime end,
  ) {
    final byDay = <int, num>{};
    for (final s in sales) {
      final key = _ordinal(s.date);
      byDay.update(key, (v) => v + s.totalValue, ifAbsent: () => s.totalValue);
    }
    final out = <({DateTime day, num total})>[];
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      out.add((day: cursor, total: byDay[_ordinal(cursor)] ?? 0));
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }

  /// Mejor día histórico (mayor venta en una fecha).
  ({DateTime day, num total})? _bestDayAllTime(List<Sale> sales) {
    if (sales.isEmpty) return null;
    final byDay = <int, num>{};
    final dayDate = <int, DateTime>{};
    for (final s in sales) {
      final key = _ordinal(s.date);
      dayDate[key] = DateTime(s.date.year, s.date.month, s.date.day);
      byDay.update(key, (v) => v + s.totalValue, ifAbsent: () => s.totalValue);
    }
    int? bestKey;
    num bestTotal = 0;
    byDay.forEach((k, v) {
      if (v > bestTotal) {
        bestKey = k;
        bestTotal = v;
      }
    });
    if (bestKey == null) return null;
    return (day: dayDate[bestKey]!, total: bestTotal);
  }

  static int _ordinal(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  String _formatQuantity(num q) {
    if (q == q.toInt()) return q.toInt().toString();
    return q.toStringAsFixed(2);
  }
}

class _DailyTrendCard extends StatelessWidget {
  const _DailyTrendCard({required this.daily});
  final List<({DateTime day, num total})> daily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (daily.isEmpty) return const SizedBox.shrink();

    final maxY =
        daily.map((d) => d.total).fold<num>(0, (a, b) => a > b ? a : b);
    final niceMaxY = maxY == 0 ? 1.0 : maxY * 1.15;
    // Format más corto para no aplastar el eje X cuando hay muchos días.
    // Para >14 días usamos solo "d/M" (ej. "5/5"); menos días sí aguanta
    // "d MMM" (ej. "5 may").
    final useShortFmt = daily.length > 14;
    final dayFmt = DateFormat(useShortFmt ? 'd/M' : 'd MMM', 'es_CO');
    // Interval: en pantallas mobile (~360-400px de chart útil) caben
    // ~5-6 labels cómodamente. Para 31 días, label cada 7. Para
    // 7 días, cada 1. Para 30 días, cada 6.
    final labelInterval = (daily.length / 5).ceil().clamp(1, 30).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tendencia diaria', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: niceMaxY.toDouble(),
                  minY: 0,
                  gridData: FlGridData(
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
                        interval: labelInterval,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= daily.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              dayFmt.format(daily[i].day),
                              style: theme.textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < daily.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: daily[i].total.toDouble(),
                            color: theme.colorScheme.primary,
                            width: 10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortMoney(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}K';
    return '\$${v.toStringAsFixed(0)}';
  }
}

class _AuditorSaleRow extends StatelessWidget {
  const _AuditorSaleRow({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.receipt_long_outlined,
            color: theme.colorScheme.primary,
            size: 22,
          ),
        ),
        title: Text(
          '${sale.consecutive} · ${formatDate(sale.date)}',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          '${sale.quantity} ${sale.unit.toLowerCase()} '
          '· ${formatCop(sale.unitPrice)}/u',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        trailing: Text(
          formatCop(sale.totalValue),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _NoFilterState extends StatelessWidget {
  const _NoFilterState();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 56,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Filtro no configurado',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tu cuenta de auditor no tiene un filtro asignado. '
              'Contacta al admin para que configure qué datos puedes ver.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
