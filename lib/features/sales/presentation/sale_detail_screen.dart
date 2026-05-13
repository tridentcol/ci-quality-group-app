import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../../shared/widgets/state_pill.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
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
      appBar: AppBar(
        title: const Text('Detalle de venta'),
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
    // Sales solo edita mientras la solicitud sigue en `generada`. Una
    // vez que cajero la toma o procesa queda bloqueada para sales,
    // aunque la ventana de 24 h siga abierta.
    if (profile.role == AppRole.sales && sale.state != SaleState.generada) {
      return false;
    }
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
    ),);

    // Sales no ve nada financiero. El admin sí — payment breakdown,
    // método de pago, destino, etc. Esto NO incluye paidAmount /
    // outstandingBalance / financialStatus (eso vive solo en la
    // pantalla de pagos de caja).
    final showPaymentInfo = isAdmin;

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
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _StateHeader(sale: sale),
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
                      label: 'Número de documento', value: sale.documentNumber,),
                  _Row(label: 'Cliente', value: sale.providerName),
                  const Divider(height: 24),
                  _Row(label: 'Material', value: sale.material),
                  if (sale.materialVariant != null)
                    _Row(
                      label: 'Tipo de material',
                      value: sale.materialVariant!,
                    ),
                  _Row(label: 'Unidad', value: sale.unit),
                  _Row(label: 'Cantidad', value: sale.quantity.toString()),
                  _Row(
                      label: 'Valor unitario',
                      value: formatCop(sale.unitPrice),),
                  _Row(label: 'Valor total', value: formatCop(sale.totalValue)),
                  if (sale.customFields.isNotEmpty) ...[
                    const Divider(height: 24),
                    for (final entry in sale.customFields.entries)
                      _Row(label: entry.key, value: entry.value.toString()),
                  ],
                  if (showPaymentInfo) ...[
                    const Divider(height: 24),
                    if (sale.paymentMethod.isNotEmpty)
                      _Row(label: 'Método de pago', value: sale.paymentMethod),
                    if (sale.transferDestination != null &&
                        sale.transferDestination!.isNotEmpty)
                      _Row(
                        label: 'Destino transferencia',
                        value: sale.transferDestination!,
                      ),
                  ],
                  const Divider(height: 24),
                  _Row(label: 'Quién recibe', value: sale.payerName),
                  _Row(label: 'Registrada por', value: sale.createdByName),
                  _Row(
                      label: 'Registrada el',
                      value: formatDateTime(sale.createdAt),),
                  if (sale.updatedAt != null)
                    _Row(
                        label: 'Última edición',
                        value: formatDateTime(sale.updatedAt!),),
                  if (sale.editableUntil != null && !isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        AppClock.now().isBefore(sale.editableUntil!) &&
                                sale.state == SaleState.generada
                            ? 'Editable hasta ${formatDateTime(sale.editableUntil!)} '
                                'mientras la solicitud esté en estado generada.'
                            : sale.state != SaleState.generada
                                ? 'La solicitud ya no está en estado generada. Solo el admin puede modificar.'
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
        // Breakdown de pago: solo admin lo ve y solo cuando aporta info
        // más allá del row "Método de pago: Efectivo".
        if (showPaymentInfo &&
            (sale.isMixedPayment ||
                (sale.transferDestination != null &&
                    sale.transferDestination!.isNotEmpty))) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PaymentBreakdownCard(sale: sale),
          ),
        ],
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

/// Donut chart + texto con el desglose del pago. Solo se renderiza
/// cuando aporta valor (pago mixto o transferencia con destino) — en
/// ventas 100% efectivo el row "Método de pago" del card principal
/// ya transmite todo lo que hay que saber.
class _PaymentBreakdownCard extends StatelessWidget {
  const _PaymentBreakdownCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cash = sale.cashPortion;
    final transfer = sale.transferPortion;
    final total = sale.totalValue;
    final cashPct = total > 0 ? (cash / total) * 100 : 0;
    final transferPct = total > 0 ? (transfer / total) * 100 : 0;
    final cashColor = AppColors.leafGreen;
    final transferColor = theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Desglose del pago',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Donut con las dos porciones. Si una es 0, fl_chart
                // recibe una sola sección y se ve como dona completa.
                SizedBox(
                  width: 110,
                  height: 110,
                  child: PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      centerSpaceRadius: 32,
                      sectionsSpace: 2,
                      sections: [
                        if (cash > 0)
                          PieChartSectionData(
                            value: cash.toDouble(),
                            color: cashColor,
                            radius: 18,
                            showTitle: false,
                          ),
                        if (transfer > 0)
                          PieChartSectionData(
                            value: transfer.toDouble(),
                            color: transferColor,
                            radius: 18,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cash > 0)
                        _BreakdownRow(
                          color: cashColor,
                          label: 'Efectivo',
                          amount: cash,
                          percent: cashPct.toDouble(),
                        ),
                      if (cash > 0 && transfer > 0)
                        const SizedBox(height: 8),
                      if (transfer > 0)
                        _BreakdownRow(
                          color: transferColor,
                          label: sale.transferDestination == null
                              ? 'Transferencia'
                              : 'Transferencia · '
                                  '${sale.transferDestination}',
                          amount: transfer,
                          percent: transferPct.toDouble(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.percent,
  });
  final Color color;
  final String label;
  final num amount;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Text(
                '${formatCop(amount)}  ·  ${percent.toStringAsFixed(0)}%',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Encabezado de estado: muestra el state pill prominente + trazas
/// (procesada → quién y cuándo; cancelada → razón). Sales NO ve nada
/// financiero acá: paidAmount / outstandingBalance / financialStatus
/// son del dominio de caja.
class _StateHeader extends StatelessWidget {
  const _StateHeader({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatePill(state: sale.state),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _captionFor(sale.state),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            if (sale.state == SaleState.procesada &&
                sale.processedAt != null) ...[
              const SizedBox(height: 8),
              _TraceLine(
                icon: Icons.check_circle_outline,
                text: 'Procesada por ${sale.processedByName ?? '—'} · '
                    '${formatDateTime(sale.processedAt!)}',
              ),
            ],
            if (sale.state == SaleState.cancelada) ...[
              if (sale.canceledAt != null) ...[
                const SizedBox(height: 8),
                _TraceLine(
                  icon: Icons.cancel_outlined,
                  text: 'Cancelada por ${sale.canceledByName ?? '—'} · '
                      '${formatDateTime(sale.canceledAt!)}',
                ),
              ],
              if (sale.cancelReason != null &&
                  sale.cancelReason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _TraceLine(
                  icon: Icons.notes_outlined,
                  text: 'Motivo: ${sale.cancelReason}',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _captionFor(SaleState state) => switch (state) {
        SaleState.generada =>
          'Esperando que caja la tome. Mientras tanto podés editarla.',
        SaleState.enProceso =>
          'Caja la está revisando. No la podés editar hasta que la procesen '
              'o te la devuelvan.',
        SaleState.procesada => 'Caja confirmó. Podés entregar el material.',
        SaleState.cancelada => 'Esta solicitud fue cancelada.',
      };
}

class _TraceLine extends StatelessWidget {
  const _TraceLine({required this.icon, required this.text});
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
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
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
