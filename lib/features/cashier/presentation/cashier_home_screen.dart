import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/notifications_bell.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../sales/domain/sale.dart';
import '../data/cashier_repository.dart';

/// Home del rol cajero (y del admin actuando como caja). Tres tabs con
/// la misma fuente de datos pero filtros distintos:
///
///   1. Pendientes — workflow no terminal (generada / en_proceso).
///   2. Deudas — procesadas con saldo + canceladas con abonos + pérdidas.
///   3. Cerradas — procesadas pagadas + canceladas limpias.
///
/// Los filtros (búsqueda + rango) viven arriba y se aplican a los 3 tabs.
class CashierHomeScreen extends ConsumerStatefulWidget {
  const CashierHomeScreen({super.key});

  @override
  ConsumerState<CashierHomeScreen> createState() => _CashierHomeScreenState();
}

class _CashierHomeScreenState extends ConsumerState<CashierHomeScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _range;
  bool _onlyOverdue = false;
  _DebtsSort _debtsSort = _DebtsSort.oldestFirst;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 1)),
      initialDateRange: _range,
      helpText: 'Filtrar por fecha de la solicitud',
      saveText: 'Aplicar',
      cancelText: 'Cancelar',
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.role == AppRole.admin,
    ),);
    final pending = ref.watch(salesByStatesProvider(pendingStatesQuery));
    final processed = ref.watch(salesByStatesProvider(processedStatesQuery));
    final canceled = ref.watch(salesByStatesProvider(canceledStatesQuery));

    final filter = _SalesFilter(
      query: _searchCtrl.text.trim().toLowerCase(),
      range: _range,
    );

    final pendingList = filter.apply(pending.valueOrNull ?? const [])
      ..sort((a, b) => a.date.compareTo(b.date));
    final processedList = filter.apply(processed.valueOrNull ?? const []);
    final canceledList = filter.apply(canceled.valueOrNull ?? const []);

    final debtsList = _buildDebtsList(processedList, canceledList);
    final closedList = _buildClosedList(processedList, canceledList);

    final pendingBadge = pendingList.length;
    final debtsBadge = _debtsBadgeCount(debtsList);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: isAdmin
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver al panel admin',
                  onPressed: () => context.go('/admin'),
                )
              : null,
          title: const Text('Caja'),
          actions: [
            const NotificationsBell(),
            const ThemeModeIconButton(),
            IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout_outlined),
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(108),
            child: Column(
              children: [
                _FilterBar(
                  searchCtrl: _searchCtrl,
                  range: _range,
                  onRangeTap: _pickRange,
                  onRangeClear: _range == null
                      ? null
                      : () => setState(() => _range = null),
                  onSearchChanged: (_) => setState(() {}),
                ),
                TabBar(
                  tabs: [
                    _TabLabel(label: 'Pendientes', badge: pendingBadge),
                    _TabLabel(label: 'Deudas', badge: debtsBadge),
                    const _TabLabel(label: 'Cerradas'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _PendingTab(
              loading: pending.isLoading,
              error: pending.error,
              sales: pendingList,
            ),
            _DebtsTab(
              loading: processed.isLoading || canceled.isLoading,
              error: processed.error ?? canceled.error,
              sales: debtsList,
              onlyOverdue: _onlyOverdue,
              onOverdueToggled: (v) => setState(() => _onlyOverdue = v),
              sort: _debtsSort,
              onSortChanged: (v) => setState(() => _debtsSort = v),
            ),
            _ClosedTab(
              loading: processed.isLoading || canceled.isLoading,
              error: processed.error ?? canceled.error,
              sales: closedList,
            ),
          ],
        ),
      ),
    );
  }

  /// Combina procesadas con saldo + canceladas con abonos + pérdidas.
  /// Las `lost` van al final para no taparse con las activas.
  List<Sale> _buildDebtsList(List<Sale> processed, List<Sale> canceled) {
    final receivables = processed.where((s) =>
        s.financialStatus == SaleFinancialStatus.pending ||
        s.financialStatus == SaleFinancialStatus.partiallyPaid,);
    final canceledWithPayments = canceled.where((s) => s.paidAmount > 0);
    final losses = processed.where(
      (s) => s.financialStatus == SaleFinancialStatus.lost,
    );
    return [
      ...receivables,
      ...canceledWithPayments,
      ...losses,
    ];
  }

  /// Procesadas pagadas + canceladas limpias (sin abonos). Recortado a 50
  /// más recientes para no traer históricos enteros.
  List<Sale> _buildClosedList(List<Sale> processed, List<Sale> canceled) {
    final paid = processed.where(
      (s) => s.financialStatus == SaleFinancialStatus.paid,
    );
    final canceledClean = canceled.where((s) => s.paidAmount == 0);
    final merged = [...paid, ...canceledClean]
      ..sort((a, b) => b.date.compareTo(a.date));
    return merged.take(50).toList();
  }

  /// Vencidos (creditDueDate < hoy) + sin plazo y antiguos > 30 días.
  int _debtsBadgeCount(List<Sale> debts) {
    final now = AppClock.now();
    return debts.where((s) {
      if (s.outstandingBalance <= 0) return false;
      final due = s.creditDueDate;
      if (due != null) return due.isBefore(now);
      return now.difference(s.createdAt).inDays > 30;
    }).length;
  }
}

