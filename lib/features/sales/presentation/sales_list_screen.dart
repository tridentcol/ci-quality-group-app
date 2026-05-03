import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
          SnackBar(content: Text('Error al exportar: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          _RangeAndStats(sales: sales.valueOrNull ?? const []),
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
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(salesByRangeProvider(
                SalesDateRange(start: _start, end: _end),
              )),
              child: sales.when(
                loading: () => const SkeletonList(),
                error: (e, _) => AppErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(salesByRangeProvider(
                    SalesDateRange(start: _start, end: _end),
                  )),
                ),
                data: (data) {
                  final q = _query;
                  final filtered = q.isEmpty
                      ? data
                      : data.where((s) {
                          return s.consecutive.toLowerCase().contains(q) ||
                              s.providerName.toLowerCase().contains(q) ||
                              s.material.toLowerCase().contains(q) ||
                              (s.materialVariant ?? '')
                                  .toLowerCase()
                                  .contains(q) ||
                              s.payerName.toLowerCase().contains(q);
                        }).toList();

                  if (filtered.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: data.isEmpty
                              ? 'Sin ventas en el rango'
                              : 'Sin coincidencias',
                          message: data.isEmpty
                              ? 'Cambia el rango o registra una nueva venta.'
                              : 'Prueba con otra palabra clave.',
                        ),
                      ],
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
          ),
        ],
      ),
    );
  }
}

class _RangeAndStats extends StatelessWidget {
  const _RangeAndStats({required this.sales});

  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final total = sales.fold<num>(0, (sum, s) => sum + s.totalValue);
    return HeroBanner(
      title: 'Total del rango',
      primaryValue: formatCop(total),
      secondary: '${sales.length} venta${sales.length == 1 ? '' : 's'}',
    );
  }
}
