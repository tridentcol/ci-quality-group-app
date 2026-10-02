import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../workers/data/workers_repository.dart';
import '../data/work_shifts_repository.dart';
import '../domain/hours_categories.dart';
import '../domain/work_schedule.dart';
import '../domain/work_shift.dart';
import 'widgets/time_range_cards.dart';

/// Crea o edita un turno. Accesible para admin y para el encargado de
/// horas.
class ShiftFormScreen extends ConsumerStatefulWidget {
  const ShiftFormScreen({super.key, this.shiftId});

  /// `null` = turno nuevo.
  final String? shiftId;

  @override
  ConsumerState<ShiftFormScreen> createState() => _ShiftFormScreenState();
}

class _ShiftFormScreenState extends ConsumerState<ShiftFormScreen> {
  static const _defaultLunch = TimeRange(12, 0, 13, 0);

  final _nameCtrl = TextEditingController();
  TimeRange _weekday = const TimeRange(6, 0, 13, 0);
  TimeRange? _weekdayLunch;
  TimeRange? _saturday;
  TimeRange? _saturdayLunch;
  TimeRange? _sunday;
  TimeRange? _sundayLunch;
  WorkShift? _editing;
  bool _loaded = false;
  bool _busy = false;
  String? _formError;

  bool get _isEdit => widget.shiftId != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _initFrom(WorkShift s) {
    if (_loaded) return;
    _loaded = true;
    _editing = s;
    _nameCtrl.text = s.name;
    _weekday = s.weekday;
    _weekdayLunch = s.weekdayLunch;
    _saturday = s.saturday;
    _saturdayLunch = s.saturdayLunch;
    _sunday = s.sunday;
    _sundayLunch = s.sundayLunch;
  }

  Future<void> _pick(
    TimeRange current,
    String title,
    ValueChanged<TimeRange> onPicked,
  ) async {
    final r = await pickTimeRange(context, current, title: title);
    if (r != null) setState(() => onPicked(r));
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return 'Escribe un nombre para el turno.';

    String? check(String day, TimeRange range, TimeRange? lunch) {
      if (range.endMinutes <= range.startMinutes) {
        return '$day: la salida debe ser posterior a la entrada. Los turnos '
            'que cruzan la medianoche no están soportados.';
      }
      if (lunch == null) return null;
      if (lunch.endMinutes <= lunch.startMinutes) {
        return '$day: el almuerzo debe terminar después de empezar.';
      }
      if (lunch.startMinutes < range.startMinutes ||
          lunch.endMinutes > range.endMinutes) {
        return '$day: el almuerzo debe quedar dentro del horario del turno.';
      }
      return null;
    }

    return check('Lunes a viernes', _weekday, _weekdayLunch) ??
        (_saturday == null
            ? null
            : check('Sábado', _saturday!, _saturdayLunch)) ??
        (_sunday == null
            ? null
            : check('Domingo y festivo', _sunday!, _sundayLunch));
  }

