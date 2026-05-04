import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../workers/data/workers_repository.dart';
import '../../workers/domain/worker.dart';
import '../data/hours_repository.dart';
import '../domain/hours_categories.dart';
import '../domain/hours_entry.dart';

/// Pantalla principal del encargado de horas: lista de trabajadores activos
/// con su estado del día (sin abrir, abierto, cerrado).
class HoursHomeScreen extends ConsumerStatefulWidget {
  const HoursHomeScreen({super.key});

  @override
  ConsumerState<HoursHomeScreen> createState() => _HoursHomeScreenState();
}

class _HoursHomeScreenState extends ConsumerState<HoursHomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final workers = ref.watch(activeWorkersProvider);
    final today = ref.watch(todayHoursByWorkerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de horas'),
        actions: [
          const ThemeModeIconButton(),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          _TodayHeader(
            entries: today.valueOrNull ?? const {},
            workers: workers.valueOrNull ?? const [],
          ),
          if (today.hasError)
            _DiagnosticBanner(
              source: 'hours_entries',
              error: today.error!,
              onRetry: () => ref.invalidate(todayHoursByWorkerProvider),
            ),
          if (workers.hasError)
            _DiagnosticBanner(
              source: 'workers',
              error: workers.error!,
              onRetry: () => ref.invalidate(activeWorkersProvider),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar trabajador…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(activeWorkersProvider);
                ref.invalidate(todayHoursByWorkerProvider);
              },
              child: workers.when(
                loading: () => const SkeletonList(),
                error: (e, _) => AppErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(activeWorkersProvider),
                ),
                data: (data) {
                  final filtered = _query.isEmpty
                      ? data
                      : data
                          .where((w) =>
                              w.fullName.toLowerCase().contains(_query) ||
                              w.role.toLowerCase().contains(_query),)
                          .toList();
                  if (filtered.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          icon: Icons.engineering_outlined,
                          title: data.isEmpty
                              ? 'Sin trabajadores activos'
                              : 'Sin coincidencias',
                          message: data.isEmpty
                              ? 'Pídele al admin que los cargue desde el panel.'
                              : 'Prueba con otro término.',
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final w = filtered[i];
                      final entry = (today.valueOrNull ?? const {})[w.id];
                      return _WorkerHoursCard(
                        worker: w,
                        entry: entry,
                        onTap: () => context.push('/hours/${w.id}'),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticBanner extends StatelessWidget {
  const _DiagnosticBanner({
    required this.source,
    required this.error,
    required this.onRetry,
  });

  final String source;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$source: $error',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.entries, required this.workers});

  final Map<String, HoursEntry> entries;
  final List<Worker> workers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeIds = workers.map((w) => w.id).toSet();
    int closed = 0;
    int open = 0;
    for (final e in entries.values) {
      if (!activeIds.contains(e.workerId)) continue;
      if (e.isOpen) {
        open++;
      } else {
        closed++;
      }
    }
    final pending = workers.length - open - closed;
    final onPrimary = theme.colorScheme.onPrimary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hoy ${formatDate(AppClock.now())}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: onPrimary.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: 'Abiertos', value: '$open', color: onPrimary),
              const SizedBox(width: 28),
              _Stat(label: 'Cerrados', value: '$closed', color: onPrimary),
              const SizedBox(width: 28),
              _Stat(
                label: 'Sin marcar',
                value: '$pending',
                color: onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color.withValues(alpha: 0.85)),),
      ],
    );
  }
}

class _WorkerHoursCard extends StatelessWidget {
  const _WorkerHoursCard({
    required this.worker,
    required this.entry,
    required this.onTap,
  });

  final Worker worker;
  final HoursEntry? entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEntry = entry != null;
    final isOpen = entry?.isOpen ?? false;
    final color = !hasEntry
        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
        : isOpen
            ? theme.colorScheme.primary
            : theme.colorScheme.secondary;
    final statusLabel = !hasEntry
        ? 'Sin marcar'
        : isOpen
            ? 'Día abierto'
            : 'Cerrado';
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(worker.fullName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      worker.role,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    if (hasEntry) ...[
                      const SizedBox(height: 6),
                      Text(
                        _summary(entry!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                  if (hasEntry && !entry!.isOpen) ...[
                    const SizedBox(height: 6),
                    Text(
                      formatHours(entry!.breakdown.totalPaid),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summary(HoursEntry e) {
    final inStr = formatTime(e.checkIn);
    final outStr = e.checkOut != null ? formatTime(e.checkOut!) : '—';
    return 'Entrada $inStr · Salida $outStr';
  }
}
