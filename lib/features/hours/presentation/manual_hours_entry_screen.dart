import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/time_picker.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../workers/data/workers_repository.dart';
import '../../workers/domain/worker.dart';
import '../data/hours_repository.dart';
import '../data/work_schedule_repository.dart';
import '../domain/hours_calculator.dart';
import '../domain/hours_categories.dart';
import '../domain/hours_entry.dart';
import '../domain/work_schedule.dart';
import 'widgets/breakdown_card.dart';

/// Pantalla del admin para crear o editar manualmente una entrada de horas
/// para cualquier fecha (típicamente días pasados u olvidados).
///
/// Combina entrada + salida + cierre en una sola operación. Para edición
/// se precarga con los datos existentes; al guardar, recalcula el desglose.
class ManualHoursEntryScreen extends ConsumerStatefulWidget {
  const ManualHoursEntryScreen({super.key, this.entryId});

  /// Si se pasa, la pantalla precarga el registro existente con ese id.
  /// El id sigue el patrón `<workerId>_<YYYYMMDD>`.
  final String? entryId;

  @override
  ConsumerState<ManualHoursEntryScreen> createState() =>
      _ManualHoursEntryScreenState();
}

class _ManualHoursEntryScreenState
    extends ConsumerState<ManualHoursEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  Worker? _worker;
  DateTime _date = AppClock.now();
  TimeOfDay _checkIn = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _checkOut = const TimeOfDay(hour: 16, minute: 0);
  bool _busy = false;
  String? _formError;
  HoursEntry? _editing;

  bool get _isEdit => widget.entryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      // Carga del registro al entrar. Esperamos a que `allWorkersProvider`
      // tenga datos para no fabricar un Worker placeholder que no esté en
      // la lista del dropdown (lo que rompía la assertion de
      // DropdownButtonFormField cuando el provider terminaba de cargar).
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEditing());
    }
  }

  Future<void> _loadEditing() async {
    if (!_isEdit || !mounted) return;
    setState(() => _busy = true);
    try {
      // Espera explícita a que allWorkersProvider entregue resultados.
      // `ref.read(...).future` resuelve con los workers ya cargados. Si
      // ya estaban en cache, vuelve sincrónico.
      final workers = await ref.read(allWorkersProvider.future);
      if (!mounted) return;

      final entry =
          await ref.read(hoursRepositoryProvider).getEntry(widget.entryId!);
      if (!mounted) return;
      if (entry == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro no encontrado.')),
        );
        context.pop();
        return;
      }

      Worker? worker;
      for (final w in workers) {
        if (w.id == entry.workerId) {
          worker = w;
          break;
        }
      }
      // Si el worker fue desactivado/borrado entre la creación del registro
      // y ahora, ya no aparece en `workers`. Aún así dejamos editar las
      // horas: agregamos un placeholder que coincide por `==` (igualdad
      // por id) con cualquier item homónimo y se suma al dropdown como
      // entrada inactiva.
      worker ??= Worker(
        id: entry.workerId,
        fullName: entry.workerName,
        idNumber: '',
        role: '',
        active: false,
      );

      setState(() {
        _editing = entry;
        _worker = worker;
        _date = entry.workDate;
        _checkIn =
            TimeOfDay(hour: entry.checkIn.hour, minute: entry.checkIn.minute);
        if (entry.checkOut != null) {
          _checkOut = TimeOfDay(
            hour: entry.checkOut!.hour,
            minute: entry.checkOut!.minute,
          );
        }
      });
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      // Permitimos fechas futuras hasta ~1 año adelante para que el admin
      // pueda registrar entradas anticipadas o usarlo como sandbox de
      // prueba sin restricción.
      lastDate: AppClock.now().add(const Duration(days: 365)),
      helpText: 'Fecha del registro',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool checkIn}) async {
    final initial = checkIn ? _checkIn : _checkOut;
    final picked = await showAppTimePicker(
      context: context,
      initialTime: initial,
      helpText: checkIn ? 'Hora de entrada' : 'Hora de salida',
    );
    if (picked != null) {
      setState(() {
        if (checkIn) {
          _checkIn = picked;
        } else {
          _checkOut = picked;
        }
      });
    }
  }

  ({String label, Color color})? _dateBadge(Brightness brightness) {
    final today = AppClock.now();
    final isDark = brightness == Brightness.dark;
    // En dark, los verdes corporativos quedan muy oscuros sobre fondo
    // grafito; subimos a leafGreen y a versiones más luminosas.
    if (isSameDay(_date, today)) {
      return (
        label: 'Hoy',
        color: isDark ? AppColors.leafGreen : AppColors.success,
      );
    }
    if (_date.isBefore(today)) {
      return (
        label: 'Pasado',
        color: isDark ? const Color(0xFF60A5FA) : AppColors.info,
      );
    }
    return (
      label: 'Futuro',
      color: isDark ? const Color(0xFFFFC857) : AppColors.warning,
    );
  }

  DateTime _composeCheckIn() => DateTime(
      _date.year, _date.month, _date.day, _checkIn.hour, _checkIn.minute);

  DateTime _composeCheckOut() {
    var dt = DateTime(
        _date.year, _date.month, _date.day, _checkOut.hour, _checkOut.minute);
    // Si la salida es anterior o igual a la entrada, se asume cruce de
    // medianoche y se corre al día siguiente.
    final inDt = _composeCheckIn();
    if (!dt.isAfter(inDt)) {
      dt = dt.add(const Duration(days: 1));
    }
    return dt;
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (_worker == null) {
      setState(() => _formError = 'Selecciona un trabajador.');
      return;
    }
    final inDt = _composeCheckIn();
    final outDt = _composeCheckOut();
    if (!outDt.isAfter(inDt)) {
      setState(() => _formError = 'La salida debe ser posterior a la entrada.');
      return;
    }

    setState(() => _busy = true);
    try {
      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) throw StateError('Sesión inválida.');
      final schedule =
          ref.read(workScheduleProvider).valueOrNull ?? const WorkSchedule();
      await ref.read(hoursRepositoryProvider).upsertManualEntry(
            workerId: _worker!.id,
            workerName: _worker!.fullName,
            date: _date,
            checkIn: inDt,
            checkOut: outDt,
            createdBy: profile.uid,
            createdByName: profile.fullName,
            schedule: schedule,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit
                ? 'Registro actualizado.'
                : 'Registro de horas creado.'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _formError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_editing == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Eliminar registro',
      message: 'Esto borra el registro permanentemente.',
      confirmLabel: 'Eliminar',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(hoursRepositoryProvider).deleteEntry(_editing!.id);
      if (mounted) context.pop();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final workers = ref.watch(allWorkersProvider);
    final schedule =
        ref.watch(workScheduleProvider).valueOrNull ?? const WorkSchedule();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar registro' : 'Nuevo registro manual'),
        actions: const [ThemeModeIconButton()],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: workers.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorView(error: e),
          data: (workersList) {
            // Si el worker que estamos editando no aparece en la lista
            // (fue desactivado / borrado), lo añadimos como entrada extra
            // para que el dropdown pueda mostrarlo como `value`. La
            // igualdad por id en `Worker.==` garantiza que el dropdown
            // lo reconozca aunque sean instancias distintas.
            final workersForDropdown = <Worker>[
              ...workersList,
              if (_worker != null && !workersList.contains(_worker)) _worker!,
            ];
            return Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + keyboardInset),
                children: [
                  const SectionLabel('Trabajador'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Worker>(
                    initialValue: _worker,
                    decoration: const InputDecoration(
                      labelText: 'Selecciona un trabajador',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: workersForDropdown
                        .map(
                          (w) => DropdownMenuItem(
                            value: w,
                            child: Text(
                              '${w.fullName}${w.active ? '' : ' (inactivo)'}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged:
                        _isEdit ? null : (w) => setState(() => _worker = w),
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('Fecha y horas'),
                  const SizedBox(height: 8),
                  _TappableField(
                    label: 'Fecha',
                    value: formatDate(_date),
                    badge: _dateBadge(Theme.of(context).brightness),
                    icon: Icons.calendar_today_outlined,
                    onTap: _isEdit ? null : _pickDate,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _TappableField(
                          label: 'Entrada',
                          value: formatTimeOfDay(_checkIn),
                          icon: Icons.login_outlined,
                          onTap: () => _pickTime(checkIn: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TappableField(
                          label: 'Salida',
                          value: formatTimeOfDay(_checkOut),
                          icon: Icons.logout_outlined,
                          onTap: () => _pickTime(checkIn: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('Vista previa del desglose'),
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final inDt = _composeCheckIn();
                    final outDt = _composeCheckOut();
                    if (!outDt.isAfter(inDt)) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'La salida debe ser posterior a la entrada.',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      );
                    }
                    final breakdown = HoursBreakdownPreview.calculate(
                      inDt: inDt,
                      outDt: outDt,
                      schedule: schedule,
                    );
                    return BreakdownCard(breakdown: breakdown);
                  }),
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    FormErrorBanner(message: _formError!),
                  ],
                  const SizedBox(height: 24),
                  LoadingButton(
                    onPressed: _submit,
                    loading: _busy,
                    label:
                        _isEdit ? 'Guardar cambios' : 'Crear registro cerrado',
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar registro'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TappableField extends StatelessWidget {
  const _TappableField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final ({String label, Color color})? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: onTap == null ? null : const Icon(Icons.chevron_right),
        ),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badge!.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: badge!.color.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  badge!.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: badge!.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Helper estático que ejecuta el motor de cálculo para mostrar la vista
/// previa del desglose dentro del formulario.
class HoursBreakdownPreview {
  HoursBreakdownPreview._();

  static HoursBreakdown calculate({
    required DateTime inDt,
    required DateTime outDt,
    required WorkSchedule schedule,
  }) {
    return HoursCalculator(schedule: schedule).calculate(inDt, outDt);
  }
}
