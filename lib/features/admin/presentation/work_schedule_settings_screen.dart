import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/time_picker.dart';
import '../../hours/data/work_schedule_repository.dart';
import '../../hours/domain/work_schedule.dart';

/// Pantalla de configuración global de la jornada laboral.
///
/// Cambios aplican globalmente — pero solo afectan registros nuevos. Las
/// entradas ya cerradas conservan el desglose calculado con la
/// configuración vigente al momento del cierre.
class WorkScheduleSettingsScreen extends ConsumerStatefulWidget {
  const WorkScheduleSettingsScreen({super.key});

  @override
  ConsumerState<WorkScheduleSettingsScreen> createState() =>
      _WorkScheduleSettingsScreenState();
}

class _WorkScheduleSettingsScreenState
    extends ConsumerState<WorkScheduleSettingsScreen> {
  WorkSchedule? _draft;
  WorkSchedule? _initial;
  bool _busy = false;
  String? _error;

  bool get _dirty => _draft != null && !_eq(_draft!, _initial!);

  bool _eq(WorkSchedule a, WorkSchedule b) {
    bool tr(TimeRange? x, TimeRange? y) {
      if (x == null && y == null) return true;
      if (x == null || y == null) return false;
      return x.startMinutes == y.startMinutes && x.endMinutes == y.endMinutes;
    }

    bool tom(TimeOfDayMinutes x, TimeOfDayMinutes y) =>
        x.totalMinutes == y.totalMinutes;

    return tr(a.weekdayOrdinary, b.weekdayOrdinary) &&
        tr(a.weekdayLunch, b.weekdayLunch) &&
        tr(a.saturdayOrdinary, b.saturdayOrdinary) &&
        tr(a.saturdayLunch, b.saturdayLunch) &&
        tr(a.sundayOrdinary, b.sundayOrdinary) &&
        tr(a.sundayLunch, b.sundayLunch) &&
        tom(a.dayStart, b.dayStart) &&
        tom(a.dayEnd, b.dayEnd);
  }

  void _initFrom(WorkSchedule s) {
    if (_initial != null) return;
    _initial = s;
    _draft = s;
  }

  Future<void> _save() async {
    if (_draft == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(workScheduleRepositoryProvider).save(_draft!);
      _initial = _draft;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada.')),
        );
      }
      setState(() {});
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar valores por defecto'),
        content: const Text(
          'Se restablecen todos los rangos al horario estándar de CI Quality '
          'Group. Tendrás que tocar "Guardar cambios" para confirmar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _draft = WorkSchedule.defaultSchedule);
  }

  Future<TimeRange?> _editRange(TimeRange current,
      {required String title}) async {
    final start = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.startHour, minute: current.startMinute),
      helpText: '$title · inicio',
    );
    if (start == null) return null;
    if (!mounted) return null;
    final end = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.endHour, minute: current.endMinute),
      helpText: '$title · fin',
    );
    if (end == null) return null;
    return TimeRange(start.hour, start.minute, end.hour, end.minute);
  }

  Future<TimeOfDayMinutes?> _editTime(TimeOfDayMinutes current,
      {required String title}) async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: title,
    );
    if (picked == null) return null;
    return TimeOfDayMinutes(picked.hour, picked.minute);
  }

  void _setOrdinary(String day, TimeRange r) {
    setState(() {
      _draft = switch (day) {
        'weekday' => _copyWith(weekdayOrdinary: r),
        'saturday' => _copyWith(saturdayOrdinary: r),
        'sunday' => _copyWith(sundayOrdinary: r),
        _ => _draft!,
      };
    });
  }

  void _setLunch(String day, TimeRange? r) {
    setState(() {
      _draft = switch (day) {
        'weekday' => _copyWith(weekdayLunch: r, clearWeekdayLunch: r == null),
        'saturday' => _copyWith(saturdayLunch: r, clearSaturdayLunch: r == null),
        'sunday' => _copyWith(sundayLunch: r, clearSundayLunch: r == null),
        _ => _draft!,
      };
    });
  }

  WorkSchedule _copyWith({
    TimeRange? weekdayOrdinary,
    TimeRange? weekdayLunch,
    bool clearWeekdayLunch = false,
    TimeRange? saturdayOrdinary,
    TimeRange? saturdayLunch,
    bool clearSaturdayLunch = false,
    TimeRange? sundayOrdinary,
    TimeRange? sundayLunch,
    bool clearSundayLunch = false,
    TimeOfDayMinutes? dayStart,
    TimeOfDayMinutes? dayEnd,
  }) {
    final d = _draft!;
    return WorkSchedule(
      weekdayOrdinary: weekdayOrdinary ?? d.weekdayOrdinary,
      weekdayLunch: clearWeekdayLunch ? null : (weekdayLunch ?? d.weekdayLunch),
      saturdayOrdinary: saturdayOrdinary ?? d.saturdayOrdinary,
      saturdayLunch:
          clearSaturdayLunch ? null : (saturdayLunch ?? d.saturdayLunch),
      sundayOrdinary: sundayOrdinary ?? d.sundayOrdinary,
      sundayLunch: clearSundayLunch ? null : (sundayLunch ?? d.sundayLunch),
      dayStart: dayStart ?? d.dayStart,
      dayEnd: dayEnd ?? d.dayEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(workScheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de jornada'),
        actions: [
          IconButton(
            tooltip: 'Restaurar valores por defecto',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _resetDefaults,
          ),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) {
          _initFrom(s);
          final draft = _draft!;
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _InfoBanner(),
                const SizedBox(height: 16),
                _SectionLabel('Jornada ordinaria'),
                const SizedBox(height: 8),
                _OrdinaryCard(
                  label: 'Lunes a viernes',
                  range: draft.weekdayOrdinary,
                  onEdit: () async {
                    final r = await _editRange(draft.weekdayOrdinary,
                        title: 'Jornada L–V');
                    if (r != null) _setOrdinary('weekday', r);
                  },
                ),
                const SizedBox(height: 10),
                _OrdinaryCard(
                  label: 'Sábado',
                  range: draft.saturdayOrdinary,
                  onEdit: () async {
                    final r = await _editRange(draft.saturdayOrdinary,
                        title: 'Jornada sábado');
                    if (r != null) _setOrdinary('saturday', r);
                  },
                ),
                const SizedBox(height: 10),
                _OrdinaryCard(
                  label: 'Domingo y festivo',
                  range: draft.sundayOrdinary,
                  helper:
                      'Cuenta como dominical diurna ordinaria (con recargo).',
                  onEdit: () async {
                    final r = await _editRange(draft.sundayOrdinary,
                        title: 'Jornada dominical');
                    if (r != null) _setOrdinary('sunday', r);
                  },
                ),
                const SizedBox(height: 24),
                _SectionLabel('Hora de almuerzo'),
                const SizedBox(height: 8),
                _LunchCard(
                  label: 'Lunes a viernes',
                  range: draft.weekdayLunch,
                  onToggle: (on) => _setLunch(
                    'weekday',
                    on ? const TimeRange(12, 0, 13, 0) : null,
                  ),
                  onEdit: () async {
                    final current = draft.weekdayLunch ??
                        const TimeRange(12, 0, 13, 0);
                    final r =
                        await _editRange(current, title: 'Almuerzo L–V');
                    if (r != null) _setLunch('weekday', r);
                  },
                ),
                const SizedBox(height: 10),
                _LunchCard(
                  label: 'Sábado',
                  range: draft.saturdayLunch,
                  onToggle: (on) => _setLunch(
                    'saturday',
                    on ? const TimeRange(12, 0, 13, 0) : null,
                  ),
                  onEdit: () async {
                    final current = draft.saturdayLunch ??
                        const TimeRange(12, 0, 13, 0);
                    final r =
                        await _editRange(current, title: 'Almuerzo sábado');
                    if (r != null) _setLunch('saturday', r);
                  },
                ),
                const SizedBox(height: 10),
                _LunchCard(
                  label: 'Domingo y festivo',
                  range: draft.sundayLunch,
                  onToggle: (on) => _setLunch(
                    'sunday',
                    on ? const TimeRange(12, 0, 13, 0) : null,
                  ),
                  onEdit: () async {
                    final current = draft.sundayLunch ??
                        const TimeRange(12, 0, 13, 0);
                    final r = await _editRange(current,
                        title: 'Almuerzo dominical');
                    if (r != null) _setLunch('sunday', r);
                  },
                ),
                const SizedBox(height: 24),
                _SectionLabel('Franjas diurna y nocturna'),
                const SizedBox(height: 8),
                _DayPeriodCard(
                  start: draft.dayStart,
                  end: draft.dayEnd,
                  onEditStart: () async {
                    final t = await _editTime(draft.dayStart,
                        title: 'Inicio franja diurna');
                    if (t != null) {
                      setState(() => _draft = _copyWith(dayStart: t));
                    }
                  },
                  onEditEnd: () async {
                    final t = await _editTime(draft.dayEnd,
                        title: 'Inicio franja nocturna');
                    if (t != null) {
                      setState(() => _draft = _copyWith(dayEnd: t));
                    }
                  },
                ),
                const SizedBox(height: 24),
                _SectionLabel('Resumen aplicado'),
                const SizedBox(height: 8),
                _PreviewCard(schedule: draft),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: (_busy || !_dirty) ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.4),
                        )
                      : Text(_dirty ? 'Guardar cambios' : 'Sin cambios'),
                ),
                const SizedBox(height: 8),
                if (_dirty)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _draft = _initial),
                    child: const Text('Descartar cambios'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
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
              'Los cambios aplican a partir del próximo registro o cierre. '
              'Los registros ya cerrados conservan el desglose calculado con '
              'la configuración vigente al momento del cierre.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdinaryCard extends StatelessWidget {
  const _OrdinaryCard({
    required this.label,
    required this.range,
    required this.onEdit,
    this.helper,
  });

  final String label;
  final TimeRange range;
  final VoidCallback onEdit;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: theme.textTheme.titleMedium),
                  ),
                  Icon(Icons.edit_outlined,
                      size: 18, color: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ChipTime(label: 'Entrada', minutes: range.startMinutes),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward,
                      size: 16,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  _ChipTime(label: 'Salida', minutes: range.endMinutes),
                ],
              ),
              if (helper != null) ...[
                const SizedBox(height: 8),
                Text(
                  helper!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LunchCard extends StatelessWidget {
  const _LunchCard({
    required this.label,
    required this.range,
    required this.onToggle,
    required this.onEdit,
  });

  final String label;
  final TimeRange? range;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = range != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
                Switch.adaptive(value: on, onChanged: onToggle),
              ],
            ),
            if (on) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      _ChipTime(label: 'Inicio', minutes: range!.startMinutes),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward,
                          size: 16,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5)),
                      const SizedBox(width: 8),
                      _ChipTime(label: 'Fin', minutes: range!.endMinutes),
                      const Spacer(),
                      Icon(Icons.edit_outlined,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Sin descuento de almuerzo este día.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayPeriodCard extends StatelessWidget {
  const _DayPeriodCard({
    required this.start,
    required this.end,
    required this.onEditStart,
    required this.onEditEnd,
  });

  final TimeOfDayMinutes start;
  final TimeOfDayMinutes end;
  final VoidCallback onEditStart;
  final VoidCallback onEditEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inicio franja diurna', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            InkWell(
              onTap: onEditStart,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    _ChipTime(label: 'Diurno desde', minutes: start.totalMinutes),
                    const Spacer(),
                    Icon(Icons.edit_outlined,
                        size: 18, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            Text('Inicio franja nocturna', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            InkWell(
              onTap: onEditEnd,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    _ChipTime(label: 'Nocturno desde', minutes: end.totalMinutes),
                    const Spacer(),
                    Icon(Icons.edit_outlined,
                        size: 18, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cualquier hora fuera de la jornada ordinaria se clasifica como '
              'extra diurna o nocturna según estos límites.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipTime extends StatelessWidget {
  const _ChipTime({required this.label, required this.minutes});
  final String label;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final tod = TimeOfDay(hour: hour, minute: minute);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          Text(
            formatTimeOfDay(tod),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.schedule});
  final WorkSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordWeek = _hoursOf(schedule.weekdayOrdinary, schedule.weekdayLunch);
    final ordSat = _hoursOf(schedule.saturdayOrdinary, schedule.saturdayLunch);
    final ordSun = _hoursOf(schedule.sundayOrdinary, schedule.sundayLunch);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(theme, 'Jornada efectiva L–V', '$ordWeek h'),
            _row(theme, 'Jornada efectiva sábado', '$ordSat h'),
            _row(theme, 'Jornada efectiva dom/festivo', '$ordSun h'),
            const Divider(height: 20),
            _row(theme, 'Diurno', _range(schedule.dayStart, schedule.dayEnd)),
            _row(theme, 'Nocturno',
                _range(schedule.dayEnd, schedule.dayStart, wrap: true)),
          ],
        ),
      ),
    );
  }

  String _range(TimeOfDayMinutes a, TimeOfDayMinutes b, {bool wrap = false}) {
    final aTod = TimeOfDay(hour: a.hour, minute: a.minute);
    final bTod = TimeOfDay(hour: b.hour, minute: b.minute);
    final extra = wrap ? ' del día siguiente' : '';
    return '${formatTimeOfDay(aTod)} → ${formatTimeOfDay(bTod)}$extra';
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  num _hoursOf(TimeRange ord, TimeRange? lunch) {
    final total = ord.endMinutes - ord.startMinutes;
    final lunchMin =
        lunch == null ? 0 : (lunch.endMinutes - lunch.startMinutes);
    return ((total - lunchMin) / 60).abs();
  }
}
