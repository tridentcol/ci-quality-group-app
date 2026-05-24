import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/data/auth_repository.dart';
import '../data/sales_delegation_repository.dart';
import '../domain/sales_delegation.dart';
import '../domain/sales_delegation_history_entry.dart';
import 'admin_shell.dart';

/// Pantalla del modo "delegación caja". Permite al admin activar/desactivar
/// la posibilidad de que Ventas registre el pago en el mismo submit de la
/// venta, eligiendo ventanas predefinidas o un rango personalizado
/// (incluyendo programación para días futuros).
class SalesDelegationScreen extends ConsumerStatefulWidget {
  const SalesDelegationScreen({super.key});

  @override
  ConsumerState<SalesDelegationScreen> createState() =>
      _SalesDelegationScreenState();
}

class _SalesDelegationScreenState extends ConsumerState<SalesDelegationScreen> {
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-pinta el countdown del banner cada 30 s sin tocar Firestore.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _onActivate(SalesDelegation current) async {
    final result = await showModalBottomSheet<_ActivationChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _ActivationSheet(),
    );
    if (result == null || !mounted) return;
    final actor =
        ref.read(currentProfileProvider).valueOrNull;
    if (actor == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(salesDelegationRepositoryProvider).activate(
            actor: actor,
            startsAt: result.startsAt,
            expiresAt: result.expiresAt,
            note: result.note,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_activatedSnackbar(result))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo activar: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _activatedSnackbar(_ActivationChoice c) {
    if (c.startsAt != null && c.startsAt!.isAfter(AppClock.now())) {
      return 'Delegación programada para ${formatDateTime(c.startsAt!)}.';
    }
    if (c.expiresAt == null) {
      return 'Delegación activada sin vencimiento.';
    }
    return 'Delegación activada hasta ${formatDateTime(c.expiresAt!)}.';
  }

  Future<void> _onDeactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar delegación'),
        content: const Text(
          'Ventas dejará de poder registrar pagos en sus solicitudes. '
          '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final actor = ref.read(currentProfileProvider).valueOrNull;
    if (actor == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(salesDelegationRepositoryProvider)
          .deactivate(actor: actor);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delegación desactivada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo desactivar: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delegationAsync = ref.watch(salesDelegationProvider);
    final historyAsync = ref.watch(salesDelegationHistoryProvider);

    return Scaffold(
      drawer: adminDrawerOrNull(context, '/admin/settings/delegation'),
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const BackButton() : null,
        title: const Text('Delegación caja'),
      ),
      body: delegationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: ${friendlyError(e)}'),
          ),
        ),
        data: (delegation) {
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _StatusCard(delegation: delegation),
                const SizedBox(height: 16),
                _ActionButtons(
                  delegation: delegation,
                  busy: _busy,
                  onActivate: () => _onActivate(delegation),
                  onDeactivate: _onDeactivate,
                ),
                const SizedBox(height: 24),
                _ContextCard(delegation: delegation),
                const SizedBox(height: 24),
                const _SectionLabel('Historial reciente'),
                const SizedBox(height: 8),
                historyAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No se pudo cargar el historial: ${friendlyError(e)}',
                    ),
                  ),
                  data: (entries) => entries.isEmpty
                      ? const EmptyState(
                          icon: Icons.history_outlined,
                          title: 'Sin activaciones registradas',
                          message:
                              'El historial empezará a llenarse al activar o desactivar la delegación.',
                        )
                      : _HistoryList(entries: entries),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.delegation});
  final SalesDelegation delegation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (String headline, String secondary, Color accent, IconData icon) =
        _summary(delegation, scheme);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 10),
              Text(
                headline,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: accent, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            secondary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
          if (delegation.note != null && delegation.note!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _NoteBlock(text: delegation.note!),
          ],
        ],
      ),
    );
  }

  (String, String, Color, IconData) _summary(
    SalesDelegation d,
    ColorScheme scheme,
  ) {
    if (d.isCurrentlyActive) {
      final until = d.expiresAt;
      final secondary = until == null
          ? 'Sin vencimiento configurado. Permanece activa hasta que la desactives manualmente.'
          : 'Vigente hasta ${formatDateTime(until)} · ${_remainingHuman(until)}.';
      return (
        'Activa',
        secondary,
        scheme.primary,
        Icons.lock_open_outlined,
      );
    }
    if (d.isScheduled) {
      return (
        'Programada',
        'Empieza ${formatDateTime(d.startsAt!)}'
            '${d.expiresAt != null ? " y termina ${formatDateTime(d.expiresAt!)}." : "."}',
        scheme.tertiary,
        Icons.schedule_outlined,
      );
    }
    if (d.hasExpired) {
      return (
        'Expirada',
        'El vencimiento programado (${formatDateTime(d.expiresAt!)}) ya pasó. '
            'Desactivá para limpiar el estado.',
        scheme.error,
        Icons.timer_off_outlined,
      );
    }
    return (
      'Inactiva',
      'Ventas no puede registrar pagos. Activá la delegación cuando admin o caja no estén disponibles.',
      scheme.onSurface.withValues(alpha: 0.7),
      Icons.lock_outline,
    );
  }

  String _remainingHuman(DateTime until) {
    final diff = until.difference(AppClock.now());
    if (diff.isNegative) return 'vencida';
    if (diff.inMinutes < 1) return 'menos de 1 min';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min restantes';
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    if (hours < 24) {
      return mins == 0
          ? '$hours h restantes'
          : '$hours h $mins min restantes';
    }
    final days = diff.inDays;
    final remainingHours = diff.inHours % 24;
    return remainingHours == 0
        ? '$days días restantes'
        : '$days d $remainingHours h restantes';
  }
}

