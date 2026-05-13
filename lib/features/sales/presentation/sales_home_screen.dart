import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import 'widgets/sale_card.dart';

/// Pantalla principal del encargado de ventas. Muestra ventas recientes
/// + acceso rápido a "Nueva venta". Si hay solicitudes pendientes de
/// caja (state in [generada, en_proceso]), aparecen destacadas arriba
/// para que sales sepa qué le falta antes de entregar material.
class SalesHomeScreen extends ConsumerWidget {
  const SalesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fullName = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.fullName ?? 'Usuario',
    ),);
    final salesAsync = ref.watch(recentSalesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de ventas'),
        actions: [
          const ThemeModeIconButton(),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sales/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva venta'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentSalesProvider),
        child: salesAsync.when(
          loading: () => const SkeletonList(),
          error: (e, _) => AppErrorView(
            error: e,
            onRetry: () => ref.invalidate(recentSalesProvider),
          ),
          data: (data) {
            final today = _todaysSummary(data);
            final pending = data
                .where((s) =>
                    s.state == SaleState.generada ||
                    s.state == SaleState.enProceso,)
                .toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: HeroBanner(
                    title: 'Hola, $fullName · hoy',
                    primaryValue: formatCop(today.total),
                    secondary:
                        '${today.count} venta${today.count == 1 ? '' : 's'} registrada${today.count == 1 ? '' : 's'}',
                  ),
                ),
                if (pending.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: _PendingHeader(count: pending.length),
                    ),
                  ),
                  SliverList.separated(
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: pending.length,
                    itemBuilder: (context, i) {
                      final sale = pending[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SaleCard(
                          sale: sale,
                          onTap: () => context.push('/sales/${sale.id}'),
                        ),
                      );
                    },
                  ),
                ],
                if (data.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Sin ventas todavía',
                      message: 'Empieza con la primera venta del día.',
                      actionLabel: 'Registrar primera venta',
                      onAction: () => context.push('/sales/new'),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      pending.isNotEmpty ? 20 : 16,
                      16,
                      8,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Movimientos recientes',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  SliverList.separated(
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: data.length,
                    itemBuilder: (context, i) {
                      final sale = data[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SaleCard(
                          sale: sale,
                          onTap: () => context.push('/sales/${sale.id}'),
                        ),
                      );
                    },
                  ),
                ],
                const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
              ],
            );
          },
        ),
      ),
    );
  }

  ({num total, int count}) _todaysSummary(List<Sale> sales) {
    final today = AppClock.now();
    num total = 0;
    int count = 0;
    for (final s in sales) {
      if (isSameDay(s.date, today)) {
        total += s.totalValue;
        count++;
      }
    }
    return (total: total, count: count);
  }
}

/// Banda destacada arriba de la home cuando el sales user tiene
/// solicitudes generadas o en proceso en caja. Sirve para que se
/// entere de un vistazo sin tener que escanear toda la lista.
class _PendingHeader extends StatelessWidget {
  const _PendingHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const amber = Color(0xFFE6A100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_outlined, color: amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? 'Tenés 1 solicitud pendiente de procesar en caja.'
                  : 'Tenés $count solicitudes pendientes de procesar en caja.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
