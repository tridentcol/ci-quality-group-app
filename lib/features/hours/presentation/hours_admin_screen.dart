import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../shared/services/xlsx_export_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../admin/presentation/admin_shell.dart';
import '../../workers/data/workers_repository.dart';
import '../data/hours_repository.dart';
import '../domain/hours_categories.dart';
import '../domain/hours_entry.dart';
import 'widgets/breakdown_card.dart';

class HoursAdminScreen extends ConsumerStatefulWidget {
  const HoursAdminScreen({super.key});

  @override
  ConsumerState<HoursAdminScreen> createState() => _HoursAdminScreenState();
}

class _HoursAdminScreenState extends ConsumerState<HoursAdminScreen> {
  late DateTime _start;
  late DateTime _end;
  String? _workerFilter;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  Future<void> _export(List<HoursEntry> entries) async {
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros en el rango.')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      await XlsxExportService.exportHours(
        context: context,
        entries: entries,
        rangeStart: _start,
        rangeEnd: _end,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(
      hoursByRangeProvider(HoursDateRange(start: _start, end: _end)),
    );
    final workers = ref.watch(allWorkersProvider).valueOrNull ?? const [];
    return Scaffold(
      drawer: adminDrawerOrNull(context, '/admin/hours'),
      appBar: AppBar(
        title: const Text('Horas laboradas'),
        actions: [
          IconButton(
            tooltip: 'Exportar a Excel (rango actual)',
            onPressed: _exporting
                ? null
                : () => _export(_filtered(entries.valueOrNull ?? const [])),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/hours/manual'),
        icon: const Icon(Icons.add),
        label: const Text('Entrada manual'),
      ),
      body: entries.when(
        loading: () => const SkeletonList(),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(
              hoursByRangeProvider(HoursDateRange(start: _start, end: _end)),),
        ),
        data: (data) {
          final filtered = _filtered(data);
          final totals = _aggregate(filtered);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(
                hoursByRangeProvider(HoursDateRange(start: _start, end: _end)),),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: HeroBanner(
                    title: 'Registros del rango',
                    primaryValue: '${filtered.length}',
                    secondary:
                        'registro${filtered.length == 1 ? '' : 's'} cargado${filtered.length == 1 ? '' : 's'}',
                  ),
                ),
                SliverToBoxAdapter(
                  child: RangeFilterBar(
                    start: _start,
                    end: _end,
                    onChanged: (r) => setState(() {
                      _start = r.start;
                      _end = r.end;
                    }),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: DropdownButtonFormField<String?>(
                      initialValue: _workerFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por trabajador',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos los trabajadores'),
                        ),
                        ...workers.map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.fullName),
                            ),),
                      ],
                      onChanged: (v) => setState(() => _workerFilter = v),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: BreakdownCard(
                      breakdown: totals,
                      title: 'Totales del rango',
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  const SliverToBoxAdapter(
                    child: EmptyState(
                      icon: Icons.schedule_outlined,
                      title: 'Sin registros en el rango',
                      message:
                          'Cambia el rango o crea una entrada manual con el botón inferior.',
                    ),
                  )
                else
                  SliverList.separated(
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _HoursEntryCard(
                          entry: e,
                          onTap: () =>
                              context.push('/admin/hours/manual/${e.id}'),
                        ),
                      );
                    },
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
              ],
            ),
          );
        },
      ),
    );
  }

  List<HoursEntry> _filtered(List<HoursEntry> data) {
    if (_workerFilter == null) return data;
    return data.where((e) => e.workerId == _workerFilter).toList();
  }

  HoursBreakdown _aggregate(List<HoursEntry> entries) {
    var total = HoursBreakdown();
    for (final e in entries) {
      total = total + e.breakdown;
    }
    return total;
  }
}

class _HoursEntryCard extends StatelessWidget {
  const _HoursEntryCard({required this.entry, required this.onTap});
  final HoursEntry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 48,
                decoration: BoxDecoration(
                  color: entry.isOpen
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.workerName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDate(entry.workDate)} · '
                      '${formatTime(entry.checkIn)}'
                      '${entry.checkOut != null ? " – ${formatTime(entry.checkOut!)}" : ""}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (entry.isOpen)
                    Text('Abierto',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),)
                  else
                    Text(
                      formatHours(entry.breakdown.totalPaid),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
