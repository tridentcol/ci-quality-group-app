import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../workers/data/workers_repository.dart';
import '../../workers/domain/worker.dart';
import '../data/work_schedule_repository.dart';
import '../data/work_shifts_repository.dart';
import '../domain/hours_categories.dart';
import '../domain/work_schedule.dart';
import '../domain/work_shift.dart';
import 'shift_form_screen.dart';
import 'widgets/time_range_cards.dart';

/// Turnos de trabajo y a qué trabajadores aplica cada uno. La usan el
/// admin y el encargado de horas, para que un cambio de horarios en la
/// empresa no dependa de tocar código.
class ShiftsScreen extends ConsumerWidget {
  const ShiftsScreen({super.key});

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    WorkShift shift,
    List<Worker> workers,
    List<WorkShift> shifts,
  ) async {
    final current =
        workers.where((w) => w.shiftId == shift.id).map((w) => w.id).toSet();
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AssignWorkersSheet(
        shift: shift,
        workers: workers,
        shifts: shifts,
        initial: current,
      ),
    );
    if (selected == null || !context.mounted) return;

    final added = selected.difference(current);
    final removed = current.difference(selected);
    if (added.isEmpty && removed.isEmpty) return;
    try {
      final repo = ref.read(workersRepositoryProvider);
      if (added.isNotEmpty) await repo.setShift(added, shift.id);
      if (removed.isNotEmpty) await repo.setShift(removed, null);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trabajadores de "${shift.name}" guardados.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftsAsync = ref.watch(workShiftsProvider);
    final workersAsync = ref.watch(activeWorkersProvider);
    final general =
        ref.watch(workScheduleProvider).valueOrNull ?? const WorkSchedule();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turnos'),
        actions: const [ThemeModeIconButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/hours/shifts/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo turno'),
      ),
      body: shiftsAsync.when(
        loading: () => const SkeletonList(),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(workShiftsProvider),
        ),
        data: (shifts) {
          final workers = workersAsync.valueOrNull ?? const <Worker>[];
          final active = shifts.where((s) => s.active).toList();
          final inactive = shifts.where((s) => !s.active).toList();
          final activeIds = active.map((s) => s.id).toSet();
          final unassigned =
              workers.where((w) => !activeIds.contains(w.shiftId)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              const _InfoBanner(),
              const SizedBox(height: 16),
              if (active.isEmpty)
                const EmptyState(
                  icon: Icons.schedule_outlined,
                  title: 'Aún no hay turnos',
                  message: 'Mientras no existan turnos, todos los trabajadores '
                      'se calculan con la jornada general.',
                )
              else
                for (final shift in active) ...[
                  _ShiftCard(
                    shift: shift,
                    workers:
                        workers.where((w) => w.shiftId == shift.id).toList(),
                    onEdit: () => context.push('/hours/shifts/${shift.id}'),
                    onAssign: () =>
                        _assign(context, ref, shift, workers, active),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 12),
              const SectionLabel('Sin turno'),
              const SizedBox(height: 8),
              _UnassignedCard(workers: unassigned, general: general),
              if (inactive.isNotEmpty) ...[
                const SizedBox(height: 24),
                const SectionLabel('Turnos inactivos'),
                const SizedBox(height: 8),
                for (final shift in inactive)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.block_outlined),
                      title: Text(shift.name),
                      subtitle: Text(formatTimeRange(shift.weekday)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/hours/shifts/${shift.id}'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'El turno define las horas ordinarias de cada trabajador; lo '
              'que trabaje fuera de ese horario cuenta como hora extra. '
              'Puedes cambiar el turno de un día puntual desde el registro '
              'del trabajador.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.workers,
    required this.onEdit,
    required this.onAssign,
  });

  final WorkShift shift;
  final List<Worker> workers;
  final VoidCallback onEdit;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final effective = effectiveShiftDuration(shift.weekday, shift.weekdayLunch);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(shift.name, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Editar turno',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
              ],
            ),
            Text(
              '${formatTimeRange(shift.weekday)} · ${formatHours(effective)}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (shift.weekdayLunch != null ||
                shift.saturday != null ||
                shift.sunday != null) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (shift.weekdayLunch != null)
                    'Almuerzo ${formatTimeRange(shift.weekdayLunch!)}',
                  if (shift.saturday != null)
                    'Sábado ${formatTimeRange(shift.saturday!)}',
                  if (shift.sunday != null)
                    'Dom/festivo ${formatTimeRange(shift.sunday!)}',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: 12),
            if (workers.isEmpty)
              Text(
                'Sin trabajadores asignados.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final w in workers) Chip(label: Text(w.fullName)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAssign,
              icon: const Icon(Icons.group_add_outlined),
              label: Text(
                workers.isEmpty
                    ? 'Asignar trabajadores'
                    : 'Cambiar trabajadores (${workers.length})',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnassignedCard extends StatelessWidget {
  const _UnassignedCard({required this.workers, required this.general});

  final List<Worker> workers;
  final WorkSchedule general;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jornada general · ${formatTimeRange(general.weekdayOrdinary)}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'La configura el administrador y aplica a quien no tiene turno.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            if (workers.isEmpty)
              Text(
                'Todos los trabajadores tienen turno.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final w in workers) Chip(label: Text(w.fullName)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AssignWorkersSheet extends StatefulWidget {
  const _AssignWorkersSheet({
    required this.shift,
    required this.workers,
    required this.shifts,
    required this.initial,
  });

  final WorkShift shift;
  final List<Worker> workers;
  final List<WorkShift> shifts;
  final Set<String> initial;

  @override
  State<_AssignWorkersSheet> createState() => _AssignWorkersSheetState();
}

class _AssignWorkersSheetState extends State<_AssignWorkersSheet> {
  late final Set<String> _selected = {...widget.initial};

  String? _otherShiftName(Worker w) {
    if (w.shiftId == null || w.shiftId == widget.shift.id) return null;
    for (final s in widget.shifts) {
      if (s.id == w.shiftId) return s.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Trabajadores de "${widget.shift.name}"',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final w in widget.workers)
                    CheckboxListTile(
                      value: _selected.contains(w.id),
                      title: Text(w.fullName),
                      subtitle: _otherShiftName(w) == null
                          ? null
                          : Text('Ahora está en ${_otherShiftName(w)}'),
                      onChanged: (on) => setState(() {
                        if (on ?? false) {
                          _selected.add(w.id);
                        } else {
                          _selected.remove(w.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: Text('Guardar (${_selected.length})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
