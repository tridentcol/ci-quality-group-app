import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/services/xlsx_export_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/hero_banner.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../auth/data/auth_repository.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import 'widgets/expense_card.dart';

/// Gastos de bodega del rango seleccionado (por defecto el mes natural).
/// La ven admin, cajero y hours.
class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> {
  late DateTime _start;
  late DateTime _end;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  Future<void> _export(List<Expense> expenses) async {
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay gastos en el rango.')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      await XlsxExportService.exportExpenses(
        context: context,
        expenses: expenses,
        rangeStart: _start,
        rangeEnd: _end,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(
      currentProfileProvider.select((p) => p.valueOrNull?.role == AppRole.admin),
    );
    final range = ExpensesDateRange(start: _start, end: _end);
    final expensesAsync = ref.watch(expensesByRangeProvider(range));
    final expenses = expensesAsync.valueOrNull ?? const [];
    final total = expenses.fold<num>(0, (sum, e) => sum + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos de bodega'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Exportar a Excel (rango actual)',
              onPressed: _exporting ? null : () => _export(expenses),
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo gasto'),
      ),
      body: Column(
        children: [
          HeroBanner(
            title: 'Total del rango',
            primaryValue: formatCop(total),
            secondary:
                '${expenses.length} ${expenses.length == 1 ? 'gasto' : 'gastos'}',
            icon: Icons.receipt_long_outlined,
          ),
          RangeFilterBar(
            start: _start,
            end: _end,
            onChanged: (r) => setState(() {
              _start = r.start;
              _end = r.end;
            }),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(expensesByRangeProvider(range)),
              child: expensesAsync.when(
                loading: () => const SkeletonList(),
                error: (e, _) => AppErrorView(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(expensesByRangeProvider(range)),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Sin gastos en este rango',
                          message: 'Toca "Nuevo gasto" para registrar el primero.',
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => ExpenseCard(
                      expense: list[i],
                      onTap: () => context.push('/expenses/${list[i].id}'),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
