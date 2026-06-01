import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/time_picker.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../admin/presentation/admin_shell.dart';
import '../../auth/data/auth_repository.dart';
import '../data/cash_shift_repository.dart';
import '../domain/cash_register.dart';
import '../domain/cash_register_config.dart';
import '../domain/cash_shift.dart';

/// Pantalla de cierre de caja. Una sola pantalla con un estado claro
/// (abierta / cerrada) y una acción primaria. El arqueo se hace en un
/// bottom sheet guiado: contar efectivo, confirmar transferencias, razón
/// solo si algo no cuadra, retiro opcional.
///
/// La ventana del dinero es contigua (`periodStart` = cierre anterior), así
/// que nada se pierde aunque se cierre temprano o tarde. La "hora de cierre"
/// es solo un recordatorio configurable por admin.
class CashCloseScreen extends ConsumerStatefulWidget {
  const CashCloseScreen({super.key});

  @override
  ConsumerState<CashCloseScreen> createState() => _CashCloseScreenState();
}

class _CashCloseScreenState extends ConsumerState<CashCloseScreen> {
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-pinta el "esperado en vivo" y el recordatorio de hora cada 30 s.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _onOpen(CashRegister register) async {
    final suggestedBase = register.lastRemainingCash ?? 0;
    final result = await showModalBottomSheet<_OpenChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _OpenSheet(suggestedBase: suggestedBase),
    );
    if (result == null || !mounted) return;
    final actor = ref.read(currentProfileProvider).valueOrNull;
    if (actor == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(cashShiftRepositoryProvider).openShift(
            actor: actor,
            openingFloat: result.base,
            note: result.note,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja abierta.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la caja: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onClose(CashRegister register) async {
    final repo = ref.read(cashShiftRepositoryProvider);
    // Snapshot del esperado al abrir el sheet — el arqueo se valida contra
    // este número; el servidor recalcula al confirmar (red de seguridad).
    final expectation = await repo.liveExpectation(register);
    if (!mounted) return;
    final result = await showModalBottomSheet<_CloseChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CloseSheet(
        expectation: expectation,
        defaultBusinessDate: CashShift.businessDateLabel(
          register.openedAt ?? AppClock.now(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final actor = ref.read(currentProfileProvider).valueOrNull;
    if (actor == null) return;
    setState(() => _busy = true);
    try {
      final closed = await repo.closeShift(
        actor: actor,
        countedCash: result.countedCash,
        confirmedTransfer: result.confirmedTransfer,
        cashReason: result.cashReason,
        transferReason: result.transferReason,
        withdrawalAmount: result.withdrawal,
        note: result.note,
        businessDate: result.businessDate,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            closed.balances
                ? 'Caja cerrada. Todo cuadra.'
                : 'Caja cerrada con diferencias registradas.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cerrar la caja: ${friendlyError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onEditClosingTime(CashRegisterConfig config) async {
    final parsed = config.parsed;
    final picked = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parsed.hour, minute: parsed.minute),
      helpText: 'Hora de cierre sugerida',
    );
    if (picked == null || !mounted) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    try {
      await ref
          .read(cashShiftRepositoryProvider)
          .saveConfig(CashRegisterConfig(closingTime: '$hh:$mm'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hora de cierre actualizada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final registerAsync = ref.watch(cashRegisterProvider);
    final configAsync = ref.watch(cashRegisterConfigProvider);
    final closedAsync = ref.watch(closedCashShiftsProvider);
    final isAdmin = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.role == AppRole.admin,
    ),);

    return Scaffold(
      drawer: adminDrawerOrNull(context, '/admin/settings/cierre'),
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const BackButton() : null,
        title: const Text('Cierre de caja'),
      ),
      body: registerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: ${friendlyError(e)}'),
          ),
        ),
        data: (register) {
          final config =
              configAsync.valueOrNull ?? const CashRegisterConfig.defaults();
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _StatusCard(register: register, config: config),
                const SizedBox(height: 16),
                if (register.isOpen)
                  _LiveExpectedCard(register: register)
                else
                  const SizedBox.shrink(),
                if (register.isOpen) const SizedBox(height: 16),
                _PrimaryAction(
                  register: register,
                  busy: _busy,
                  onOpen: () => _onOpen(register),
                  onClose: () => _onClose(register),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  _ClosingTimeCard(
                    config: config,
                    onEdit: () => _onEditClosingTime(config),
                  ),
                ],
                const SizedBox(height: 24),
                const _SectionLabel('Cierres recientes'),
                const SizedBox(height: 8),
                closedAsync.when(
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
                  data: (shifts) => shifts.isEmpty
                      ? const EmptyState(
                          icon: Icons.point_of_sale_outlined,
                          title: 'Sin cierres registrados',
                          message:
                              'Cada vez que cierres la caja, el resumen aparecerá aquí.',
                        )
                      : _ClosedList(shifts: shifts),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Tarjeta de estado: abierta (verde) o cerrada (neutra), con el detalle
/// relevante de un vistazo.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.register, required this.config});
  final CashRegister register;
  final CashRegisterConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = register.isOpen
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.6);
    final icon = register.isOpen
        ? Icons.lock_open_outlined
        : Icons.point_of_sale_outlined;
    final headline = register.isOpen ? 'Caja abierta' : 'Caja cerrada';
    final secondary = register.isOpen
        ? _openSecondary(register)
        : _closedSecondary(register);

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
        ],
      ),
    );
  }

  String _openSecondary(CashRegister r) {
    final parts = <String>[];
    if (r.openedAt != null) {
      parts.add('Abierta desde ${formatTime(r.openedAt!)}');
    }
    if (r.openedByName != null) parts.add('por ${r.openedByName}');
    final base = parts.join(' ');
    final floatLine = 'Base inicial: ${formatCop(r.openingFloat ?? 0)}.';
    return base.isEmpty ? floatLine : '$base.\n$floatLine';
  }

  String _closedSecondary(CashRegister r) {
    if (r.lastClosedAt == null) {
      return 'Abre la caja al iniciar el turno para registrar el dinero que '
          'entra y cuadrarlo al final.';
    }
    return 'Último cierre: ${formatDateTime(r.lastClosedAt!)}.\n'
        'Quedó en caja: ${formatCop(r.lastRemainingCash ?? 0)} '
        '(se sugiere como base al abrir).';
  }
}

/// Esperado en vivo mientras la caja está abierta. Lee de forma asíncrona
/// para no bloquear el primer render.
class _LiveExpectedCard extends ConsumerWidget {
  const _LiveExpectedCard({required this.register});
  final CashRegister register;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(cashShiftRepositoryProvider);
    return FutureBuilder<CashShiftExpectation>(
      future: repo.liveExpectation(register),
      builder: (context, snap) {
        final exp = snap.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.trending_up_outlined,
                        size: 18, color: theme.colorScheme.primary,),
                    const SizedBox(width: 8),
                    Text(
                      'Esperado en este turno',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (exp == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  _amountRow(theme, 'Efectivo en caja', exp.expectedCash,
                      'Base + lo cobrado en efectivo.',),
                  const SizedBox(height: 8),
                  _amountRow(theme, 'Transferencias', exp.expectedTransfer,
                      'Lo recibido por transferencia.',),
                  if (exp.preOpenReceived > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Incluye ${formatCop(exp.preOpenReceived)} recibidos '
                      'antes de abrir la caja.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _amountRow(ThemeData theme, String label, num value, String help) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Text(
              formatCop(value),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Text(
          help,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.register,
    required this.busy,
    required this.onOpen,
    required this.onClose,
  });

  final CashRegister register;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (register.isOpen) {
      return FilledButton.icon(
        onPressed: busy ? null : onClose,
        icon: const Icon(Icons.lock_outline),
        label: const Text('Cerrar caja'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: busy ? null : onOpen,
      icon: const Icon(Icons.lock_open_outlined),
      label: const Text('Abrir caja'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
      ),
    );
  }
}

class _ClosingTimeCard extends StatelessWidget {
  const _ClosingTimeCard({required this.config, required this.onEdit});
  final CashRegisterConfig config;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = config.parsed;
    final tod = TimeOfDay(hour: p.hour, minute: p.minute);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.schedule_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hora de cierre sugerida',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Solo un recordatorio: a las ${formatTimeOfDay(tod)} la '
                      'app sugiere hacer el cierre. No cierra sola.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatTimeOfDay(tod),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined,
                  size: 18, color: theme.colorScheme.primary,),
            ],
          ),
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

class _ClosedList extends StatelessWidget {
  const _ClosedList({required this.shifts});
  final List<CashShift> shifts;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < shifts.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _ClosedTile(shift: shifts[i]),
          ],
        ],
      ),
    );
  }
}