/// Estructura inmutable con el estado de filtrado actual. Vive en el
/// `build` y se descarta — no se persiste.
class _SalesFilter {
  const _SalesFilter({required this.query, required this.range});
  final String query;
  final DateTimeRange? range;

  List<Sale> apply(List<Sale> sales) {
    if (query.isEmpty && range == null) {
      return List<Sale>.from(sales);
    }
    final end = range == null
        ? null
        : DateTime(range!.end.year, range!.end.month, range!.end.day, 23, 59, 59);
    final start = range?.start;
    return sales.where((s) {
      if (query.isNotEmpty) {
        final blob = '${s.consecutive} ${s.providerName}'.toLowerCase();
        if (!blob.contains(query)) return false;
      }
      if (start != null && s.date.isBefore(start)) return false;
      if (end != null && s.date.isAfter(end)) return false;
      return true;
    }).toList();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtrl,
    required this.range,
    required this.onRangeTap,
    required this.onRangeClear,
    required this.onSearchChanged,
  });

  final TextEditingController searchCtrl;
  final DateTimeRange? range;
  final VoidCallback onRangeTap;
  final VoidCallback? onRangeClear;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rangeLabel = range == null
        ? 'Rango de fecha'
        : '${formatDate(range!.start)} – ${formatDate(range!.end)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Consecutivo o cliente',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          searchCtrl.clear();
                          onSearchChanged('');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InputChip(
            avatar: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              rangeLabel,
              style: theme.textTheme.bodySmall,
            ),
            onPressed: onRangeTap,
            onDeleted: onRangeClear,
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, this.badge});
  final String label;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (badge != null && badge! > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 20),
              alignment: Alignment.center,
              child: Text(
                badge! > 99 ? '99+' : '$badge',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _DebtsSort { oldestFirst, highestAmountFirst }

class _PendingTab extends StatelessWidget {
  const _PendingTab({
    required this.loading,
    required this.error,
    required this.sales,
  });

  final bool loading;
  final Object? error;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    if (loading && sales.isEmpty) return const SkeletonList();
    if (error != null) return AppErrorView(error: error!);
    if (sales.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Sin solicitudes pendientes',
        message: 'Cuando sales registre una venta nueva, va a aparecer acá.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: sales.length,
      itemBuilder: (context, i) => _CashierSaleCard(
        sale: sales[i],
        onTap: () => context.push('/cashier/${sales[i].id}'),
      ),
    );
  }
}

class _DebtsTab extends StatelessWidget {
  const _DebtsTab({
    required this.loading,
    required this.error,
    required this.sales,
    required this.onlyOverdue,
    required this.onOverdueToggled,
    required this.sort,
    required this.onSortChanged,
  });

  final bool loading;
  final Object? error;
  final List<Sale> sales;
  final bool onlyOverdue;
  final ValueChanged<bool> onOverdueToggled;
  final _DebtsSort sort;
  final ValueChanged<_DebtsSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    if (loading && sales.isEmpty) return const SkeletonList();
    if (error != null) return AppErrorView(error: error!);

    final now = AppClock.now();
    final overdueCount = sales
        .where((s) =>
            s.outstandingBalance > 0 &&
            s.creditDueDate != null &&
            s.creditDueDate!.isBefore(now),)
        .length;

