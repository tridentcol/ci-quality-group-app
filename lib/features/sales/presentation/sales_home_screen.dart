import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../auth/data/auth_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import 'widgets/sale_card.dart';

/// Pantalla principal del encargado de ventas.
///
/// Muestra ventas recientes + acceso rápido a "Nueva venta".
class SalesHomeScreen extends ConsumerWidget {
  const SalesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final sales = ref.watch(recentSalesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de ventas'),
        actions: [
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
      body: sales.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text('Error: $e')),
        ),
        data: (data) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                fullName: profile?.fullName ?? 'Usuario',
                todayTotal: _todaysTotal(data),
                todayCount: _todaysCount(data),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Movimientos recientes',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            if (data.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Aún no se han registrado ventas.\nEmpieza con la primera.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
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
        ),
      ),
    );
  }

  num _todaysTotal(List<Sale> sales) {
    final today = AppClock.now();
    return sales
        .where((s) => isSameDay(s.date, today))
        .fold<num>(0, (sum, s) => sum + s.totalValue);
  }

  int _todaysCount(List<Sale> sales) {
    final today = AppClock.now();
    return sales.where((s) => isSameDay(s.date, today)).length;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.fullName,
    required this.todayTotal,
    required this.todayCount,
  });

  final String fullName;
  final num todayTotal;
  final int todayCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hola, $fullName',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            'Hoy',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 2),
          Text(
            formatCop(todayTotal),
            style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            '$todayCount venta${todayCount == 1 ? '' : 's'} registrada${todayCount == 1 ? '' : 's'}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
