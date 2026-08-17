import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/kpi_card.dart';
import '../../../shared/widgets/range_filter_bar.dart';
import '../../material/data/material_entries_repository.dart';
import '../../material/data/material_metrics.dart';
import '../../material/domain/material_entry.dart';
import '../../material/presentation/widgets/material_entry_card.dart';
import 'admin_shell.dart';

enum _MaterialView { ingresos, salidas }

/// Dashboard de gerencia del control de material: totales del rango,
/// desglosados en ingreso y salida por separado (ambos independientes
/// de `sales`). Arriba siempre se ve el comparativo "entró vs. salió"
/// (lo que pidió Carlos: "de un vistazo"); abajo un SegmentedButton
/// (mismo patrón que `AdminMetricsScreen` para Ventas/Horas) muestra
/// el detalle — breakdown por empresa, por material y el feed de
/// movimientos — de uno solo a la vez en vez de apilar ambos.
class MaterialAdminScreen extends ConsumerStatefulWidget {
  const MaterialAdminScreen({super.key});

  @override
  ConsumerState<MaterialAdminScreen> createState() =>
      _MaterialAdminScreenState();
}

class _MaterialAdminScreenState extends ConsumerState<MaterialAdminScreen> {
  late DateTime _start;
  late DateTime _end;
  _MaterialView _view = _MaterialView.ingresos;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    _start = startOfMonth(now);
    _end = endOfMonth(now);
  }

  Future<void> _openRegisterSheet(BuildContext context) async {
    final type = await showModalBottomSheet<MaterialMovementType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_received_outlined),
              title: const Text('Registrar ingreso'),
              onTap: () => Navigator.pop(ctx, MaterialMovementType.ingreso),
            ),
            ListTile(
              leading: const Icon(Icons.call_made_outlined),
              title: const Text('Registrar salida'),
              onTap: () => Navigator.pop(ctx, MaterialMovementType.salida),
            ),
          ],
        ),
      ),
    );
    if (type != null && context.mounted) {
      context.push('/material/new', extra: type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = MaterialDateRange(start: _start, end: _end);
    final entriesAsync = ref.watch(materialEntriesByRangeProvider(range));

    return Scaffold(
      drawer: adminDrawerOrNull(context, '/admin/material'),
      appBar: AppBar(title: const Text('Control de material')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRegisterSheet(context),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Registrar movimiento'),
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
            child: entriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorView(error: e),
              data: (entries) {
                final ingresoEntries = entries
                    .where((e) => e.type == MaterialMovementType.ingreso)
                    .toList();
                final salidaEntries = entries
                    .where((e) => e.type == MaterialMovementType.salida)
                    .toList();
                final ingresoMetrics = MaterialMetrics.compute(ingresoEntries);
                final salidaMetrics = MaterialMetrics.compute(salidaEntries);
                const ingresoColor = Color(0xFF2E7D32);
                const salidaColor = AppColors.warning;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    KpiRow(
                      cards: [
                        KpiCard(
                          label: 'Entró',
                          value: formatQuantity(ingresoMetrics.totalQuantity),
                          subtitle: ingresoMetrics.commonUnit != null
                              ? '${ingresoMetrics.commonUnit} · ${ingresoMetrics.entryCount} registros'
                              : '${ingresoMetrics.entryCount} registros',
                          icon: Icons.call_received_outlined,
                          color: ingresoColor,
                          onTap: () => setState(
                            () => _view = _MaterialView.ingresos,
                          ),
                        ),
                        KpiCard(
                          label: 'Salió',
                          value: formatQuantity(salidaMetrics.totalQuantity),
                          subtitle: salidaMetrics.commonUnit != null
                              ? '${salidaMetrics.commonUnit} · ${salidaMetrics.entryCount} registros'
                              : '${salidaMetrics.entryCount} registros',
                          icon: Icons.call_made_outlined,
                          color: salidaColor,
                          onTap: () => setState(
                            () => _view = _MaterialView.salidas,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_MaterialView>(
                        segments: const [
                          ButtonSegment(
                            value: _MaterialView.ingresos,
                            label: Text('Ingresos'),
                            icon: Icon(Icons.call_received_outlined),
                          ),
                          ButtonSegment(
                            value: _MaterialView.salidas,
                            label: Text('Salidas'),
                            icon: Icon(Icons.call_made_outlined),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (s) =>
                            setState(() => _view = s.first),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_view == _MaterialView.ingresos)
                      _MaterialSection(
                        title: 'Ingresos',
                        counterpartyLabel: 'Proveedor',
                        metrics: ingresoMetrics,
                        entries: ingresoEntries,
                        accent: ingresoColor,
                      )
                    else
                      _MaterialSection(
                        title: 'Salidas',
                        counterpartyLabel: 'Cliente',
                        metrics: salidaMetrics,
                        entries: salidaEntries,
                        accent: salidaColor,
                      ),
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

class _MaterialSection extends StatelessWidget {
  const _MaterialSection({
    required this.title,
    required this.counterpartyLabel,
    required this.metrics,
    required this.entries,
    required this.accent,
  });

  final String title;
  final String counterpartyLabel;
  final MaterialMetrics metrics;

  /// Movimientos individuales del rango — mismos que ve `hours` en
  /// `/material`, con foto. Admin necesita poder entrar al detalle de
  /// cada uno, no solo ver los totales agregados.
  final List<MaterialEntry> entries;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (metrics.entryCount == 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Sin ${title.toLowerCase()} en el rango.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          )
        else ...[
          _SectionLabel('Por $counterpartyLabel'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final c in metrics.topCompanies)
                  ListTile(
                    title: Text(c.name),
                    subtitle:
                        Text('${c.count} registro${c.count == 1 ? '' : 's'}'),
                    trailing: Text(
                      _formatWithUnit(c.quantity, metrics.commonUnit),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Por material'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final entry in metrics.byMaterial.entries)
                  ListTile(
                    title: Text(entry.key),
                    trailing: Text(
                      _formatWithUnit(entry.value, metrics.commonUnit),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Movimientos ($title)'),
          const SizedBox(height: 8),
          for (final entry in entries) ...[
            MaterialEntryCard(
              entry: entry,
              onTap: () => context.push('/material/${entry.id}'),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

/// `unit` puede ser `null` si el rango mezcla unidades distintas (hoy
/// no pasa — la única lista maestra de unidades tiene "Kilogramos" —
/// pero si el admin agrega otra, esto evita ponerle un sufijo
/// incorrecto en vez de mentir con "kg" fijo.
String _formatWithUnit(num value, String? unit) {
  final formatted = formatQuantity(value);
  return unit == null ? formatted : '$formatted $unit';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          ),
    );
  }
}
