import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/payment.dart';
import '../../sales/domain/sale.dart';
import '../data/cashier_repository.dart';

/// Pantalla de pagos de una venta. Header con totales + plazo +
/// financialStatus, timeline cronológico de abonos, FAB para registrar
/// uno nuevo, y acción de "Marcar saldo como pérdida".
class SalePaymentsScreen extends ConsumerWidget {
  const SalePaymentsScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleAsync = ref.watch(saleByIdProvider(saleId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos'),
        actions: const [ThemeModeIconButton()],
      ),
      body: saleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(saleByIdProvider(saleId)),
        ),
        data: (sale) {
          if (sale == null) {
            return const Center(child: Text('Esta venta ya no existe.'));
          }
          return _Body(sale: sale);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(paymentsBySaleProvider(sale.id));
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isAdmin = profile?.role == AppRole.admin;
    final canRegister = sale.state != SaleState.cancelada;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canRegister && profile != null
          ? FloatingActionButton.extended(
              onPressed: () => _openRegisterPaymentSheet(context, ref, sale, profile),
              icon: const Icon(Icons.add),
              label: const Text('Registrar abono'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _ConsecutiveBadge(consecutive: sale.consecutive),
          const SizedBox(height: 12),
          _HeaderCard(sale: sale, profile: profile),
          const SizedBox(height: 16),
          if (sale.financialStatus == SaleFinancialStatus.lost &&
              sale.outstandingBalance != 0) ...[
            const _LossWarning(),
            const SizedBox(height: 12),
          ],
          Text(
            'Historial de abonos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          paymentsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => AppErrorView(error: e),
            data: (payments) => _PaymentsTimeline(
              sale: sale,
              payments: payments,
              isAdmin: isAdmin,
              profile: profile,
            ),
          ),
          if (sale.outstandingBalance > 0 && profile != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _confirmMarkAsLoss(context, ref, sale, profile),
              icon: const Icon(Icons.error_outline),
              label: const Text('Marcar pérdida'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withValues(
                        alpha: 0.6,
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsecutiveBadge extends StatelessWidget {
  const _ConsecutiveBadge({required this.consecutive});
  final String consecutive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tag, size: 14, color: theme.colorScheme.onPrimary),
            const SizedBox(width: 4),
            Text(
              consecutive,
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.sale, required this.profile});
  final Sale sale;
  final AppUser? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isOverdue = sale.outstandingBalance > 0 &&
        sale.creditDueDate != null &&
        sale.creditDueDate!.isBefore(AppClock.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sale.providerName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _FinancialPill(status: sale.financialStatus),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Total',
                    value: formatCop(sale.totalValue),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Pagado',
                    value: formatCop(sale.paidAmount),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Saldo',
                    value: formatCop(sale.outstandingBalance),
                    emphasized: sale.outstandingBalance > 0,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Pérdida',
                    value: formatCop(sale.lossAmount),
                    emphasized: sale.lossAmount > 0,
                    emphasizedColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.event,
                  size: 18,
                  color: isOverdue
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sale.creditDueDate == null
                        ? 'Sin plazo asignado'
                        : isOverdue
                            ? 'Plazo vencido el ${formatDate(sale.creditDueDate!)}'
                            : 'Plazo: ${formatDate(sale.creditDueDate!)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isOverdue ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
                if (profile != null)
                  TextButton(
                    onPressed: () => _editDueDate(context, ref),
                    child: const Text('Editar'),
                  ),
                if (sale.creditDueDate != null && profile != null)
                  IconButton(
                    tooltip: 'Quitar plazo',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _clearDueDate(context, ref),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDueDate(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: sale.creditDueDate ?? AppClock.now(),
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 365 * 3)),
      helpText: 'Plazo para cobrar',
    );
    if (picked == null) return;
    try {
      await ref.read(cashierRepositoryProvider).updateCreditDueDate(
            saleId: sale.id,
            date: picked,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _clearDueDate(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(cashierRepositoryProvider)
          .updateCreditDueDate(saleId: sale.id, date: null);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}

class _PaymentsTimeline extends StatelessWidget {
  const _PaymentsTimeline({
    required this.sale,
    required this.payments,
    required this.isAdmin,
    required this.profile,
  });
  final Sale sale;
  final List<SalePayment> payments;
  final bool isAdmin;
  final AppUser? profile;

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      final theme = Theme.of(context);
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Aún no hay abonos registrados.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final p in payments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PaymentCard(
              payment: p,
              isAdmin: isAdmin,
              profile: profile,
              saleId: sale.id,
            ),
          ),
      ],
    );
  }
}

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard({
    required this.payment,
    required this.isAdmin,
    required this.profile,
    required this.saleId,
  });
  final SalePayment payment;
  final bool isAdmin;
  final AppUser? profile;
  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.payments_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  formatCop(payment.amount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    payment.paymentMethod,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const Spacer(),
                if (isAdmin && profile != null)
                  IconButton(
                    tooltip: 'Anular',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        _confirmVoidPayment(context, ref, profile!),
                  ),
              ],
            ),
            if (payment.paymentMethod.toLowerCase() == 'mixto') ...[
              const SizedBox(height: 6),
              Text(
                '${formatCop(payment.cashAmount ?? 0)} efectivo · '
                '${formatCop(payment.transferAmount ?? 0)} transferencia'
                '${payment.transferDestination == null ? '' : ' a ${payment.transferDestination}'}',
                style: theme.textTheme.bodySmall,
              ),
            ] else if (payment.transferDestination != null &&
                payment.transferDestination!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Destino: ${payment.transferDestination}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (payment.payerName != null && payment.payerName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Recibido por: ${payment.payerName}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Registrado por ${payment.registeredByName} · '
              '${formatDateTime(payment.registeredAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (payment.notes != null && payment.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                payment.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmVoidPayment(
    BuildContext context,
    WidgetRef ref,
    AppUser actor,
  ) async {
    final reason = await _askReasonDialog(
      context,
      title: 'Anular abono',
      hint: 'Motivo de la anulación',
      confirmLabel: 'Anular abono',
      destructive: true,
    );
    if (reason == null) return;
    try {
      await ref.read(cashierRepositoryProvider).voidPayment(
            saleId: saleId,
            paymentId: payment.id,
            reason: reason,
            actor: actor,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abono anulado.')),
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
}

class _LossWarning extends StatelessWidget {
  const _LossWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esta venta está marcada como pérdida. Los abonos siguientes '
              'no cambian su estado financiero.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.emphasizedColor,
  });
  final String label;
  final String value;
  final bool emphasized;
  final Color? emphasizedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            color: emphasized ? (emphasizedColor ?? theme.colorScheme.error) : null,
          ),
        ),
      ],
    );
  }
}

