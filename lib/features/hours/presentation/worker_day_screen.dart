import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/time_picker.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../workers/data/workers_repository.dart';
import '../../workers/domain/worker.dart';
import '../data/hours_repository.dart';
import '../data/work_schedule_repository.dart';
import '../data/work_shifts_repository.dart';
import '../domain/hours_entry.dart';
import '../domain/work_schedule.dart';
import '../domain/work_shift.dart';
import 'widgets/breakdown_card.dart';
import 'widgets/time_range_cards.dart';

/// Pantalla del trabajador-día. Permite:
///  - Abrir el día con la entrada (default = ahora).
///  - Ajustar la entrada / salida durante el día.
///  - Cerrar el día (calcula el desglose).
///  - Editar dentro de la ventana de 24 h o, si eres admin, siempre.
class WorkerDayScreen extends ConsumerStatefulWidget {
  const WorkerDayScreen({super.key, required this.workerId, this.date});

  final String workerId;

  /// Fecha del registro. `null` = hoy.
  final DateTime? date;

  @override
  ConsumerState<WorkerDayScreen> createState() => _WorkerDayScreenState();
}

class _WorkerDayScreenState extends ConsumerState<WorkerDayScreen> {
  late DateTime _date;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = widget.date ?? AppClock.now();
  }

  /// Jornada efectiva para un registro con el turno [shiftId]. Espera a
  /// que los turnos carguen: caer a la jornada general por un stream que
  /// aún no emite dejaría un desglose equivocado guardado.
  Future<WorkSchedule> _scheduleFor(String? shiftId) async {
    final base =
        ref.read(workScheduleProvider).valueOrNull ?? const WorkSchedule();
    if (shiftId == null) return base;
    final shifts = await ref.read(workShiftsProvider.future);
    return resolveSchedule(base, shifts, shiftId);
  }

  Future<void> _openDay(Worker worker) async {
    setState(() => _busy = true);
    try {
      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) throw StateError('Sesión inválida.');
      final shift = activeShiftById(
        await ref.read(workShiftsProvider.future),
        worker.shiftId,
      );
      final now = AppClock.now();
      final start = shift?.rangeFor(_date);
      final checkIn = isSameDay(now, _date)
          ? now
          : DateTime(
              _date.year,
              _date.month,
              _date.day,
              start?.startHour ?? 7,
              start?.startMinute ?? 0,
            );
      await ref.read(hoursRepositoryProvider).openDay(
            workerId: worker.id,
            workerName: worker.fullName,
            checkIn: checkIn,
            createdBy: profile.uid,
            createdByName: profile.fullName,
            shiftId: shift?.id,
            shiftName: shift?.name,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir el día: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editTime(
    HoursEntry entry, {
    required bool checkIn,
  }) async {
    final initial =
        checkIn ? entry.checkIn : (entry.checkOut ?? AppClock.now());
    final pickedTime = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: checkIn ? 'Hora de entrada' : 'Hora de salida',
    );
    if (pickedTime == null) return;
    final newDt = DateTime(
      initial.year,
      initial.month,
      initial.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() => _busy = true);
    try {
      final schedule = await _scheduleFor(entry.shiftId);
      if (checkIn) {
        await ref
            .read(hoursRepositoryProvider)
            .updateEntry(entry.id, checkIn: newDt, schedule: schedule);
      } else {
        await ref
            .read(hoursRepositoryProvider)
            .updateEntry(entry.id, checkOut: newDt, schedule: schedule);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCheckOutNow(HoursEntry entry) async {
    setState(() => _busy = true);
    try {
      await ref.read(hoursRepositoryProvider).updateEntry(
            entry.id,
            checkOut: AppClock.now(),
            schedule: await _scheduleFor(entry.shiftId),
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeDay(HoursEntry entry) async {
    if (entry.checkOut == null) {
      await _setCheckOutNow(entry);
      // Recargamos la entry recién actualizada
      final updated =
          await ref.read(hoursRepositoryProvider).getEntry(entry.id);
      if (updated == null) return;
      entry = updated;
    }
    if (!mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Cerrar día',
      message: 'Se cerrará el día con entrada ${formatTime(entry.checkIn)} y '
          'salida ${formatTime(entry.checkOut!)}. Después tendrás 24 h para '
          'corregir antes de que solo el admin pueda editar.',
      confirmLabel: 'Cerrar día',
      icon: Icons.check_circle_outline,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(hoursRepositoryProvider).closeDay(
            entry.id,
            checkOut: entry.checkOut!,
            schedule: await _scheduleFor(entry.shiftId),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Día cerrado.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cambia el turno solo para este día (ej. alguien cubre el otro turno).
  /// No toca el turno asignado al trabajador.
  Future<void> _changeShift(HoursEntry entry, List<WorkShift> shifts) async {
    final options = shifts.where((s) => s.active).toList();
    // `''` representa "jornada general"; `null` es cancelar el diálogo.
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Turno de este día'),
        children: [
          for (final s in options)
            ListTile(
              leading: Icon(
                s.id == entry.shiftId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(s.name),
              subtitle: Text(formatTimeRange(s.rangeFor(entry.workDate))),
              onTap: () => Navigator.pop(ctx, s.id),
            ),
          ListTile(
            leading: Icon(
              entry.shiftId == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: const Text('Jornada general'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
        ],
      ),
    );
    if (picked == null || picked == (entry.shiftId ?? '')) return;
    final shiftId = picked.isEmpty ? null : picked;
    String? shiftName;
    for (final s in options) {
      if (s.id == shiftId) shiftName = s.name;
    }
    setState(() => _busy = true);
    try {
      await ref.read(hoursRepositoryProvider).updateEntry(
            entry.id,
            changeShift: true,
            shiftId: shiftId,
            shiftName: shiftName,
            schedule: await _scheduleFor(shiftId),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopenDay(HoursEntry entry) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reabrir día',
      message:
          'Se descartará el desglose calculado y podrás ajustar la entrada o '
          'salida.',
      confirmLabel: 'Reabrir',
      icon: Icons.lock_open_outlined,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(hoursRepositoryProvider).reopenDay(entry.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEntry(HoursEntry entry) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Eliminar registro',
      message: 'Esto borrará por completo el registro de ese día.',
      confirmLabel: 'Eliminar',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    try {
      await ref.read(hoursRepositoryProvider).deleteEntry(entry.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  bool _canEdit(HoursEntry entry) {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile == null) return false;
    if (profile.role == AppRole.admin) return true;
    if (entry.editableUntil == null) return true; // día abierto
    return AppClock.now().isBefore(entry.editableUntil!);
  }

  @override
  Widget build(BuildContext context) {
    final workerAsync = ref.watch(workerByIdProvider(widget.workerId));
    final entryAsync = ref.watch(workerDayEntryProvider(
      WorkerDayQuery(workerId: widget.workerId, date: _date),
    ),);

    return Scaffold(
      appBar: AppBar(
        title: workerAsync.maybeWhen(
          data: (w) => Text(w?.fullName ?? 'Trabajador'),
          orElse: () => const Text('Trabajador'),
        ),
        actions: const [ThemeModeIconButton()],
      ),
      body: workerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(error: e),
        data: (worker) {
          if (worker == null) {
            return const Center(child: Text('Este trabajador ya no existe.'));
          }
          final entry = entryAsync.valueOrNull;
          final shifts =
              ref.watch(workShiftsProvider).valueOrNull ?? const <WorkShift>[];
          final isAdmin = ref.watch(currentProfileProvider.select(
            (a) => a.valueOrNull?.role == AppRole.admin,
          ),);
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              children: [
                HeroBanner(
                  title: '${worker.role} · ${formatDate(_date)}',
                  primaryValue: worker.fullName,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: entry == null
                      ? _NoEntryView(
                          busy: _busy, onOpen: () => _openDay(worker),)
                      : Column(
                          children: [
                            _TimesCard(
                              entry: entry,
                              canEdit: _canEdit(entry),
                              onEditCheckIn: () =>
                                  _editTime(entry, checkIn: true),
                              onEditCheckOut: () =>
                                  _editTime(entry, checkIn: false),
                              onSetCheckOutNow: () => _setCheckOutNow(entry),
                            ),
                            const SizedBox(height: 12),
                            _ShiftTile(
                              entry: entry,
                              shifts: shifts,
                              onChange: _canEdit(entry)
                                  ? () => _changeShift(entry, shifts)
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            // El desglose por categoría legal solo lo ve el
                            // admin; el encargado no necesita ese detalle.
                            if (!entry.isOpen && isAdmin)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child:
                                    BreakdownCard(breakdown: entry.breakdown),
                              ),
                            if (entry.editableUntil != null && !entry.isOpen)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child:
                                    _EditableHint(until: entry.editableUntil!),
                              ),
                            Row(
                              children: [
                                if (entry.isOpen)
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed:
                                          _busy ? null : () => _closeDay(entry),
                                      icon: const Icon(
                                          Icons.check_circle_outline,),
                                      label: const Text('Cerrar día'),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _canEdit(entry) && !_busy
                                          ? () => _reopenDay(entry)
                                          : null,
                                      icon:
                                          const Icon(Icons.lock_open_outlined),
                                      label: const Text('Reabrir'),
                                    ),
                                  ),
                              ],
                            ),
                            if (isAdmin)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TextButton.icon(
                                  onPressed:
                                      _busy ? null : () => _deleteEntry(entry),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Eliminar registro'),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NoEntryView extends StatelessWidget {
  const _NoEntryView({required this.busy, required this.onOpen});
  final bool busy;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.access_time, size: 48),
            const SizedBox(height: 12),
            Text(
              'Sin marcar todavía',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Al abrir el día, la entrada queda en la hora actual. '
              'Puedes ajustarla después.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Marcar entrada'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimesCard extends StatelessWidget {
  const _TimesCard({
    required this.entry,
    required this.canEdit,
    required this.onEditCheckIn,
    required this.onEditCheckOut,
    required this.onSetCheckOutNow,
  });

  final HoursEntry entry;
  final bool canEdit;
  final VoidCallback onEditCheckIn;
  final VoidCallback onEditCheckOut;
  final VoidCallback onSetCheckOutNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _TimeBlock(
                    label: 'Entrada',
                    time: entry.checkIn,
                    onEdit: canEdit ? onEditCheckIn : null,
                    icon: Icons.login_outlined,
                  ),
                ),
                Container(
                  width: 1,
                  height: 56,
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
                Expanded(
                  child: _TimeBlock(
                    label: 'Salida',
                    time: entry.checkOut,
                    onEdit: canEdit
                        ? (entry.checkOut == null
                            ? onSetCheckOutNow
                            : onEditCheckOut)
                        : null,
                    icon: Icons.logout_outlined,
                    placeholderAction: 'Marcar ahora',
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

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({
    required this.entry,
    required this.shifts,
    required this.onChange,
  });

  final HoursEntry entry;
  final List<WorkShift> shifts;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    WorkShift? shift;
    for (final s in shifts) {
      if (s.id == entry.shiftId) shift = s;
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.groups_outlined),
        title: Text(entry.shiftName ?? shift?.name ?? 'Jornada general'),
        subtitle: Text(
          shift == null
              ? 'Turno de este día'
              : 'Turno de este día · '
                  '${formatTimeRange(shift.rangeFor(entry.workDate))}',
        ),
        trailing: onChange == null ? null : const Icon(Icons.swap_horiz),
        onTap: onChange,
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.time,
    required this.onEdit,
    required this.icon,
    this.placeholderAction,
  });

  final String label;
  final DateTime? time;
  final VoidCallback? onEdit;
  final IconData icon;
  final String? placeholderAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time != null ? formatTime(time!) : placeholderAction ?? '—',
              style: theme.textTheme.titleLarge?.copyWith(
                color: time != null
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableHint extends StatelessWidget {
  const _EditableHint({required this.until});
  final DateTime until;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stillEditable = AppClock.now().isBefore(until);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            stillEditable ? Icons.timer_outlined : Icons.lock_outline,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stillEditable
                  ? 'Editable hasta ${formatDateTime(until)}'
                  : 'La ventana de edición venció. Solo el admin puede modificar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
