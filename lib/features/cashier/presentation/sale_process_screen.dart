import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';
import '../data/cashier_repository.dart';

/// Detalle de una venta visto desde caja. Permite mover el workflow:
/// tomar (soft-lock), procesar, devolver a sales, cancelar. El registro
/// de abonos / pérdidas / plazo entra en Fase 4 — acá solo enlazamos.
class SaleProcessScreen extends ConsumerWidget {
  const SaleProcessScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleAsync = ref.watch(saleByIdProvider(saleId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitud de venta'),
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
          child: _StatusCard(sale: sale),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _DetailsCard(sale: sale),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ActionsBar(sale: sale),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BigPill(
                  label: _stateLabel(sale.state),
                  color: _stateColor(sale.state, theme),
                ),
                const SizedBox(width: 8),
                _BigPill(
                  label: _finLabel(sale.financialStatus),
                  color: _finColor(sale.financialStatus, theme),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetricBlock(
                    label: 'Total',
                    value: formatCop(sale.totalValue),
                  ),
                ),
                Expanded(
                  child: _MetricBlock(
                    label: 'Pagado',
                    value: formatCop(sale.paidAmount),
                  ),
                ),
                Expanded(
                  child: _MetricBlock(
                    label: 'Saldo',
                    value: formatCop(sale.outstandingBalance),
                    emphasized: sale.outstandingBalance > 0,
                  ),
                ),
              ],
            ),
            if (sale.processedAt != null) ...[
              const Divider(height: 24),
              _Line(
                icon: Icons.check_circle_outline,
                text: 'Procesada por ${sale.processedByName ?? '—'} · '
                    '${formatDateTime(sale.processedAt!)}',
              ),
            ],
            if (sale.canceledAt != null) ...[
              const Divider(height: 24),
              _Line(
                icon: Icons.cancel,
                text: 'Cancelada por ${sale.canceledByName ?? '—'} · '
                    '${formatDateTime(sale.canceledAt!)}',
              ),
              if (sale.cancelReason != null &&
                  sale.cancelReason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _Line(
                  icon: Icons.notes,
                  text: 'Motivo: ${sale.cancelReason}',
                ),
              ],
            ],
            if (sale.markedAsLossAt != null) ...[
              const Divider(height: 24),
              _Line(
                icon: Icons.error_outline,
                text: 'Saldo marcado como pérdida por '
                    '${sale.markedAsLossByName ?? '—'} · '
                    '${formatDateTime(sale.markedAsLossAt!)}',
              ),
              if (sale.lossReason != null && sale.lossReason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _Line(
                  icon: Icons.notes,
                  text: 'Motivo: ${sale.lossReason}',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Row(label: 'Cliente', value: sale.providerName),
            _Row(label: 'Documento', value: '${sale.documentType} · ${sale.documentNumber}'),
            const Divider(height: 24),
            _Row(label: 'Material', value: sale.material),
            if (sale.materialVariant != null)
              _Row(label: 'Tipo', value: sale.materialVariant!),
            _Row(label: 'Unidad', value: sale.unit),
            _Row(label: 'Cantidad', value: sale.quantity.toString()),
            _Row(label: 'Valor unitario', value: formatCop(sale.unitPrice)),
            _Row(label: 'Quién recibe', value: sale.payerName),
            const Divider(height: 24),
            _Row(label: 'Solicitada por', value: sale.createdByName),
            _Row(
              label: 'Fecha de solicitud',
              value: formatDateTime(sale.createdAt),
            ),
            if (sale.creditDueDate != null)
              _Row(
                label: 'Plazo de pago',
                value: formatDate(sale.creditDueDate!),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionsBar extends ConsumerWidget {
  const _ActionsBar({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    if (profile == null) {
      return const SizedBox.shrink();
    }
    final actions = <Widget>[];
    switch (sale.state) {
      case SaleState.generada:
        actions
          ..add(
            FilledButton.icon(
              onPressed: () => _takeRequest(context, ref, profile),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar proceso'),
            ),
          )
          ..add(const SizedBox(height: 10))
          ..add(
            OutlinedButton.icon(
              onPressed: () => _cancel(context, ref, profile),
              icon: const Icon(Icons.close),
              label: const Text('Cancelar'),
            ),
          );
      case SaleState.enProceso:
        actions
          ..add(
            FilledButton.icon(
              onPressed: () => _process(context, ref, profile),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Procesar'),
            ),
          )
          ..add(const SizedBox(height: 10))
          ..add(
            OutlinedButton.icon(
              onPressed: () => _returnToSales(context, ref, profile),
              icon: const Icon(Icons.undo),
              label: const Text('Devolver'),
            ),
          )
          ..add(const SizedBox(height: 10))
          ..add(
            OutlinedButton.icon(
              onPressed: () => _cancel(context, ref, profile),
              icon: const Icon(Icons.close),
              label: const Text('Cancelar'),
            ),
          );
      case SaleState.procesada:
      case SaleState.cancelada:
        actions.add(
          FilledButton.tonalIcon(
            onPressed: () => _openPayments(context),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Ver pagos'),
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: actions,
    );
  }

  Future<void> _takeRequest(
    BuildContext context,
    WidgetRef ref,
    AppUser actor,
  ) async {
    try {
      await ref
          .read(cashierRepositoryProvider)
          .takeRequest(saleId: sale.id, actor: actor);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${sale.consecutive} en proceso.')),
        );
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _process(
    BuildContext context,
    WidgetRef ref,
    AppUser actor,
  ) async {
    try {
      await ref
          .read(cashierRepositoryProvider)
          .processRequest(saleId: sale.id, actor: actor);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${sale.consecutive} procesada.')),
        );
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _returnToSales(
    BuildContext context,
    WidgetRef ref,
    AppUser actor,
  ) async {
    final reason = await _askReason(
      context,
      title: 'Devolver solicitud',
      hint: 'Motivo (opcional)',
      confirmLabel: 'Devolver',
      requireText: false,
    );
    if (reason == null) return;
    try {
      await ref.read(cashierRepositoryProvider).returnToSales(
            saleId: sale.id,
            actor: actor,
            reason: reason.isEmpty ? null : reason,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${sale.consecutive} devuelta.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    AppUser actor,
  ) async {
    final reason = await _askReason(
      context,
      title: 'Cancelar solicitud',
      hint: 'Motivo de la cancelación',
      confirmLabel: 'Confirmar',
      requireText: true,
      destructive: true,
    );
    if (reason == null) return;
    try {
      await ref.read(cashierRepositoryProvider).cancelRequest(
            saleId: sale.id,
            actor: actor,
            reason: reason,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${sale.consecutive} cancelada.')),
        );
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  void _openPayments(BuildContext context) {
    context.push('/cashier/${sale.id}/payments');
  }

  void _showError(BuildContext context, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(error))),
    );
  }
}

/// Modal genérico para pedir una razón antes de una transición destructiva
/// o reversible. Devuelve `null` si se cancela, o el texto (posiblemente
/// vacío si `requireText == false`) cuando se confirma.
Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  required bool requireText,
  bool destructive = false,
}) {
  final ctrl = TextEditingController();
  return showDialog<String?>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
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
              if (requireText && text.isEmpty) {
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

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final String label;
  final String value;
  final bool emphasized;

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
            color: emphasized ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _BigPill extends StatelessWidget {
  const _BigPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
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

String _stateLabel(SaleState s) => switch (s) {
      SaleState.generada => 'Generada',
      SaleState.enProceso => 'En proceso',
      SaleState.procesada => 'Procesada',
      SaleState.cancelada => 'Cancelada',
    };

Color _stateColor(SaleState s, ThemeData theme) => switch (s) {
      SaleState.generada => const Color(0xFFE6A100),
      SaleState.enProceso => theme.colorScheme.primary,
      SaleState.procesada => const Color(0xFF2E7D32),
      SaleState.cancelada =>
        theme.colorScheme.onSurface.withValues(alpha: 0.55),
    };

String _finLabel(SaleFinancialStatus s) => switch (s) {
      SaleFinancialStatus.pending => 'Pago pendiente',
      SaleFinancialStatus.partiallyPaid => 'Pago parcial',
      SaleFinancialStatus.paid => 'Pagada',
      SaleFinancialStatus.lost => 'Pérdida',
    };

Color _finColor(SaleFinancialStatus s, ThemeData theme) => switch (s) {
      SaleFinancialStatus.pending =>
        theme.colorScheme.onSurface.withValues(alpha: 0.55),
      SaleFinancialStatus.partiallyPaid => const Color(0xFFE6A100),
      SaleFinancialStatus.paid => const Color(0xFF2E7D32),
      SaleFinancialStatus.lost => theme.colorScheme.error,
    };