class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.delegation,
    required this.busy,
    required this.onActivate,
    required this.onDeactivate,
  });

  final SalesDelegation delegation;
  final bool busy;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final isOn = delegation.active;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : onActivate,
            icon: const Icon(Icons.lock_open_outlined),
            label: Text(isOn ? 'Reemplazar' : 'Activar'),
          ),
        ),
        if (isOn) ...[
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onDeactivate,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Desactivar'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.delegation});
  final SalesDelegation delegation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    if (delegation.activatedAt != null) {
      rows.add(_row(
        theme,
        Icons.event_outlined,
        'Activada',
        '${formatDateTime(delegation.activatedAt!)}'
            '${delegation.activatedByName != null ? " · ${delegation.activatedByName}" : ""}',
      ),);
    }
    if (delegation.startsAt != null) {
      rows.add(_row(
        theme,
        Icons.schedule_outlined,
        'Inicio',
        formatDateTime(delegation.startsAt!),
      ),);
    }
    if (delegation.expiresAt != null) {
      rows.add(_row(
        theme,
        Icons.timer_outlined,
        'Vencimiento',
        formatDateTime(delegation.expiresAt!),
      ),);
    }
    if (delegation.deactivatedAt != null) {
      rows.add(_row(
        theme,
        Icons.lock_outline,
        'Desactivada',
        '${formatDateTime(delegation.deactivatedAt!)}'
            '${delegation.deactivatedByName != null ? " · ${delegation.deactivatedByName}" : ""}',
      ),);
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in rows) ...[
              r,
              if (r != rows.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
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

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.entries});
  final List<SalesDelegationHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _HistoryTile(entry: entries[i], theme: theme),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.theme});
  final SalesDelegationHistoryEntry entry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final isActivation = entry.action == SalesDelegationAction.activated;
    final accent = isActivation ? scheme.primary : scheme.onSurface;
    final icon = isActivation
        ? Icons.lock_open_outlined
        : Icons.lock_outline;
    final title = isActivation ? 'Activada' : 'Desactivada';
    final subtitleParts = <String>[
      formatDateTime(entry.at),
      entry.actorName,
    ];
    if (isActivation && entry.startsAt != null) {
      subtitleParts.add('Inicio ${formatDateTime(entry.startsAt!)}');
    }
    if (isActivation && entry.expiresAt != null) {
      subtitleParts.add('Hasta ${formatDateTime(entry.expiresAt!)}');
    }
    if (isActivation && entry.expiresAt == null && entry.startsAt == null) {
      subtitleParts.add('Sin vencimiento');
    }
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: accent.withValues(alpha: 0.15),
        child: Icon(icon, color: accent, size: 18),
      ),
      title: Text(title,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitleParts.join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (entry.note != null && entry.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '“${entry.note!}”',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
      isThreeLine: entry.note != null && entry.note!.isNotEmpty,
    );
  }
}

