import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../auth/data/auth_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';

/// Detalle de una venta. Permite editar/anular cuando:
///  - El usuario es admin (siempre).
///  - El usuario creó la venta y todavía está dentro de la ventana de 24 h.
class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleAsync = ref.watch(saleByIdProvider(saleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de venta')),
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
          return _SaleDetailBody(sale: sale);
        },
      ),
    );
  }
}

class _SaleDetailBody extends ConsumerWidget {
  const _SaleDetailBody({required this.sale});

  final Sale sale;

  bool _canEdit(WidgetRef ref) {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile == null) return false;
    if (profile.role == AppRole.admin) return true;
    if (profile.uid != sale.createdBy) return false;
    final until = sale.editableUntil;
    if (until == null) return false;
    return AppClock.now().isBefore(until);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Anular venta',
      message:
          '¿Seguro que deseas anular la venta ${sale.consecutive}? No se puede deshacer.',
      confirmLabel: 'Anular',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    try {
      await ref.read(salesRepositoryProvider).deleteSale(sale.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Venta ${sale.consecutive} anulada.')),
        );
        context.pop();
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
    final theme = Theme.of(context);
    final canEdit = _canEdit(ref);
    final isAdmin = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.role == AppRole.admin,
    ));

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: [
        HeroBanner(
          title: '${sale.consecutive} · ${formatDate(sale.date)}',
          primaryValue: formatCop(sale.totalValue),
          secondary: '${sale.quantity} ${sale.unit.toLowerCase()} · '
              '${sale.material}'
              '${sale.materialVariant != null ? ' · ${sale.materialVariant}' : ''}',
          icon: Icons.tag,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _Row(label: 'Tipo de documento', value: sale.documentType),
                  _Row(
                      label: 'Número de documento', value: sale.documentNumber),
                  _Row(label: 'Cliente', value: sale.providerName),
                  const Divider(height: 24),
                  _Row(label: 'Material', value: sale.material),
                  if (sale.materialVariant != null)
                    _Row(label: 'Tipo de lámina', value: sale.materialVariant!),
                  _Row(label: 'Unidad', value: sale.unit),
                  _Row(label: 'Cantidad', value: sale.quantity.toString()),
                  _Row(
                      label: 'Valor unitario',
                      value: formatCop(sale.unitPrice)),
                  _Row(label: 'Valor total', value: formatCop(sale.totalValue)),
                  if (sale.customFields.isNotEmpty) ...[
                    const Divider(height: 24),
                    for (final entry in sale.customFields.entries)
                      _Row(label: entry.key, value: entry.value.toString()),
                  ],
                  const Divider(height: 24),
                  _Row(label: 'Método de pago', value: sale.paymentMethod),
                  _Row(label: 'Quién recibe', value: sale.payerName),
                  const Divider(height: 24),
                  _Row(label: 'Registrada por', value: sale.createdByName),
                  _Row(
                      label: 'Registrada el',
                      value: formatDateTime(sale.createdAt)),
                  if (sale.updatedAt != null)
                    _Row(
                        label: 'Última edición',
                        value: formatDateTime(sale.updatedAt!)),
                  if (sale.editableUntil != null && !isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        AppClock.now().isBefore(sale.editableUntil!)
                            ? 'Editable hasta ${formatDateTime(sale.editableUntil!)}'
                            : 'Ya pasó la ventana de edición. Solo el admin puede modificar.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        context.push('/sales/${sale.id}/edit', extra: sale),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 12),
                if (isAdmin)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDelete(context, ref),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Anular'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
