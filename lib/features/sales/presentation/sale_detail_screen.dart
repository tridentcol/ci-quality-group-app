import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../auth/data/auth_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import 'sale_form_screen.dart';

/// Detalle de una venta. Permite editar/anular cuando:
///  - El usuario es admin (siempre).
///  - El usuario creó la venta y todavía está dentro de la ventana de 24 h.
class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleFuture = ref.watch(_saleByIdProvider(saleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de venta')),
      body: saleFuture.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sale) {
          if (sale == null) {
            return const Center(child: Text('La venta no existe.'));
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
    if (profile.role.id == 'admin') return true;
    if (profile.uid != sale.createdBy) return false;
    final until = sale.editableUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular venta'),
        content: Text(
          '¿Seguro que deseas anular la venta ${sale.consecutive}? '
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(salesRepositoryProvider).deleteSale(sale.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Venta ${sale.consecutive} anulada.')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canEdit = _canEdit(ref);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isAdmin = profile?.role.id == 'admin';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tag, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    sale.consecutive,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatDate(sale.date),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                formatCop(sale.totalValue),
                style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                '${sale.quantity} ${sale.unit.toLowerCase()} · ${sale.material}'
                '${sale.materialVariant != null ? ' · ${sale.materialVariant}' : ''}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Row(label: 'Tipo de documento', value: sale.documentType),
                _Row(label: 'Número de documento', value: sale.documentNumber),
                _Row(label: 'Proveedor', value: sale.providerName),
                const Divider(height: 24),
                _Row(label: 'Material', value: sale.material),
                if (sale.materialVariant != null)
                  _Row(label: 'Tipo de lámina', value: sale.materialVariant!),
                _Row(label: 'Unidad', value: sale.unit),
                _Row(label: 'Cantidad', value: sale.quantity.toString()),
                _Row(label: 'Valor unitario', value: formatCop(sale.unitPrice)),
                _Row(label: 'Valor total', value: formatCop(sale.totalValue)),
                const Divider(height: 24),
                _Row(label: 'Método de pago', value: sale.paymentMethod),
                _Row(label: 'Quién paga', value: sale.payerName),
                const Divider(height: 24),
                _Row(label: 'Registrada por', value: sale.createdByName),
                _Row(label: 'Registrada el', value: formatDateTime(sale.createdAt)),
                if (sale.updatedAt != null)
                  _Row(label: 'Última edición', value: formatDateTime(sale.updatedAt!)),
                if (sale.editableUntil != null && !isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateTime.now().isBefore(sale.editableUntil!)
                          ? 'Editable hasta ${formatDateTime(sale.editableUntil!)}'
                          : 'Ya pasó la ventana de edición. Solo el admin puede modificar.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canEdit)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SaleFormScreen(editingSale: sale),
                    ),
                  ),
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

final _saleByIdProvider =
    FutureProvider.family.autoDispose<Sale?, String>((ref, id) {
  return ref.watch(salesRepositoryProvider).getSale(id);
});