class _ClosedTile extends StatelessWidget {
  const _ClosedTile({required this.shift});
  final CashShift shift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final balances = shift.balances;
    final accent = balances ? const Color(0xFF2E7D32) : scheme.error;
    final closedAt = shift.closedAt;
    final subtitleParts = <String>[
      if (closedAt != null) 'Cerrada ${formatDateTime(closedAt)}',
      if (shift.closedByName != null) shift.closedByName!,
    ];
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: accent.withValues(alpha: 0.15),
        child: Icon(
          balances ? Icons.check_circle_outline : Icons.error_outline,
          color: accent,
          size: 18,
        ),
      ),
      title: Text(
        shift.businessDate,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitleParts.join(' · '), style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              'Efectivo ${formatCop(shift.countedCash ?? 0)} · '
              'Transfer. ${formatCop(shift.confirmedTransfer ?? 0)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (!balances) ...[
              const SizedBox(height: 2),
              Text(
                _discrepancyLabel(shift),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      isThreeLine: !balances,
    );
  }

  String _discrepancyLabel(CashShift s) {
    final parts = <String>[];
    final cash = s.cashDiscrepancy ?? 0;
    final transfer = s.transferDiscrepancy ?? 0;
    if (cash != 0) {
      parts.add(
        'Efectivo ${cash > 0 ? "sobra" : "falta"} ${formatCop(cash.abs())}',
      );
    }
    if (transfer != 0) {
      parts.add(
        'Transfer. ${transfer > 0 ? "sobra" : "falta"} '
        '${formatCop(transfer.abs())}',
      );
    }
    return parts.join(' · ');
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet: abrir caja
// ---------------------------------------------------------------------------

class _OpenChoice {
  const _OpenChoice({required this.base, this.note});
  final num base;
  final String? note;
}

class _OpenSheet extends StatefulWidget {
  const _OpenSheet({required this.suggestedBase});
  final num suggestedBase;

  @override
  State<_OpenSheet> createState() => _OpenSheetState();
}

class _OpenSheetState extends State<_OpenSheet> {
  late final TextEditingController _baseCtrl;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _baseCtrl = TextEditingController(
      text: widget.suggestedBase > 0 ? '${widget.suggestedBase}' : '',
    );
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final base = num.tryParse(_baseCtrl.text.trim()) ?? 0;
    final note = _noteCtrl.text.trim();
    Navigator.pop(
      context,
      _OpenChoice(base: base, note: note.isEmpty ? null : note),
    );
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
                'Abrir caja',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Confirma el efectivo con el que arranca el turno. Suele ser '
                'lo que quedó en caja del cierre anterior.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              _MoneyField(
                controller: _baseCtrl,
                label: 'Base inicial en efectivo',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteCtrl,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Ej: arranca turno mañana.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
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
                      label: const Text('Abrir'),
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

// ---------------------------------------------------------------------------
// Bottom sheet: cerrar caja (arqueo guiado)
// ---------------------------------------------------------------------------

class _CloseChoice {
  const _CloseChoice({
    required this.countedCash,
    required this.confirmedTransfer,
    this.cashReason,
    this.transferReason,
    this.withdrawal,
    this.note,
    this.businessDate,
  });
  final num countedCash;
  final num confirmedTransfer;
  final String? cashReason;
  final String? transferReason;
  final num? withdrawal;
  final String? note;
  final String? businessDate;
}

class _CloseSheet extends StatefulWidget {
  const _CloseSheet({
    required this.expectation,
    required this.defaultBusinessDate,
  });
  final CashShiftExpectation expectation;
  final String defaultBusinessDate;

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
  final _cashCtrl = TextEditingController();
  final _transferCtrl = TextEditingController();
  final _cashReasonCtrl = TextEditingController();
  final _transferReasonCtrl = TextEditingController();
  final _withdrawalCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Precargamos la transferencia con lo esperado: casi siempre el cajero
    // confirma el mismo número (las transferencias ya quedaron registradas).
    _transferCtrl.text = widget.expectation.expectedTransfer > 0
        ? '${widget.expectation.expectedTransfer}'
        : '';
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    _cashReasonCtrl.dispose();
    _transferReasonCtrl.dispose();
    _withdrawalCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  num get _countedCash => num.tryParse(_cashCtrl.text.trim()) ?? 0;
  num get _confirmedTransfer => num.tryParse(_transferCtrl.text.trim()) ?? 0;
  num get _withdrawal => num.tryParse(_withdrawalCtrl.text.trim()) ?? 0;

  num get _cashDiscrepancy => _countedCash - widget.expectation.expectedCash;
  num get _transferDiscrepancy =>
      _confirmedTransfer - widget.expectation.expectedTransfer;

  bool get _cashFilled => _cashCtrl.text.trim().isNotEmpty;

  void _submit() {
    final cashReason = _cashReasonCtrl.text.trim();
    final transferReason = _transferReasonCtrl.text.trim();
    if (!_cashFilled) {
      setState(() => _error = 'Cuenta el efectivo antes de cerrar.');
      return;
    }
    if (_cashDiscrepancy != 0 && cashReason.isEmpty) {
      setState(() => _error = 'El efectivo no cuadra: indica una razón.');
      return;
    }
    if (_transferDiscrepancy != 0 && transferReason.isEmpty) {
      setState(() =>
          _error = 'Las transferencias no cuadran: indica una razón.',);
      return;
    }
    if (_withdrawal > _countedCash) {
      setState(() =>
          _error = 'El retiro no puede ser mayor al efectivo contado.',);
      return;
    }
    Navigator.pop(
      context,
      _CloseChoice(
        countedCash: _countedCash,
        confirmedTransfer: _confirmedTransfer,
        cashReason: cashReason.isEmpty ? null : cashReason,
        transferReason: transferReason.isEmpty ? null : transferReason,
        withdrawal: _withdrawal > 0 ? _withdrawal : null,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        businessDate: widget.defaultBusinessDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exp = widget.expectation;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final remaining = _countedCash - _withdrawal;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cerrar caja',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Cuenta lo que hay en caja y confirma las transferencias. '
                'Si algo no cuadra, anota por qué.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 20),
              _ArqueoBlock(
                title: 'Efectivo',
                expectedLabel: 'En el sistema: ${formatCop(exp.expectedCash)}',
                controller: _cashCtrl,
                fieldLabel: 'Efectivo contado',
                onChanged: () => setState(() => _error = null),
                discrepancy: _cashFilled ? _cashDiscrepancy : null,
                reasonController: _cashReasonCtrl,
              ),
              const SizedBox(height: 20),
              _ArqueoBlock(
                title: 'Transferencias',
                expectedLabel:
                    'En el sistema: ${formatCop(exp.expectedTransfer)}',
                controller: _transferCtrl,
                fieldLabel: 'Transferencias confirmadas',
                onChanged: () => setState(() => _error = null),
                discrepancy: _transferDiscrepancy,
                reasonController: _transferReasonCtrl,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              _MoneyField(
                controller: _withdrawalCtrl,
                label: 'Retiro o consignación (opcional)',
                onChanged: () => setState(() => _error = null),
              ),
              if (_withdrawal > 0 && _withdrawal <= _countedCash) ...[
                const SizedBox(height: 8),
                Text(
                  'Queda en caja: ${formatCop(remaining)} '
                  '(base sugerida del próximo turno).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _noteCtrl,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: theme.colorScheme.error,),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Confirmar cierre'),
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

/// Bloque de arqueo por método: esperado + campo de conteo + chip en vivo
/// (cuadra / sobra / falta) + razón que aparece solo si hay diferencia.
class _ArqueoBlock extends StatelessWidget {
  const _ArqueoBlock({
    required this.title,
    required this.expectedLabel,
    required this.controller,
    required this.fieldLabel,
    required this.onChanged,
    required this.discrepancy,
    required this.reasonController,
  });

  final String title;
  final String expectedLabel;
  final TextEditingController controller;
  final String fieldLabel;
  final VoidCallback onChanged;

  /// `null` = todavía no se ingresó el conteo (no mostrar chip).
  final num? discrepancy;
  final TextEditingController reasonController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showReason = discrepancy != null && discrepancy != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          expectedLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MoneyField(
                controller: controller,
                label: fieldLabel,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 10),
            _BalanceChip(discrepancy: discrepancy),
          ],
        ),
        if (showReason) ...[
          const SizedBox(height: 10),
          TextField(
            controller: reasonController,
            onChanged: (_) => onChanged(),
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Razón de la diferencia',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.discrepancy});

  /// `null` = sin conteo todavía.
  final num? discrepancy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (discrepancy == null) {
      return const SizedBox(width: 84);
    }
    final d = discrepancy!;
    final (Color color, String label, IconData icon) = d == 0
        ? (const Color(0xFF2E7D32), 'Cuadra', Icons.check_circle_outline)
        : d > 0
            ? (
                const Color(0xFFE6A100),
                'Sobra ${formatCop(d)}',
                Icons.arrow_upward,
              )
            : (
                theme.colorScheme.error,
                'Falta ${formatCop(d.abs())}',
                Icons.arrow_downward,
              );
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo numérico de moneda — solo dígitos, teclado numérico.
class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      decoration: InputDecoration(
        labelText: label,
        prefixText: r'$ ',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
