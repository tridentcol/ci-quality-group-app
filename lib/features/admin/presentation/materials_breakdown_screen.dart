import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/kpi_card.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../sales/data/sales_repository.dart';
import '../data/metrics.dart';

/// Pantalla detallada del breakdown por material. Se llega tocando la
/// card "Por material" en el dashboard del admin.
///
/// Muestra:
///   - KPIs: # materiales únicos, top material, ingreso por material
///   - Lista completa con barras + % del total
///   - Filtros de rango
class MaterialsBreakdownScreen extends ConsumerStatefulWidget {
  const MaterialsBreakdownScreen({super.key});

  @override
  ConsumerState<MaterialsBreakdownScreen> createState() =>
      _MaterialsBreakdownScreenState();
}

class _MaterialsBreakdownScreenState
    extends ConsumerState<MaterialsBreakdownScreen> {
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
    final theme = Theme.of(context);
    final range = SalesDateRange(start: _start, end: _end);
    final metricsAsync = ref.watch(salesMetricsProvider(range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis por material'),
        actions: const [ThemeModeIconButton()],
      ),
      body: Column(
        children: [
          RangeFilterBar(
            start: _start,
            end: _end,
            onChanged: (r) => setState(() {
              _start = r.start;
              _end = r.end;
            }),
          ),
          Expanded(
            child: metricsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorView(error: e),
              data: (m) {
                if (m.byMaterial.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Sin ventas en el rango',
                    message:
                        'Cambia el rango de fechas para ver el desglose '
                        'por material.',
                  );
                }
                final entries = m.byMaterial.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final maxValue = entries.first.value;
                final top = entries.first;
                final total = m.total;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    KpiRow(cards: [
                      KpiCard(
                        label: '# Materiales',
                        value: '${entries.length}',
                        subtitle: 'distintos',
                        icon: Icons.category_outlined,
                      ),
                      KpiCard(
                        label: 'Top material',
                        value: top.key,
                        subtitle: formatCop(top.value),
                        icon: Icons.emoji_events_outlined,
                      ),
                      KpiCard(
                        label: 'Total facturado',
                        value: formatCop(total),
                        icon: Icons.payments_outlined,
                      ),
                    ],),
                    const SizedBox(height: 16),
                    Text(
                      'Distribución',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            for (final e in entries)
                              _MaterialRow(
                                label: e.key,
                                value: e.value,
                                max: maxValue,
                                pctOfTotal: e.value / total,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.label,
    required this.value,
    required this.max,
    required this.pctOfTotal,
  });
  final String label;
  final num value;
  final num max;
  final double pctOfTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pctOfMax = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatCop(value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(pctOfTotal * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pctOfMax,
              minHeight: 6,
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.10),
              valueColor:
                  AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