/// Resultado del bottom sheet de activación. `null` startsAt = vigente
/// ahora; `null` expiresAt = sin vencimiento.
class _ActivationChoice {
  const _ActivationChoice({this.startsAt, this.expiresAt, this.note});
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final String? note;
}

class _ActivationSheet extends StatefulWidget {
  const _ActivationSheet();
  @override
  State<_ActivationSheet> createState() => _ActivationSheetState();
}

enum _PresetId { twoHours, today18, noExpiry, custom }

class _ActivationSheetState extends State<_ActivationSheet> {
  _PresetId? _preset;
  final _noteCtrl = TextEditingController();

  // Solo relevante cuando _preset == custom. Defaults sensatos cargados
  // al elegir "Personalizado" por primera vez.
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _validationError;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _todayPresetVisible {
    final now = AppClock.now();
    final eod = DateTime(now.year, now.month, now.day, 18);
    return eod.isAfter(now);
  }

  Future<void> _pickCustomStart() async {
    final picked = await _pickDateTime(
      initial: _customStart ?? AppClock.now().add(const Duration(hours: 1)),
      helpDate: 'Inicio · día',
      helpTime: 'Inicio · hora',
    );
    if (picked != null) {
      setState(() {
        _customStart = picked;
        _validationError = null;
        if (_customEnd != null && !_customEnd!.isAfter(picked)) {
          _customEnd = picked.add(const Duration(hours: 2));
        }
      });
    }
  }

  Future<void> _pickCustomEnd() async {
    final base = _customStart ?? AppClock.now();
    final picked = await _pickDateTime(
      initial: _customEnd ?? base.add(const Duration(hours: 2)),
      helpDate: 'Fin · día',
      helpTime: 'Fin · hora',
    );
    if (picked != null) {
      setState(() {
        _customEnd = picked;
        _validationError = null;
      });
    }
  }

