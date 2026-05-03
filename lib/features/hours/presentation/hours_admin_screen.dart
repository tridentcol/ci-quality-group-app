import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/services/xlsx_export_service.dart';
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
        entries: entries,
        rangeStart: _start,
        rangeEnd: _end,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horas laboradas'),
        actions: [
          IconButton(
            tooltip: 'Filtrar fechas',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickRange,
          ),
          IconButton(
            tooltip: 'Exportar a Excel',
            onPressed: _exporting
                ? null
                : () => _export(_filtered(entries.valueOrNull ?? const [])),
            icon: _exporting
                ? const SizedBox(
                    width: 18, height: 18,
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final filtered = _filtered(data);
          final totals = _aggregate(filtered);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _RangeBanner(
                  start: _start,
                  end: _end,
                  count: filtered.length,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: BreakdownCard(
                    breakdown: totals,
                    title: 'Totales del rango',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: DropdownButtonFormField<String?>(
                    value: _workerFilter,
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
                          )),
                    ],
                    onChanged: (v) => setState(() => _workerFilter = v),
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No hay registros en este rango.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
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

class _RangeBanner extends StatelessWidget {
  const _RangeBanner({
    required this.start,
    required this.end,
    required this.count,
  });
  final DateTime start;
  final DateTime end;
  final int count;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 4),
          Text(
            '$count registro${count == 1 ? '' : 's'}',
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                        ))
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
