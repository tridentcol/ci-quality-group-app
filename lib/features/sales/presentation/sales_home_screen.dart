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
/// + acceso rápido a "Nueva venta".
class SalesHomeScreen extends ConsumerWidget {
  const SalesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fullName = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.fullName ?? 'Usuario',
    ));
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Movimientos recientes',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
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
                else
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