  Future<void> _submit() async {
    final error = _validate();
    setState(() => _formError = error);
    if (error != null) return;

    setState(() => _busy = true);
    try {
      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) throw StateError('Sesión inválida.');
      await ref.read(workShiftsRepositoryProvider).save(
            WorkShift(
              id: widget.shiftId ?? '',
              name: _nameCtrl.text.trim(),
              weekday: _weekday,
              weekdayLunch: _weekdayLunch,
              saturday: _saturday,
              saturdayLunch: _saturday == null ? null : _saturdayLunch,
              sunday: _sunday,
              sundayLunch: _sunday == null ? null : _sundayLunch,
              active: _editing?.active ?? true,
            ),
            updatedBy: profile.uid,
            updatedByName: profile.fullName,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Turno actualizado.' : 'Turno creado.'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) setState(() => _formError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive() async {
    final shift = _editing;
    if (shift == null) return;
    final deactivating = shift.active;
    final assigned = (ref.read(activeWorkersProvider).valueOrNull ?? const [])
        .where((w) => w.shiftId == shift.id)
        .map((w) => w.id)
        .toList();
    final ok = await showConfirmDialog(
      context,
      title: deactivating ? 'Desactivar turno' : 'Reactivar turno',
      message: deactivating
          ? 'El turno deja de estar disponible y sus ${assigned.length} '
              'trabajador(es) vuelven a la jornada general. Los registros ya '
              'calculados con este turno no cambian.'
          : 'El turno vuelve a estar disponible para asignar trabajadores.',
      confirmLabel: deactivating ? 'Desactivar' : 'Reactivar',
      destructive: deactivating,
      icon: deactivating ? Icons.block_outlined : Icons.restore_outlined,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) throw StateError('Sesión inválida.');
      if (deactivating && assigned.isNotEmpty) {
        await ref.read(workersRepositoryProvider).setShift(assigned, null);
      }
      await ref.read(workShiftsRepositoryProvider).setActive(
            shift.id,
            active: !deactivating,
            updatedBy: profile.uid,
            updatedByName: profile.fullName,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _formError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final shiftsAsync = ref.watch(workShiftsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar turno' : 'Nuevo turno'),
        actions: const [ThemeModeIconButton()],
      ),
      body: shiftsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(error: e),
        data: (shifts) {
          if (_isEdit) {
            WorkShift? found;
            for (final s in shifts) {
              if (s.id == widget.shiftId) found = s;
            }
            if (found == null) {
              return const Center(child: Text('Este turno ya no existe.'));
            }
            _initFrom(found);
          }
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + keyboardInset),
              children: [
                const SectionLabel('Nombre'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del turno',
                    hintText: 'Ej. Turno mañana',
                    prefixIcon: Icon(Icons.badge_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel('Horario'),
                const SizedBox(height: 8),
                OrdinaryRangeCard(
                  label: 'Lunes a viernes',
                  range: _weekday,
                  helper: 'Lo que se trabaje fuera de este horario cuenta '
                      'como hora extra.',
                  onEdit: () =>
                      _pick(_weekday, 'Turno L–V', (r) => _weekday = r),
                ),
                const SizedBox(height: 10),
                LunchRangeCard(
                  label: 'Almuerzo',
                  range: _weekdayLunch,
                  onToggle: (on) => setState(
                    () => _weekdayLunch = on ? _defaultLunch : null,
                  ),
                  onEdit: () => _pick(
                    _weekdayLunch ?? _defaultLunch,
                    'Almuerzo L–V',
                    (r) => _weekdayLunch = r,
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel('Sábado'),
                const SizedBox(height: 8),
                _OwnScheduleSwitch(
                  title: 'Horario distinto el sábado',
                  subtitle: 'Si está apagado, el sábado usa el mismo horario '
                      'de lunes a viernes.',
                  value: _saturday != null,
                  onChanged: (on) => setState(() {
                    _saturday = on ? _weekday : null;
                    _saturdayLunch = null;
                  }),
                ),
                if (_saturday != null) ...[
                  const SizedBox(height: 10),
                  OrdinaryRangeCard(
                    label: 'Sábado',
                    range: _saturday!,
                    onEdit: () => _pick(
                      _saturday!,
                      'Turno sábado',
                      (r) => _saturday = r,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LunchRangeCard(
                    label: 'Almuerzo del sábado',
                    range: _saturdayLunch,
                    onToggle: (on) => setState(
                      () => _saturdayLunch = on ? _defaultLunch : null,
                    ),
                    onEdit: () => _pick(
                      _saturdayLunch ?? _defaultLunch,
                      'Almuerzo sábado',
                      (r) => _saturdayLunch = r,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const SectionLabel('Domingo y festivo'),
                const SizedBox(height: 8),
                _OwnScheduleSwitch(
                  title: 'Horario distinto en domingo y festivo',
                  subtitle: 'Si está apagado, usa el mismo horario de lunes a '
                      'viernes. En ambos casos se paga con recargo dominical.',
                  value: _sunday != null,
                  onChanged: (on) => setState(() {
                    _sunday = on ? _weekday : null;
                    _sundayLunch = null;
                  }),
                ),
                if (_sunday != null) ...[
                  const SizedBox(height: 10),
                  OrdinaryRangeCard(
                    label: 'Domingo y festivo',
                    range: _sunday!,
                    onEdit: () => _pick(
                      _sunday!,
                      'Turno dominical',
                      (r) => _sunday = r,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LunchRangeCard(
                    label: 'Almuerzo dominical',
                    range: _sundayLunch,
                    onToggle: (on) => setState(
                      () => _sundayLunch = on ? _defaultLunch : null,
                    ),
                    onEdit: () => _pick(
                      _sundayLunch ?? _defaultLunch,
                      'Almuerzo dominical',
                      (r) => _sundayLunch = r,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _SummaryCard(
                  weekday: effectiveShiftDuration(_weekday, _weekdayLunch),
                  saturday: _saturday == null
                      ? null
                      : effectiveShiftDuration(_saturday!, _saturdayLunch),
                  sunday: _sunday == null
                      ? null
                      : effectiveShiftDuration(_sunday!, _sundayLunch),
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Los cambios aplican a los registros que se abran o se '
                    'editen de ahora en adelante. Los días ya cerrados '
                    'conservan su desglose.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 16),
                  FormErrorBanner(message: _formError!),
                ],
                const SizedBox(height: 24),
                LoadingButton(
                  onPressed: _submit,
                  loading: _busy,
                  label: _isEdit ? 'Guardar cambios' : 'Crear turno',
                ),
                if (_editing != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleActive,
                    icon: Icon(
                      _editing!.active
                          ? Icons.block_outlined
                          : Icons.restore_outlined,
                    ),
                    label: Text(
                      _editing!.active ? 'Desactivar turno' : 'Reactivar turno',
                    ),
                    style: _editing!.active
                        ? OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                          )
                        : null,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Horas efectivas de un rango, descontando el almuerzo.
Duration effectiveShiftDuration(TimeRange range, TimeRange? lunch) {
  final total = range.endMinutes - range.startMinutes;
  final lunchMinutes =
      lunch == null ? 0 : lunch.endMinutes - lunch.startMinutes;
  final minutes = total - lunchMinutes;
  return Duration(minutes: minutes < 0 ? 0 : minutes);
}

class _OwnScheduleSwitch extends StatelessWidget {
  const _OwnScheduleSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile.adaptive(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.weekday,
    required this.saturday,
    required this.sunday,
  });

  final Duration weekday;
  final Duration? saturday;
  final Duration? sunday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, Duration value) => Padding(
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
                formatHours(value),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row('Jornada efectiva L–V', weekday),
            row('Jornada efectiva sábado', saturday ?? weekday),
            row('Jornada efectiva dom/festivo', sunday ?? weekday),
          ],
        ),
      ),
    );
  }
}
