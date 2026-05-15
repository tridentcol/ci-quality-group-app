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

/// Pantalla detallada del breakdown por persona que recibe la plata
/// ("payerName"). Se llega tocando la card "Por quién recibe" del
/// dashboard del admin. Misma estructura que `MaterialsBreakdownScreen`
/// para que sea predecible:
///   - KPIs: # personas distintas, quién recibe más, total recibido
///   - Lista completa con barras + % del total
///   - Filtro de rango propio
class PayersBreakdownScreen extends ConsumerStatefulWidget {
  const PayersBreakdownScreen({super.key});

  @override
  ConsumerState<PayersBreakdownScreen> createState() =>
      _PayersBreakdownScreenState();
}

class _PayersBreakdownScreenState extends ConsumerState<PayersBreakdownScreen> {
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
        title: const Text('Análisis por quién recibe'),
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
                // Filtramos nombres vacíos: las solicitudes nuevas
                // (flujo Fase 6+) no traen payerName todavía, ese campo lo
                // setea cajero al registrar cada abono. Si nadie lo seteó,
                // no tiene sentido mostrarlo como una fila en blanco.
                final filtered = Map<String, num>.fromEntries(
                  m.byPayer.entries.where((e) => e.key.trim().isNotEmpty),
                );
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.person_outline,
                    title: 'Sin datos en el rango',
                    message:
                        'Aún no hay ventas procesadas con "Quién recibe" '
                        'registrado en este rango. Cambia el rango o '
                        'esperá a que se registren abonos en caja.',
                  );
                }
                final entries = filtered.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final maxValue = entries.first.value;
                final top = entries.first;
                final total =
                    entries.fold<num>(0, (acc, e) => acc + e.value);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    KpiRow(cards: [
                      KpiCard(
                        label: '# Personas',
                        value: '${entries.length}',
                        subtitle: 'distintas',
                        icon: Icons.group_outlined,
                      ),
                      KpiCard(
                        label: 'Top quien recibe',
                        value: top.key,
                        subtitle: formatCop(top.value),
                        icon: Icons.emoji_events_outlined,
                      ),
                      KpiCard(
                        label: 'Total recibido',
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
                              _PayerRow(
                                label: e.key,
                                value: e.value,
                                max: maxValue,
                                pctOfTotal:
                                    total == 0 ? 0 : e.value / total,
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

class _PayerRow extends StatelessWidget {
  const _PayerRow({
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
    final pctOfMax =
        max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0).toDouble();
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
