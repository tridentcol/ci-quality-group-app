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

/// Clave del bucket que agrupa las ventas sin comisionista (directas).
/// Debe coincidir con la usada en `SalesMetrics.compute`.
const _bodegaKey = 'Bodega';

/// Análisis de ventas por comisionista. Se llega tocando la card "Por
/// comisionista" del dashboard admin. Misma estructura que
/// `PayersBreakdownScreen` (KPIs + barras + filtro de rango) para que sea
/// predecible.
///
/// Trato especial del bucket "Bodega": se muestra en la distribución (para
/// comparar bodega vs comisionistas de un vistazo — que es justo lo que se
/// pidió), pero NO cuenta como comisionista en los KPIs "# comisionistas"
/// ni "Top comisionista".
class CommissionAgentsBreakdownScreen extends ConsumerStatefulWidget {
  const CommissionAgentsBreakdownScreen({super.key});

  @override
  ConsumerState<CommissionAgentsBreakdownScreen> createState() =>
      _CommissionAgentsBreakdownScreenState();
}

class _CommissionAgentsBreakdownScreenState
    extends ConsumerState<CommissionAgentsBreakdownScreen> {
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
        title: const Text('Análisis por comisionista'),
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
                final all = Map<String, num>.fromEntries(
                  m.byCommissionAgent.entries
                      .where((e) => e.key.trim().isNotEmpty && e.value > 0),
                );
                if (all.isEmpty) {
                  return const EmptyState(
                    icon: Icons.handshake_outlined,
                    title: 'Sin datos en el rango',
                    message:
                        'Aún no hay ventas procesadas en este rango. Cambia '
                        'el rango o espera a que se procesen ventas en caja.',
                  );
                }

                // Todas las filas (incluye Bodega), ordenadas por monto.
                final entries = all.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final maxValue = entries.first.value;
                final total = entries.fold<num>(0, (acc, e) => acc + e.value);

                // Solo comisionistas reales (sin Bodega) para los KPIs.
                final agentsOnly = entries
                    .where((e) => e.key != _bodegaKey)
                    .toList();
                final bodega = all[_bodegaKey] ?? 0;
                final agentsTotal =
                    agentsOnly.fold<num>(0, (acc, e) => acc + e.value);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    KpiRow(cards: [
                      KpiCard(
                        label: '# Comisionistas',
                        value: '${agentsOnly.length}',
                        subtitle: 'con ventas',
                        icon: Icons.handshake_outlined,
                      ),
                      KpiCard(
                        label: 'Top comisionista',
                        value: agentsOnly.isEmpty ? '—' : agentsOnly.first.key,
                        subtitle: agentsOnly.isEmpty
                            ? 'sin comisionistas'
                            : formatCop(agentsOnly.first.value),
                        icon: Icons.emoji_events_outlined,
                      ),
                      KpiCard(
                        label: 'Por comisionista',
                        value: formatCop(agentsTotal),
                        subtitle: total == 0
                            ? null
                            : '${(agentsTotal / total * 100).toStringAsFixed(0)}% del total',
                        icon: Icons.groups_outlined,
                      ),
                      KpiCard(
                        label: 'Bodega (directo)',
                        value: formatCop(bodega),
                        subtitle: total == 0
                            ? null
                            : '${(bodega / total * 100).toStringAsFixed(0)}% del total',
                        icon: Icons.store_outlined,
                      ),
                    ],),
                    const SizedBox(height: 16),
                    Text('Distribución', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Bodega agrupa las ventas directas (sin comisionista).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            for (final e in entries)
                              _AgentRow(
                                label: e.key,
                                value: e.value,
                                max: maxValue,
                                pctOfTotal: total == 0 ? 0 : e.value / total,
                                isBodega: e.key == _bodegaKey,
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

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.label,
    required this.value,
    required this.max,
    required this.pctOfTotal,
    required this.isBodega,
  });
  final String label;
  final num value;
  final num max;
  final double pctOfTotal;
  final bool isBodega;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Bodega en un tono neutro para diferenciarla visualmente de los
    // comisionistas (que van en el color primario de la marca).
    final barColor =
        isBodega ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                 : theme.colorScheme.primary;
    final pctOfMax =
        max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isBodega) ...[
                Icon(Icons.store_outlined, size: 15, color: barColor),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  isBodega ? 'Bodega (venta directa)' : label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontStyle: isBodega ? FontStyle.italic : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatCop(value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: barColor,
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
              backgroundColor: barColor.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ),
    );
  }
}