class _FinancialPill extends StatelessWidget {
  const _FinancialPill({required this.status});
  final SaleFinancialStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (status) {
      SaleFinancialStatus.pending => (
          theme.colorScheme.onSurface.withValues(alpha: 0.55),
          'Pendiente',
        ),
      SaleFinancialStatus.partiallyPaid =>
        (const Color(0xFFE6A100), 'Pago parcial'),
      SaleFinancialStatus.paid => (const Color(0xFF2E7D32), 'Pagada'),
      SaleFinancialStatus.lost => (theme.colorScheme.error, 'Pérdida'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------
// Modal: registrar abono
// -------------------------------------------------------------------

Future<void> _openRegisterPaymentSheet(
  BuildContext context,
  WidgetRef ref,
  Sale sale,
  AppUser actor,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _RegisterPaymentSheet(sale: sale, actor: actor),
      );
    },
  );
}

class _RegisterPaymentSheet extends ConsumerStatefulWidget {
  const _RegisterPaymentSheet({required this.sale, required this.actor});
  final Sale sale;
  final AppUser actor;

  @override
  ConsumerState<_RegisterPaymentSheet> createState() =>
      _RegisterPaymentSheetState();
}

enum _PayMode { cash, transfer, mixed }

class _RegisterPaymentSheetState extends ConsumerState<_RegisterPaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  final _transferCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  _PayMode _mode = _PayMode.cash;
  String? _transferDestination;
  String? _payerName;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  num? get _amount {
    return num.tryParse(_amountCtrl.text.replaceAll(',', '.').trim());
  }

  String get _methodValue => switch (_mode) {
        _PayMode.cash => 'Efectivo',
        _PayMode.transfer => 'Transferencia',
        _PayMode.mixed => 'Mixto',
      };

  Future<void> _submit() async {
    setState(() => _error = null);
    final amount = _amount;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Ingresá un monto válido.');
      return;
    }
    num? cash;
    num? transfer;
    String? destination;
    switch (_mode) {
      case _PayMode.cash:
        cash = amount;
      case _PayMode.transfer:
        transfer = amount;
        destination = _transferDestination;
        if (destination == null || destination.isEmpty) {
          setState(() => _error = 'Seleccioná el destino de la transferencia.');
          return;
        }
      case _PayMode.mixed:
        final c =
            num.tryParse(_cashCtrl.text.replaceAll(',', '.').trim());
        final t =
            num.tryParse(_transferCtrl.text.replaceAll(',', '.').trim());
        if (c == null || t == null || c < 0 || t < 0) {
          setState(() {
            _error = 'Ingresá los montos en efectivo y por transferencia.';
          });
          return;
        }
        if ((c + t - amount).abs() > 1) {
          setState(() {
            _error =
                'La suma de efectivo y transferencia debe ser igual al monto del abono.';
          });
          return;
        }
        cash = c;
        transfer = t;
        destination = _transferDestination;
        if (destination == null || destination.isEmpty) {
          setState(() => _error = 'Seleccioná el destino de la transferencia.');
          return;
        }
    }

    if (_payerName == null || _payerName!.isEmpty) {
      setState(() => _error = 'Seleccioná quién recibe.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(cashierRepositoryProvider).registerPayment(
            saleId: widget.sale.id,
            amount: amount,
            paymentMethod: _methodValue,
            cashAmount: cash,
            transferAmount: transfer,
            transferDestination: destination,
            payerName: _payerName,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            actor: widget.actor,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Abono de ${formatCop(amount)} registrado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outstanding = widget.sale.outstandingBalance;
    final amount = _amount;
    final overpay = amount != null && outstanding > 0 && amount > outstanding;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registrar abono',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            outstanding > 0
                ? 'Saldo pendiente: ${formatCop(outstanding)}'
                : 'Sin saldo pendiente.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Monto',
              prefixText: r'$ ',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (overpay) ...[
            const SizedBox(height: 8),
            _OverpayBanner(extra: amount - outstanding),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_PayMode>(
              segments: const [
                ButtonSegment(value: _PayMode.cash, label: Text('Efectivo')),
                ButtonSegment(
                  value: _PayMode.transfer,
                  label: Text('Transferencia'),
                ),
                ButtonSegment(value: _PayMode.mixed, label: Text('Mixto')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() {
                  _mode = s.first;
                  if (_mode == _PayMode.cash) {
                    _cashCtrl.clear();
                    _transferCtrl.clear();
                    _transferDestination = null;
                  } else if (_mode == _PayMode.transfer) {
                    _cashCtrl.clear();
                    _transferCtrl.clear();
                  }
                });
              },
            ),
          ),
          if (_mode == _PayMode.mixed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cashCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Efectivo',
                      prefixText: r'$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _transferCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Transferencia',
                      prefixText: r'$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_mode == _PayMode.transfer || _mode == _PayMode.mixed) ...[
            const SizedBox(height: 12),
            MasterListField(
              listId: 'transfer_destinations',
              label: 'Destino de transferencia',
              initialValue: _transferDestination,
              required: true,
              onChanged: (v) => setState(() => _transferDestination = v),
            ),
          ],
          const SizedBox(height: 12),
          MasterListField(
            listId: 'payers',
            label: 'Quién recibe',
            initialValue: _payerName,
            required: true,
            onChanged: (v) => setState(() => _payerName = v),
            helperText: 'Persona en caja que recibe este abono.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Registrar abono'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverpayBanner extends StatelessWidget {
  const _OverpayBanner({required this.extra});
  final num extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const amber = Color(0xFFE6A100);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sobrepago de ${formatCop(extra)}. Se permite igualmente.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------
// Modal: marcar pérdida
// -------------------------------------------------------------------

Future<void> _confirmMarkAsLoss(
  BuildContext context,
  WidgetRef ref,
  Sale sale,
  AppUser actor,
) async {
  final reason = await _askReasonDialog(
    context,
    title: 'Marcar saldo como pérdida',
    hint: 'Motivo (ej. cliente no respondió, cierre contable)',
    confirmLabel: 'Marcar como pérdida',
    destructive: true,
    extraInfo:
        'Saldo a castigar: ${formatCop(sale.outstandingBalance)}. La venta '
        'queda con estado financiero "Pérdida" aunque después se '
        'registren abonos.',
  );
  if (reason == null) return;
  try {
    await ref.read(cashierRepositoryProvider).markAsLoss(
          saleId: sale.id,
          reason: reason,
          actor: actor,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${sale.consecutive} marcada como pérdida.')),
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

// -------------------------------------------------------------------
// Helper: modal de razón (reutilizable)
// -------------------------------------------------------------------

Future<String?> _askReasonDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  bool destructive = false,
  String? extraInfo,
}) {
  final ctrl = TextEditingController();
  return showDialog<String?>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (extraInfo != null) ...[
              Text(
                extraInfo,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El motivo es obligatorio.'),
                  ),
                );
                return;
              }
              Navigator.of(context).pop(text);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