  Future<DateTime?> _pickDateTime({
    required DateTime initial,
    required String helpDate,
    required String helpTime,
  }) async {
    final now = AppClock.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
      helpText: helpDate,
    );
    if (date == null) return null;
    if (!mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: helpTime,
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  _ActivationChoice? _buildChoice() {
    final now = AppClock.now();
    final note = _noteCtrl.text.trim();
    String? note0() => note.isEmpty ? null : note;

    switch (_preset) {
      case _PresetId.twoHours:
        return _ActivationChoice(
          expiresAt: now.add(const Duration(hours: 2)),
          note: note0(),
        );
      case _PresetId.today18:
        final eod = DateTime(now.year, now.month, now.day, 18);
        if (!eod.isAfter(now)) {
          setState(() => _validationError =
              'Ya pasaron las 18:00 de hoy. Elegí otra opción.',);
          return null;
        }
        return _ActivationChoice(
          expiresAt: eod,
          note: note0(),
        );
      case _PresetId.noExpiry:
        return _ActivationChoice(note: note0());
      case _PresetId.custom:
        if (_customStart == null || _customEnd == null) {
          setState(() => _validationError =
              'Elegí inicio y fin para el rango personalizado.',);
          return null;
        }
        if (!_customEnd!.isAfter(_customStart!)) {
          setState(() =>
              _validationError = 'El fin debe ser posterior al inicio.',);
          return null;
        }
        if (!_customEnd!.isAfter(now)) {
          setState(() => _validationError =
              'El fin debe ser posterior al momento actual.',);
          return null;
        }
        if (_customEnd!.difference(_customStart!) >
            const Duration(days: 7)) {
          setState(() => _validationError =
              'Máximo 7 días por activación. Acortá el rango.',);
          return null;
        }
        final startsAt =
            _customStart!.isAfter(now) ? _customStart : null;
        return _ActivationChoice(
          startsAt: startsAt,
          expiresAt: _customEnd,
          note: note0(),
        );
      case null:
        setState(() =>
            _validationError = 'Elegí una duración antes de continuar.',);
        return null;
    }
  }

  void _submit() {
    final choice = _buildChoice();
    if (choice == null) return;
    Navigator.pop(context, choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Activar delegación caja',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Mientras esté vigente, Ventas podrá registrar el pago al crear una venta. Toda activación queda en el historial.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Duración',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PresetChip(
                    icon: Icons.timer_outlined,
                    label: 'Próximas 2 horas',
                    selected: _preset == _PresetId.twoHours,
                    onTap: () => setState(() {
                      _preset = _PresetId.twoHours;
                      _validationError = null;
                    }),
                  ),
                  if (_todayPresetVisible)
                    _PresetChip(
                      icon: Icons.today_outlined,
                      label: 'Hoy hasta 18:00',
                      selected: _preset == _PresetId.today18,
                      onTap: () => setState(() {
                        _preset = _PresetId.today18;
                        _validationError = null;
                      }),
                    ),
                  _PresetChip(
                    icon: Icons.all_inclusive_outlined,
                    label: 'Sin vencimiento',
                    selected: _preset == _PresetId.noExpiry,
                    onTap: () => setState(() {
                      _preset = _PresetId.noExpiry;
                      _validationError = null;
                    }),
                  ),
                  _PresetChip(
                    icon: Icons.event_outlined,
                    label: 'Personalizado',
                    selected: _preset == _PresetId.custom,
                    onTap: () => setState(() {
                      _preset = _PresetId.custom;
                      _validationError = null;
                    }),
                  ),
                ],
              ),
              if (_preset == _PresetId.custom) ...[
                const SizedBox(height: 16),
                _CustomRangeFields(
                  start: _customStart,
                  end: _customEnd,
                  onPickStart: _pickCustomStart,
                  onPickEnd: _pickCustomEnd,
                ),
                if (_customStart != null &&
                    _customStart!.isAfter(AppClock.now())) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule_outlined,
                          size: 16, color: theme.colorScheme.tertiary,),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Quedará programada — no estará vigente hasta el inicio.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 20),
              Text(
                'Nota (opcional)',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText:
                      'Ej: Reunión con cliente X · viaje del cajero · etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: theme.colorScheme.error,),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Activar'),
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

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.15)
        : scheme.surfaceContainerHighest;
    final fg = selected ? scheme.primary : scheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomRangeFields extends StatelessWidget {
  const _CustomRangeFields({
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _RangeField(
          label: 'Inicio',
          icon: Icons.play_circle_outline,
          value: start,
          placeholder: 'Elegí día y hora',
          onTap: onPickStart,
          theme: theme,
        ),
        const SizedBox(height: 10),
        _RangeField(
          label: 'Fin',
          icon: Icons.stop_circle_outlined,
          value: end,
          placeholder: 'Elegí día y hora',
          onTap: onPickEnd,
          theme: theme,
        ),
      ],
    );
  }
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.label,
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final IconData icon;
  final DateTime? value;
  final String placeholder;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value == null ? placeholder : formatDateTime(value!),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: value == null
                            ? scheme.onSurface.withValues(alpha: 0.55)
                            : scheme.onSurface,
                        fontWeight:
                            value == null ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined,
                  size: 18, color: scheme.onSurface.withValues(alpha: 0.55),),
            ],
          ),
        ),
      ),
    );
  }
}