    var visible = sales;
    if (onlyOverdue) {
      visible = visible
          .where((s) =>
              s.outstandingBalance > 0 &&
              s.creditDueDate != null &&
              s.creditDueDate!.isBefore(now),)
          .toList();
    }
    // Ordenamiento por antigüedad o por monto. Las pérdidas se mantienen
    // al final del bloque general (ya vienen así desde _buildDebtsList),
    // así que solo ordenamos dentro del bloque "activos".
    final activos = <Sale>[];
    final perdidas = <Sale>[];
    for (final s in visible) {
      if (s.financialStatus == SaleFinancialStatus.lost) {
        perdidas.add(s);
      } else {
        activos.add(s);
      }
    }
    activos.sort(
      (a, b) => switch (sort) {
        _DebtsSort.oldestFirst => a.date.compareTo(b.date),
        _DebtsSort.highestAmountFirst =>
          b.outstandingBalance.compareTo(a.outstandingBalance),
      },
    );
    visible = [...activos, ...perdidas];

    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.payments_outlined,
        title: onlyOverdue ? 'Sin deudas vencidas' : 'Sin deudas activas',
        message: onlyOverdue
            ? 'Ningún cliente con plazo vencido en este momento.'
            : 'Cuando una venta procesada quede con saldo va a aparecer acá.',
      );
    }

    return Column(
      children: [
        if (overdueCount > 0)
          _OverdueBanner(
            count: overdueCount,
            onlyOverdue: onlyOverdue,
            onToggle: onOverdueToggled,
          ),
        _DebtsToolbar(sort: sort, onChanged: onSortChanged),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: visible.length,
            itemBuilder: (context, i) => _CashierSaleCard(
              sale: visible[i],
              onTap: () => context.push('/cashier/${visible[i].id}'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ClosedTab extends StatelessWidget {
  const _ClosedTab({
    required this.loading,
    required this.error,
    required this.sales,
  });

  final bool loading;
  final Object? error;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    if (loading && sales.isEmpty) return const SkeletonList();
    if (error != null) return AppErrorView(error: error!);
    if (sales.isEmpty) {
      return const EmptyState(
        icon: Icons.task_alt_outlined,
        title: 'Aún sin solicitudes cerradas',
        message: 'Las ventas pagadas o canceladas sin abonos van acá.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: sales.length,
      itemBuilder: (context, i) => _CashierSaleCard(
        sale: sales[i],
        onTap: () => context.push('/cashier/${sales[i].id}'),
      ),
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({
    required this.count,
    required this.onlyOverdue,
    required this.onToggle,
  });

  final int count;
  final bool onlyOverdue;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amber = theme.brightness == Brightness.dark
        ? const Color(0xFFFFC857)
        : const Color(0xFFE6A100);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tenés $count deuda${count == 1 ? '' : 's'} con plazo vencido.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          FilterChip(
            label: const Text('Solo vencidas'),
            selected: onlyOverdue,
            onSelected: onToggle,
          ),
        ],
      ),
    );
  }
}

class _DebtsToolbar extends StatelessWidget {
  const _DebtsToolbar({required this.sort, required this.onChanged});

  final _DebtsSort sort;
  final ValueChanged<_DebtsSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          const Icon(Icons.sort, size: 18),
          const SizedBox(width: 8),
          DropdownButton<_DebtsSort>(
            value: sort,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [
              DropdownMenuItem(
                value: _DebtsSort.oldestFirst,
                child: Text('Más antiguas primero'),
              ),
              DropdownMenuItem(
                value: _DebtsSort.highestAmountFirst,
                child: Text('Mayor saldo primero'),
              ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

/// Tarjeta especializada para los listados de caja. Muestra el estado
/// del workflow + el estado financiero en pills compactas para que el
/// cajero pueda escanear rápido sin abrir el detalle.
class _CashierSaleCard extends StatelessWidget {
  const _CashierSaleCard({required this.sale, required this.onTap});
  final Sale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final material = sale.materialVariant != null
        ? '${sale.material} · ${sale.materialVariant}'
        : sale.material;
    final isOverdue = sale.outstandingBalance > 0 &&
        sale.creditDueDate != null &&
        sale.creditDueDate!.isBefore(AppClock.now());
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      sale.consecutive,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatePillMini(state: sale.state),
                  const SizedBox(width: 6),
                  _FinancialPillMini(status: sale.financialStatus),
                  const Spacer(),
                  Text(
                    formatDate(sale.date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                sale.providerName,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                material,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 10),
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
                  Expanded(
                    child: _Metric(
                      label: 'Saldo',
                      value: formatCop(sale.outstandingBalance),
                      emphasized: sale.outstandingBalance > 0,
                    ),
                  ),
                ],
              ),
              if (isOverdue || sale.creditDueDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.event_busy_outlined,
                      size: 14,
                      color: isOverdue
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOverdue
                          ? 'Vencida el ${formatDate(sale.creditDueDate!)}'
                          : 'Plazo: ${formatDate(sale.creditDueDate!)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOverdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            color: emphasized ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _StatePillMini extends StatelessWidget {
  const _StatePillMini({required this.state});
  final SaleState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (state) {
      SaleState.generada => (const Color(0xFFE6A100), 'Generada'),
      SaleState.enProceso => (theme.colorScheme.primary, 'En proceso'),
      SaleState.procesada => (const Color(0xFF2E7D32), 'Procesada'),
      SaleState.cancelada => (
          theme.colorScheme.onSurface.withValues(alpha: 0.55),
          'Cancelada',
        ),
    };
    return _Pill(color: color, label: label);
  }
}

class _FinancialPillMini extends StatelessWidget {
  const _FinancialPillMini({required this.status});
  final SaleFinancialStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (status) {
      SaleFinancialStatus.pending => (
          theme.colorScheme.onSurface.withValues(alpha: 0.55),
          'Pendiente',
        ),
      SaleFinancialStatus.partiallyPaid => (
          const Color(0xFFE6A100),
          'Parcial',
        ),
      SaleFinancialStatus.paid => (const Color(0xFF2E7D32), 'Pagada'),
      SaleFinancialStatus.lost => (theme.colorScheme.error, 'Pérdida'),
    };
    return _Pill(color: color, label: label);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          fontSize: 10.5,
        ),
      ),
    );
  }
}
