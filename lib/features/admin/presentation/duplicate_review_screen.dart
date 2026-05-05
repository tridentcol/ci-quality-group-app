import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../data/duplicate_service.dart';
import '../data/master_lists_repository.dart';

/// Pantalla del admin para detectar y fusionar items duplicados de una
/// lista maestra. Se llega desde el botón "Detectar duplicados" en el
/// master_list_detail.
///
/// Flujo:
///   1. Al entrar, carga clusters via DuplicateService.findClusters.
///   2. Por cada cluster muestra una card con todos los items + radio
///      para elegir cuál es el canónico (default: el con más ventas).
///   3. El admin puede saltar clusters (toggle) o cambiar la selección.
///   4. "Aplicar" lanza un dialog de confirmación con totales y, si
///      confirma, ejecuta DuplicateService.applyMerges.
///   5. Snackbar con resumen + pop a la pantalla anterior.
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

  /// Cuántos items se trajeron de `sales` al catálogo durante este run.
  /// Lo mostramos en un banner informativo.
  int _backfilled = 0;

  /// Total de items en el catálogo después del backfill (incluye los
  /// recién agregados). Se usa en el header para dar contexto.
  int _totalCatalogItems = 0;

  /// Para cada cluster (clave = índice en `_clusters`):
  ///  - `canonicalId`: el item que el admin marcó como canónico
  ///  - `skipped`: si el cluster se ignora en este aplicar
  final Map<int, String> _canonicalSelection = {};
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
      final result =
          await ref.read(duplicateServiceProvider).findClusters(
                listId: widget.listId,
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
        // Refresca también el provider de items para que la lista
        // maestra muestre los recién importados.
        ref.invalidate(
          masterListItemsProvider(
            MasterListItemsQuery(listId: widget.listId),
          ),
        );
      }
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _activeClusterCount =>
      _clusters.length - _skipped.length;

  int get _totalItemsToDelete {
    var total = 0;
    for (var i = 0; i < _clusters.length; i++) {
      if (_skipped.contains(i)) continue;
      total += _clusters[i].items.length - 1; // todos menos el canónico
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
      title: 'Aplicar fusión de duplicados',
      message:
          'Se eliminarán $_totalItemsToDelete items del catálogo y '
          'se actualizarán $_totalSalesToUpdate ventas para que apunten '
          'al canónico de cada grupo.\n\n'
          'Esta operación no es reversible.',
      confirmLabel: 'Aplicar',
      icon: Icons.merge_type,
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
      // Invalida el provider de items para que la lista maestra se refresque.
      ref.invalidate(
        masterListItemsProvider(
          MasterListItemsQuery(listId: widget.listId),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.itemsDeleted} duplicados fusionados, '
            '${result.salesUpdated} ventas actualizadas.',
          ),
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
      body: Stack(
        children: [
          if (_loading)
            const _LoadingState()
          else if (_error != null)
            AppErrorView(error: _error!, onRetry: _detect)
          else
            ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: _clusters.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _SummaryHeader(
                    clusterCount: _clusters.length,
                    backfilled: _backfilled,
                    totalCatalogItems: _totalCatalogItems,
                  );
                }
                final idx = i - 1;
                final cluster = _clusters[idx];
                return _ClusterCard(
                  cluster: cluster,
                  canonicalId: _canonicalSelection[idx]!,
                  skipped: _skipped.contains(idx),
                  onCanonicalChanged: (id) =>
                      setState(() => _canonicalSelection[idx] = id),
                  onSkipChanged: (skipped) => setState(() {
                    if (skipped) {
                      _skipped.add(idx);
                    } else {
                      _skipped.remove(idx);
                    }
                  }),
                );
              },
            ),
          if (_applying)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.4),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: _clusters.isEmpty || _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_activeClusterCount grupo${_activeClusterCount == 1 ? '' : 's'}'
                            ' · $_totalItemsToDelete item${_totalItemsToDelete == 1 ? '' : 's'}'
                            ' · $_totalSalesToUpdate venta${_totalSalesToUpdate == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed:
                          _activeClusterCount == 0 || _applying ? null : _apply,
                      icon: const Icon(Icons.merge_type),
                      label: const Text('Aplicar'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.clusterCount,
    required this.backfilled,
    required this.totalCatalogItems,
  });
  final int clusterCount;
  final int backfilled;
  final int totalCatalogItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          if (backfilled > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                  Icon(
                    Icons.cloud_sync_outlined,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodySmall,
                        children: [
                          const TextSpan(text: 'Sincronizamos '),
                          TextSpan(
                            text: '$backfilled nombre${backfilled == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(
                            text: ' que aparecían en ventas pero no estaban en '
                                'el catálogo (la versión vieja de la app no '
                                'los registraba). Ahora hacen parte del listado.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    clusterCount == 0
                        ? 'No se detectaron duplicados en los $totalCatalogItems '
                            'items del catálogo.'
                        : 'Se detectaron $clusterCount grupo${clusterCount == 1 ? '' : 's'} '
                            'de posibles duplicados sobre $totalCatalogItems '
                            'items totales. Por cada uno, escoge cuál spelling '
                            'se queda como canónico — los otros se borran y '
                            'todas las ventas que los usen se actualizan.',
                    style: theme.textTheme.bodySmall,
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

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({
    required this.cluster,
    required this.canonicalId,
    required this.skipped,
    required this.onCanonicalChanged,
    required this.onSkipChanged,
  });

  final DuplicateCluster cluster;
  final String canonicalId;
  final bool skipped;
  final ValueChanged<String> onCanonicalChanged;
  final ValueChanged<bool> onSkipChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final salesAffected = cluster.totalSalesAffected(
      cluster.items.firstWhere(
        (it) => it.id == canonicalId,
        orElse: () => cluster.suggestedCanonical,
      ),
    );

    return Opacity(
      opacity: skipped ? 0.4 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Grupo de ${cluster.items.length} parecidos',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => onSkipChanged(!skipped),
                    icon: Icon(
                      skipped ? Icons.refresh : Icons.close,
                      size: 16,
                    ),
                    label: Text(skipped ? 'Reactivar' : 'Saltar'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (!skipped)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    '$salesAffected venta${salesAffected == 1 ? '' : 's'} se '
                    'actualizará${salesAffected == 1 ? '' : 'n'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: canonicalId,
                onChanged: skipped
                    ? null
                    : (v) {
                        if (v != null) onCanonicalChanged(v);
                      },
                child: Column(
                  children: [
                    for (final item in cluster.items)
                      RadioListTile<String>(
                        value: item.id,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.value,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: item.id == canonicalId
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _RefBadge(count: cluster.refCounts[item.value] ?? 0),
                          ],
                        ),
                        subtitle: item.userSuggested
                            ? Text(
                                'Sugerencia sin formalizar',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefBadge extends StatelessWidget {
  const _RefBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = count == 0
        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count == 1 ? '1 venta' : '$count ventas',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Buscando duplicados…'),
          SizedBox(height: 4),
          Text(
            'Comparando items + contando referencias en ventas',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

