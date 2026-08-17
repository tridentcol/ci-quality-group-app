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

/// Dashboard de gerencia del control de material: totales del rango,
/// desglosados en ingreso y salida por separado (ambos independientes
/// de `sales`), con breakdown por empresa y por material en cada uno.
/// Mismos KPIs que dijo Carlos que necesitaba: "hoy entró tanto, salió
/// tanto, tanto por empresa".
class MaterialAdminScreen extends ConsumerStatefulWidget {
  const MaterialAdminScreen({super.key});

  @override
  ConsumerState<MaterialAdminScreen> createState() =>
      _MaterialAdminScreenState();
}

class _MaterialAdminScreenState extends ConsumerState<MaterialAdminScreen> {
  late DateTime _start;
  late DateTime _end;

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
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    _MaterialSection(
                      title: 'Ingresos',
                      counterpartyLabel: 'Proveedor',
                      metrics: MaterialMetrics.compute(ingresoEntries),
                      entries: ingresoEntries,
                      accent: const Color(0xFF2E7D32),
                    ),
                    const SizedBox(height: 28),
                    _MaterialSection(
                      title: 'Salidas',
                      counterpartyLabel: 'Cliente',
                      metrics: MaterialMetrics.compute(salidaEntries),
                      entries: salidaEntries,
                      accent: AppColors.warning,
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
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
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
          KpiRow(cards: [
            KpiCard(
              label: 'Total',
              value: formatQuantity(metrics.totalQuantity),
              subtitle: metrics.commonUnit != null
                  ? '${metrics.commonUnit} en el rango'
                  : 'en el rango (unidades mixtas)',
              icon: Icons.scale_outlined,
              color: accent,
            ),
            KpiCard(
              label: title,
              value: '${metrics.entryCount}',
              subtitle: 'registros',
              icon: Icons.inventory_2_outlined,
              color: accent,
            ),
          ],),
          const SizedBox(height: 16),
          _SectionLabel('Por $counterpartyLabel'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final c in metrics.topCompanies)
                  ListTile(
                    title: Text(c.name),
                    subtitle: Text('${c.count} registro${c.count == 1 ? '' : 's'}'),
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
