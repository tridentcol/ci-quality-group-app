import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../data/duplicate_service.dart';
import '../data/master_lists_repository.dart';
import '../domain/master_list.dart';

/// Pantalla del admin para detectar y fusionar items duplicados de una
/// lista maestra.
///
/// Flujo (todo guiado):
///   1. Al entrar, sincroniza catálogo desde sales (backfill) + detecta
///      clusters de items parecidos.
///   2. Banner verde si hubo sincronización (con contador).
///   3. Banner azul con totales de detección.
///   4. Una card por grupo: header con "Grupo X" + ventas afectadas,
///      cuerpo con cada item + radio + badge de uso, footer con "Saltar".
///   5. Footer fijo con resumen + botón "Aplicar".
///   6. Al aplicar: confirmación → merge → snackbar → pop.
class DuplicateReviewScreen extends ConsumerStatefulWidget {
  const DuplicateReviewScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<DuplicateReviewScreen> createState() =>
      _DuplicateReviewScreenState();
}

class _DuplicateReviewScreenState extends ConsumerState<DuplicateReviewScreen> {
  bool _loading = true;
  Object? _error;
  List<DuplicateCluster> _clusters = const [];
  int _backfilled = 0;
  int _totalCatalogItems = 0;

  /// canonicalId por cluster (índice en `_clusters`).
  final Map<int, String> _canonicalSelection = {};

