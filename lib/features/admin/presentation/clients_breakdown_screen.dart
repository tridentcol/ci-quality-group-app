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

/// Pantalla detallada del breakdown de clientes. Se llega tocando la
/// card "Clientes" en el dashboard del admin.
///
/// Permite analizar:
///   - % de nuevos vs recurrentes
///   - tasa de adquisición (nuevos / total clientes)
///   - top clientes por revenue
///   - lista completa con filtros (tab nuevos / recurrentes / todos)
class ClientsBreakdownScreen extends ConsumerStatefulWidget {
  const ClientsBreakdownScreen({super.key});

  @override
  ConsumerState<ClientsBreakdownScreen> createState() =>
      _ClientsBreakdownScreenState();
}

class _ClientsBreakdownScreenState
    extends ConsumerState<ClientsBreakdownScreen> {
  late DateTime _start;
  late DateTime _end;
  _ClientFilter _filter = _ClientFilter.all;

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
    final metricsAsync = ref.watch(clientMetricsProvider(range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis de clientes'),
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
                if (m.totalClientsInRange == 0) {
                  return const EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'Sin clientes en el rango',
                    message: 'Cambia el rango de fechas para ver más datos.',
                  );
                }
                final filtered = _filterClients(m.byClient);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    KpiRow(cards: [
                      KpiCard(
                        label: 'Total',
                        value: '${m.totalClientsInRange}',
                        subtitle: 'clientes',
                        icon: Icons.groups_outlined,
                      ),
                      KpiCard(
                        label: 'Nuevos',
                        value: '${m.newClientsCount}',
                        subtitle:
                            '${(m.newClientRate * 100).toStringAsFixed(0)}% del total',
                        icon: Icons.person_add_outlined,
                      ),
                      KpiCard(
                        label: 'Recurrentes',
                        value: '${m.recurrentClientsCount}',
                        subtitle:
                            '${((1 - m.newClientRate) * 100).toStringAsFixed(0)}% del total',
                        icon: Icons.refresh,
                      ),
                    ],),
                    const SizedBox(height: 12),
                    KpiRow(cards: [
                      KpiCard(
                        label: 'Ingreso de nuevos',
                        value: formatCop(m.newClientsRevenue),
                        icon: Icons.payments_outlined,
                      ),
                      KpiCard(
                        label: 'Ingreso recurrentes',
                        value: formatCop(m.recurrentClientsRevenue),
                        icon: Icons.savings_outlined,
                      ),
                    ],),
                    const SizedBox(height: 16),
                    _RecommendationCard(metrics: m),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Distribución',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: SizedBox(
                                height: 12,
                                child: Row(
                                  children: [
                                    if (m.recurrentClientsCount > 0)
                                      Expanded(
                                        flex: m.recurrentClientsCount,
                                        child:
                                            Container(color: theme.colorScheme.primary),
                                      ),
                                    if (m.newClientsCount > 0)
                                      Expanded(
                                        flex: m.newClientsCount,
                                        child: Container(
                                            color: theme.colorScheme.secondary,),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              children: [
                                _Legend(
                                  color: theme.colorScheme.primary,
                                  label: '${m.recurrentClientsCount} recurrentes',
                                ),
                                _Legend(
                                  color: theme.colorScheme.secondary,
                                  label: '${m.newClientsCount} nuevos',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Encabezado + filtro segmentado en columna para que
                    // no se aplaste en pantallas estrechas (el SegmentedButton
                    // de 3 segmentos no cabe al lado del título en mobile).
                    Text(
                      'Lista de clientes',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_ClientFilter>(
                        segments: const [
                          ButtonSegment(
                            value: _ClientFilter.all,
                            label: Text('Todos'),
                          ),
                          ButtonSegment(
                            value: _ClientFilter.nuevos,
                            label: Text('Nuevos'),
                          ),
                          ButtonSegment(
                            value: _ClientFilter.recurrentes,
                            label: Text('Recurrentes'),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) =>
                            setState(() => _filter = s.first),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No hay clientes que coincidan con el filtro.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...filtered.map((c) => _ClientRow(stat: c)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ClientStat> _filterClients(List<ClientStat> all) {
    return switch (_filter) {
      _ClientFilter.all => all,
      _ClientFilter.nuevos => all.where((c) => c.isNew).toList(),
      _ClientFilter.recurrentes => all.where((c) => !c.isNew).toList(),
    };
  }
}

enum _ClientFilter { all, nuevos, recurrentes }

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.metrics});
  final ClientMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newRate = metrics.newClientRate;
    final (icon, headline, body) = _interpret(newRate, metrics);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String, String) _interpret(double rate, ClientMetrics m) {
    if (rate >= 0.6) {
      return (
        Icons.trending_up,
        'Alta adquisición de nuevos clientes',
        '${(rate * 100).toStringAsFixed(0)}% de los clientes activos en el '
            'rango son nuevos. La marca está captando bien — considera '
            'invertir en programas de fidelización para que esos nuevos '
            'se vuelvan recurrentes.',
      );
    }
    if (rate >= 0.3) {
      return (
        Icons.balance_outlined,
        'Mezcla saludable',
        'El ${(rate * 100).toStringAsFixed(0)}% son nuevos y el resto '
            'recurrentes. Buen balance entre adquisición y retención.',
      );
    }
    return (
      Icons.handshake_outlined,
      'Base muy fiel',
      'Solo ${(rate * 100).toStringAsFixed(0)}% de los clientes son nuevos; '
          'la mayor parte de la facturación viene de recurrentes. '
          'Considera invertir en marketing/comercial para captar nuevos '
          'leads y diversificar.',
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.stat});
  final ClientStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Row(
          children: [
            Expanded(
              child: Text(
                stat.name,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (stat.isNew)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.secondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'NUEVO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${stat.salesCount} venta${stat.salesCount == 1 ? '' : 's'} · '
            '${formatDate(stat.firstPurchaseInRange)} – '
            '${formatDate(stat.lastPurchaseInRange)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
        trailing: Text(
          formatCop(stat.revenue),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
