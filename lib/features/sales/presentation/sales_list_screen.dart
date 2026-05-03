import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/services/xlsx_export_service.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import 'widgets/sale_card.dart';

/// Listado de ventas con filtros por rango de fechas, métricas y exportación.
/// Disponible para el admin (también lo reusan otros roles con el rango oculto).
class SalesListScreen extends ConsumerStatefulWidget {
  const SalesListScreen({super.key, this.allowExport = true});

  final bool allowExport;

  @override
  ConsumerState<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends ConsumerState<SalesListScreen> {
  late DateTime _start;
  late DateTime _end;
  String _query = '';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  Future<void> _export(List<Sale> sales) async {
    if (sales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay ventas en el rango seleccionado.')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      await XlsxExportService.exportSales(
        sales: sales,
        rangeStart: _start,
        rangeEnd: _end,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sales = ref.watch(
      salesByRangeProvider(SalesDateRange(start: _start, end: _end)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas'),
        actions: [
          if (widget.allowExport)
            IconButton(
              tooltip: 'Exportar a Excel (rango actual)',
              onPressed: _exporting
                  ? null
                  : () => _export(sales.valueOrNull ?? const []),
              icon: _exporting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sales/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva venta'),
      ),
      body: Column(
        children: [
          _RangeAndStats(
            start: _start,
            end: _end,
            sales: sales.valueOrNull ?? const [],
          ),
          RangeFilterBar(
            start: _start,
            end: _end,
            onChanged: (r) => setState(() {
              _start = r.start;
              _end = r.end;
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por consecutivo, cliente, material…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: sales.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $e', style: TextStyle(color: theme.colorScheme.error)),
              ),
              data: (data) {
                final filtered = _query.isEmpty
                    ? data
                    : data.where((s) =>
                        s.consecutive.toLowerCase().contains(_query) ||
                        s.providerName.toLowerCase().contains(_query) ||
                        s.material.toLowerCase().contains(_query) ||
                        (s.materialVariant ?? '').toLowerCase().contains(_query) ||
                        s.payerName.toLowerCase().contains(_query)).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        data.isEmpty
                            ? 'No hay ventas en este rango.'
                            : 'No hay ventas que coincidan con la búsqueda.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final sale = filtered[i];
                    return SaleCard(
                      sale: sale,
                      onTap: () => context.push('/sales/${sale.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeAndStats extends StatelessWidget {
  const _RangeAndStats({
    required this.start,
    required this.end,
    required this.sales,
  });

  final DateTime start;
  final DateTime end;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = sales.fold<num>(0, (sum, s) => sum + s.totalValue);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total del rango',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatCop(total),
              style:
                  theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${sales.length} venta${sales.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