  /// Clusters marcados como "no son duplicados" (saltar al aplicar).
  final Set<int> _skipped = {};

  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(duplicateServiceProvider)
          .findClusters(listId: widget.listId)
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () => throw 'Tomó demasiado tiempo (>90s). '
                'Probablemente la lista tiene muchos items o la red '
                'está lenta. Intenta de nuevo.',
          );
      _clusters = result.clusters;
      _backfilled = result.backfilled;
      _totalCatalogItems = result.totalCatalogItems;
      _canonicalSelection.clear();
      _skipped.clear();
      for (var i = 0; i < _clusters.length; i++) {
        _canonicalSelection[i] = _clusters[i].suggestedCanonical.id;
      }
      if (_backfilled > 0 && mounted) {
        ref.invalidate(
          masterListItemsProvider(
            MasterListItemsQuery(listId: widget.listId),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('DuplicateReviewScreen._detect error: $e\n$st');
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _activeClusterCount => _clusters.length - _skipped.length;

  int get _totalItemsToDelete {
    var total = 0;
    for (var i = 0; i < _clusters.length; i++) {
      if (_skipped.contains(i)) continue;
      total += _clusters[i].items.length - 1;
    }
    return total;
  }

  int get _totalSalesToUpdate {
    var total = 0;
    for (var i = 0; i < _clusters.length; i++) {
      if (_skipped.contains(i)) continue;
      final cluster = _clusters[i];
      final canonicalId = _canonicalSelection[i];
      final canonical = cluster.items.firstWhere(
        (it) => it.id == canonicalId,
        orElse: () => cluster.suggestedCanonical,
      );
      total += cluster.totalSalesAffected(canonical);
    }
    return total;
  }

  Future<void> _apply() async {
    if (_activeClusterCount == 0) return;

    final ok = await showConfirmDialog(
      context,
      title: 'Aplicar fusión',
      message:
          'Se van a fusionar $_totalItemsToDelete duplicado'
          '${_totalItemsToDelete == 1 ? '' : 's'} en '
          '$_activeClusterCount grupo'
          '${_activeClusterCount == 1 ? '' : 's'}.\n\n'
          '$_totalSalesToUpdate venta'
          '${_totalSalesToUpdate == 1 ? '' : 's'} se actualizará'
          '${_totalSalesToUpdate == 1 ? '' : 'n'} para apuntar a los '
          'nombres canónicos.\n\n'
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Aplicar',
      icon: Icons.call_merge,
    );
    if (!ok) return;

    setState(() => _applying = true);
    try {
      final requests = <DuplicateMergeRequest>[];
      for (var i = 0; i < _clusters.length; i++) {
        if (_skipped.contains(i)) continue;
        final cluster = _clusters[i];
        final canonicalId = _canonicalSelection[i];
        final canonical = cluster.items.firstWhere(
          (it) => it.id == canonicalId,
          orElse: () => cluster.suggestedCanonical,
        );
        final duplicates =
            cluster.items.where((it) => it.id != canonical.id).toList();
        if (duplicates.isEmpty) continue;
        requests.add(
          DuplicateMergeRequest(
            canonical: canonical,
            duplicates: duplicates,
          ),
        );
      }

      final result =
          await ref.read(duplicateServiceProvider).applyMerges(
                listId: widget.listId,
                requests: requests,
              );

      if (!mounted) return;
      // Refresca el catálogo abierto detrás (la lista maestra).
      ref.invalidate(
        masterListItemsProvider(
          MasterListItemsQuery(listId: widget.listId),
        ),
      );
      // Los providers de sales son StreamProviders que escuchan a
      // Firestore directo: las actualizaciones de los documentos de
      // sales (que el merge acaba de hacer) se propagan solas a las
      // métricas, listas, etc. No hace falta invalidar manualmente.

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ ${result.itemsDeleted} duplicado'
            '${result.itemsDeleted == 1 ? '' : 's'} fusionado'
            '${result.itemsDeleted == 1 ? '' : 's'} · '
            '${result.salesUpdated} venta'
            '${result.salesUpdated == 1 ? '' : 's'} actualizada'
            '${result.salesUpdated == 1 ? '' : 's'}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = ref.watch(masterListMetaProvider(widget.listId));
    final theme = Theme.of(context);
    final hasResults = _clusters.isNotEmpty;
    final hasSyncOnly = !hasResults && _backfilled > 0;
    final hasNothing = !hasResults && _backfilled == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Duplicados — ${meta.valueOrNull?.name ?? widget.listId}'),
        actions: [
          IconButton(
            tooltip: 'Detectar de nuevo',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _detect,
          ),
          const ThemeModeIconButton(),
        ],
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loading)
              _LoadingState(theme: theme)
            else if (_error != null)
              AppErrorView(error: _error!, onRetry: _detect)
            else if (hasNothing)
              _NothingFoundState(theme: theme, totalItems: _totalCatalogItems)
            else
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (_backfilled > 0)
                    _SyncBanner(
                      backfilled: _backfilled,
                      totalCatalogItems: _totalCatalogItems,
                    ),
                  if (_backfilled > 0 && hasResults)
                    const SizedBox(height: 12),
                  if (hasResults)
                    _DetectionBanner(
                      clusterCount: _clusters.length,
                      totalCatalogItems: _totalCatalogItems,
                    ),
                  if (hasSyncOnly)
                    _AllCleanBanner(theme: theme),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _clusters.length; i++) ...[
                    _ClusterCard(
                      number: i + 1,
                      cluster: _clusters[i],
                      canonicalId: _canonicalSelection[i]!,
                      skipped: _skipped.contains(i),
                      onCanonicalChanged: (id) =>
                          setState(() => _canonicalSelection[i] = id),
                      onSkipChanged: (skipped) => setState(() {
                        if (skipped) {
                          _skipped.add(i);
                        } else {
                          _skipped.remove(i);
                        }
                      }),
                    ),
                    if (i < _clusters.length - 1) const SizedBox(height: 16),
                  ],
                ],
              ),
            if (_applying)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            'Aplicando fusión…',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: hasResults && !_loading
          ? _ApplyFooter(
              activeClusters: _activeClusterCount,
              itemsToDelete: _totalItemsToDelete,
              salesToUpdate: _totalSalesToUpdate,
              onApply: _applying ? null : _apply,
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Banners de estado (sync, detección, nothing, all-clean)
// ─────────────────────────────────────────────────────────────────────

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({
    required this.backfilled,
    required this.totalCatalogItems,
  });
  final int backfilled;
  final int totalCatalogItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_done_outlined, color: theme.colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'Importamos '),
                  TextSpan(
                    text: '$backfilled nombre${backfilled == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: ' que estaban en ventas pero faltaban en el '
                        'catálogo. Ya hacen parte de los dropdowns y '
                        'sugerencias.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionBanner extends StatelessWidget {
  const _DetectionBanner({
    required this.clusterCount,
    required this.totalCatalogItems,
  });
  final int clusterCount;
  final int totalCatalogItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$clusterCount grupo${clusterCount == 1 ? '' : 's'} '
                  'de posibles duplicados',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sobre $totalCatalogItems items en el catálogo. Por cada '
                  'grupo, escoge la versión que se queda; las demás se '
                  'borran y todas las ventas que las usen se actualizan al '
                  'canónico. Si crees que un grupo NO es realmente '
                  'duplicado, márcalo como "Saltar".',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AllCleanBanner extends StatelessWidget {
  const _AllCleanBanner({required this.theme});
  final ThemeData theme;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No se detectaron duplicados en el catálogo. '
              'Todo el listado parece consistente.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingFoundState extends StatelessWidget {
  const _NothingFoundState({required this.theme, required this.totalItems});
  final ThemeData theme;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Catálogo limpio',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              totalItems == 0
                  ? 'La lista está vacía y no hay nombres pendientes en '
                      'ventas que importar.'
                  : 'Revisamos los $totalItems items del catálogo y todos '
                      'los nombres de ventas. No detectamos duplicados.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Card de cluster
// ─────────────────────────────────────────────────────────────────────

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({
    required this.number,
    required this.cluster,
    required this.canonicalId,
    required this.skipped,
    required this.onCanonicalChanged,
    required this.onSkipChanged,
  });

  final int number;
  final DuplicateCluster cluster;
  final String canonicalId;
  final bool skipped;
  final ValueChanged<String> onCanonicalChanged;
  final ValueChanged<bool> onSkipChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canonical = cluster.items.firstWhere(
      (it) => it.id == canonicalId,
      orElse: () => cluster.suggestedCanonical,
    );
    final salesAffected = cluster.totalSalesAffected(canonical);

    return Opacity(
      opacity: skipped ? 0.4 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: número + impacto
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$number',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grupo de ${cluster.items.length} parecidos',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!skipped && salesAffected > 0)
                          Text(
                            '$salesAffected venta'
                            '${salesAffected == 1 ? '' : 's'} '
                            'se actualizará'
                            '${salesAffected == 1 ? '' : 'n'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          )
                        else if (skipped)
                          Text(
                            'Marcado como NO duplicado',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body: items con radio
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: RadioGroup<String>(
                groupValue: canonicalId,
                onChanged: (v) {
                  if (v != null) onCanonicalChanged(v);
                },
                child: Column(
                  children: [
                    for (final item in cluster.items)
                      _ItemRow(
                        item: item,
                        isCanonical: item.id == canonicalId,
                        refCount: cluster.refCounts[item.value] ?? 0,
                      ),
                  ],
                ),
              ),
            ),
            // Footer: skip toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onSkipChanged(!skipped),
                  icon: Icon(
                    skipped ? Icons.refresh : Icons.block,
                    size: 16,
                  ),
                  label: Text(
                    skipped
                        ? 'Reactivar grupo'
                        : 'No son duplicados — saltar',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: skipped
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.isCanonical,
    required this.refCount,
  });
  final MasterListItem item;
  final bool isCanonical;
  final int refCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isCanonical
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RadioListTile<String>(
        value: item.id,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        dense: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight:
                      isCanonical ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RefBadge(count: refCount, highlighted: isCanonical),
          ],
        ),
        subtitle: item.userSuggested
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Importada de una venta · sin formalizar',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _RefBadge extends StatelessWidget {
  const _RefBadge({required this.count, required this.highlighted});
  final int count;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = count == 0
        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: highlighted ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count == 1 ? '1 venta' : '$count ventas',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Footer fijo con totales + botón Aplicar
// ─────────────────────────────────────────────────────────────────────

class _ApplyFooter extends StatelessWidget {
  const _ApplyFooter({
    required this.activeClusters,
    required this.itemsToDelete,
    required this.salesToUpdate,
    required this.onApply,
  });

  final int activeClusters;
  final int itemsToDelete;
  final int salesToUpdate;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Stat(
                    label: 'Grupos',
                    value: '$activeClusters',
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  _Stat(
                    label: 'Items a borrar',
                    value: '$itemsToDelete',
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  _Stat(
                    label: 'Ventas afectadas',
                    value: '$salesToUpdate',
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: activeClusters == 0 ? null : onApply,
                icon: const Icon(Icons.call_merge),
                label: Text(
                  activeClusters == 0
                      ? 'Nada que aplicar'
                      : 'Aplicar fusión',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 24),
            Text(
              'Sincronizando catálogo y buscando duplicados…',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Importando nombres de ventas + comparando spelling',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
