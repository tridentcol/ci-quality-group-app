import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/time_picker.dart';
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
  bool _initialized = false;
  bool _busy = false;
  String? _formError;
  HoursEntry? _editing;

  bool get _isEdit => widget.entryId != null;

  Future<void> _loadEditing() async {
    if (_initialized) return;
    _initialized = true;
    if (!_isEdit) return;

    setState(() => _busy = true);
    try {
      final entry =
          await ref.read(hoursRepositoryProvider).getEntry(widget.entryId!);
      if (entry == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registro no encontrado.')),
          );
          context.pop();
        }
        return;
      }
      final workers =
          ref.read(allWorkersProvider).valueOrNull ?? const <Worker>[];
      final worker = workers.firstWhere(
        (w) => w.id == entry.workerId,
        orElse: () => Worker(
          id: entry.workerId,
          fullName: entry.workerName,
          idNumber: '',
          role: '',
          active: false,
        ),
      );
      setState(() {
        _editing = entry;
        _worker = worker;
        _date = entry.workDate;
        _checkIn = TimeOfDay(hour: entry.checkIn.hour, minute: entry.checkIn.minute);
        if (entry.checkOut != null) {
          _checkOut = TimeOfDay(
            hour: entry.checkOut!.hour,
            minute: entry.checkOut!.minute,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 1)),
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
      setState(() => _formError = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_editing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: const Text(
          'Esto borra el registro permanentemente. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(hoursRepositoryProvider).deleteEntry(_editing!.id);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEditing());

    final theme = Theme.of(context);
    final workers = ref.watch(allWorkersProvider);
    final schedule =
        ref.watch(workScheduleProvider).valueOrNull ?? const WorkSchedule();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar registro' : 'Nuevo registro manual'),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: workers.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (workersList) {
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _SectionLabel('Trabajador'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Worker>(
                    value: _worker,
                    decoration: const InputDecoration(
                      labelText: 'Selecciona un trabajador',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: workersList
                        .map((w) => DropdownMenuItem(
                              value: w,
                              child: Text(
                                '${w.fullName}${w.active ? '' : ' (inactivo)'}',
                              ),
                            ))
                        .toList(),
                    onChanged: _isEdit
                        ? null
                        : (w) => setState(() => _worker = w),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel('Fecha y horas'),
                  const SizedBox(height: 8),
                  _TappableField(
                    label: 'Fecha',
                    value: formatDate(_date),
                    icon: Icons.calendar_today_outlined,
                    onTap: _isEdit ? null : _pickDate,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _TappableField(
                          label: 'Entrada',
                          value: _checkIn.format(context),
                          icon: Icons.login_outlined,
                          onTap: () => _pickTime(checkIn: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TappableField(
                          label: 'Salida',
                          value: _checkOut.format(context),
                          icon: Icons.logout_outlined,
                          onTap: () => _pickTime(checkIn: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel('Vista previa del desglose'),
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        _formError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.4),
                          )
                        : Text(_isEdit
                            ? 'Guardar cambios'
                            : 'Crear registro cerrado'),
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

class _TappableField extends StatelessWidget {
  const _TappableField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: onTap == null
              ? null
              : const Icon(Icons.chevron_right),
        ),
        child: Text(value),
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
