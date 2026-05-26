import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/kpi_card.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../cashier/data/cashier_repository.dart';
import '../../sales/data/sales_repository.dart';

/// Drill-down del KPI "Pagos bajo delegación" del dashboard del admin.
/// Lista todos los `SalePayment` con `createdViaDelegation: true` dentro
/// del rango (default mes actual). Cada item linkea a la pantalla de
/// pagos de la venta para auditar el resto.
///
/// Sin export xlsx por ahora — la lista es pequeña por diseño (es un
/// flujo excepcional). Si crece, se suma export como Fase 5.
class PaymentsViaDelegationScreen extends ConsumerStatefulWidget {
  const PaymentsViaDelegationScreen({super.key});

  @override
  ConsumerState<PaymentsViaDelegationScreen> createState() =>
      _PaymentsViaDelegationScreenState();
}

class _PaymentsViaDelegationScreenState
    extends ConsumerState<PaymentsViaDelegationScreen> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = SalesDateRange(start: _start, end: _end);
    final paymentsAsync = ref.watch(paymentsByRangeProvider(range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos bajo delegación'),
        actions: const [ThemeModeIconButton()],
      ),
      body: Column(
        children: [
          RangeFilterBar(
            start: _start,
            end: _end,
            onChanged: (r) => setState(() {
              _start = r.start;
              _end = r.end;
            }),
          ),
          Expanded(
            child: paymentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorView(error: e),
              data: (allPayments) {
                final items = allPayments
                    .where((p) => p.payment.createdViaDelegation)
                    .toList()
                  ..sort(
                    (a, b) => b.payment.registeredAt
                        .compareTo(a.payment.registeredAt),
                  );
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.lock_open_outlined,
                    title: 'Sin pagos bajo delegación',
                    message: 'No se registró ningún cobro a través del modo '
                        'delegación caja en este rango.',
                  );
                }
                final total = items.fold<num>(
                  0,
                  (a, it) => a + it.payment.amount,
                );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    KpiRow(cards: [
                      KpiCard(
                        label: 'Total cobrado',
                        value: formatCop(total),
                        subtitle:
                            '${items.length} pago${items.length == 1 ? '' : 's'}',
                        icon: Icons.payments_outlined,
                        color: const Color(0xFFE6A100),
                      ),
                    ],),
                    const SizedBox(height: 16),
                    Text(
                      'Detalle',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final it in items) ...[
                      _DelegationPaymentRow(item: it),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DelegationPaymentRow extends StatelessWidget {
  const _DelegationPaymentRow({required this.item});

  final PaymentWithSaleId item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = item.payment;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/cashier/${item.saleId}/payments'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatCop(p.amount),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
                      p.paymentMethod,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sales · ${p.registeredByName} · '
                '${formatDateTime(p.registeredAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (p.payerName != null && p.payerName!.isNotEmpty)
                Text(
                  'Recibido por: ${p.payerName}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
