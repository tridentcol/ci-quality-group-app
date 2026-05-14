import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../data/duplicate_service.dart';
import '../data/master_lists_repository.dart';
import '../domain/master_list.dart';

/// IDs de listas cuyos items pertenecen a un material padre. El admin
/// edita estas listas con un picker adicional de "material padre" y los
/// items muestran el padre como subtítulo.
///
/// Por ahora solo `lamina_brands` (renombrada a "Tipos de materiales"
/// en el display) tiene esta semántica — sus items son subtipos que
/// aplican a un material principal específico.
const Set<String> _listsWithParentPicker = {'lamina_brands'};

/// El listId de donde se sacan las opciones del picker de padre cuando
/// `_listsWithParentPicker` contiene el listId actual.
const String _parentSourceListId = 'materials';

class MasterListDetailScreen extends ConsumerStatefulWidget {
  const MasterListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<MasterListDetailScreen> createState() =>
      _MasterListDetailScreenState();
}

class _MasterListDetailScreenState
    extends ConsumerState<MasterListDetailScreen> {
  /// Cuando está en `true`, cada item muestra un checkbox y el FAB se
  /// reemplaza por la barra inferior de fusión manual. El admin sale del
  /// modo con la X del AppBar o aplicando.
  bool _selecting = false;

  /// Ids de items marcados para fusionar.
  final Set<String> _selectedIds = {};

  bool _merging = false;

  String get _listId => widget.listId;
  bool get _hasParentPicker => _listsWithParentPicker.contains(_listId);

  /// Carga la lista de materiales para usar como opciones del picker
  /// de parent. Se hace por demanda (al abrir el dialog) en lugar de
  /// watch en el build, para no causar rebuilds extra.
  Future<List<String>> _loadParentOptions() async {
    if (!_hasParentPicker) return const [];
    final items = await ref
        .read(masterListsRepositoryProvider)
        .fetchItemsOnce(_parentSourceListId);
    return items.map((it) => it.value).toList();
  }

  Future<void> _addItem() async {
    final parentOptions = await _loadParentOptions();
    if (!mounted) return;
    final result = await _promptItem(
      context,
      title: 'Nueva opción',
      parentOptions: parentOptions,
      parentLabel: 'Material padre',
    );
    if (result == null || result.value.isEmpty) return;
    try {
      await ref.read(masterListsRepositoryProvider).addItem(
            _listId,
            value: result.value,
            parent: result.parent,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _editItem(MasterListItem item) async {
    final parentOptions = await _loadParentOptions();
    if (!mounted) return;
    final result = await _promptItem(
      context,
      title: 'Editar opción',
      initialValue: item.value,
      initialParent: item.parent,
      parentOptions: parentOptions,
      parentLabel: 'Material padre',
    );
    if (result == null || result.value.isEmpty) return;

    final valueChanged = result.value != item.value;
    final parentChanged = result.parent != item.parent;
    if (!valueChanged && !parentChanged) return;

    try {
      if (parentChanged) {
        await ref.read(masterListsRepositoryProvider).updateItem(
              _listId,
              item.id,
              parent: result.parent,
            );
      }
      var salesUpdated = 0;
      if (valueChanged) {
        salesUpdated =
            await ref.read(masterListsRepositoryProvider).renameItem(
                  listId: _listId,
                  itemId: item.id,
                  oldValue: item.value,
                  newValue: result.value,
                );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _buildEditSuccessMessage(
                valueChanged: valueChanged,
                parentChanged: parentChanged,
                salesUpdated: salesUpdated,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  String _buildEditSuccessMessage({
    required bool valueChanged,
    required bool parentChanged,
    required int salesUpdated,
  }) {
    if (valueChanged && salesUpdated > 0) {
      return '✓ Nombre actualizado · $salesUpdated venta'
          '${salesUpdated == 1 ? '' : 's'} históricas '
          'actualizadas al nuevo nombre';
    }
    if (valueChanged) return 'Nombre actualizado.';
    if (parentChanged) return 'Material padre actualizado.';
    return 'Sin cambios.';
  }

  Future<void> _deleteItem(MasterListItem item) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Eliminar opción',
      message:
          'Se eliminará "${item.value}" de la lista. Las ventas o registros '
          'que ya la usen no se verán afectados.',
      confirmLabel: 'Eliminar',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    try {
      await ref.read(masterListsRepositoryProvider).deleteItem(_listId, item.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _approveSuggestion(MasterListItem item) async {
    await ref.read(masterListsRepositoryProvider).updateItem(
          _listId,
          item.id,
          userSuggested: false,
        );
  }

  void _enterSelecting() {
    setState(() {
      _selecting = true;
      _selectedIds.clear();
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _mergeSelected(List<MasterListItem> allItems) async {
    if (_selectedIds.length < 2) return;
    final selected =
        allItems.where((it) => _selectedIds.contains(it.id)).toList();

    final canonical = await _pickCanonical(context, selected);
    if (canonical == null || !mounted) return;

    final duplicates =
        selected.where((it) => it.id != canonical.id).toList();
    final dupNames = duplicates.map((d) => '"${d.value}"').join(', ');

    final ok = await showConfirmDialog(
      context,
      title: 'Fusionar manualmente',
      message: 'Unir $dupNames en "${canonical.value}". '
          'Las ventas que usaban esos nombres pasarán al canónico y los '
          'items duplicados se eliminan del catálogo.\n\n'
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Fusionar',
      icon: Icons.compress,
    );
    if (!ok || !mounted) return;

    setState(() => _merging = true);
    try {
      final result = await ref.read(duplicateServiceProvider).applyMerges(
        listId: _listId,
        requests: [
          DuplicateMergeRequest(
            canonical: canonical,
            duplicates: duplicates,
          ),
        ],
      );
      if (!mounted) return;
      // Refresca catálogo. Los providers de sales son streams y se
      // actualizan solos cuando los docs cambian.
      ref.invalidate(
        masterListItemsProvider(MasterListItemsQuery(listId: _listId)),
      );
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
      _exitSelecting();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(
      masterListItemsProvider(MasterListItemsQuery(listId: _listId)),
    );
    final meta = ref.watch(masterListMetaProvider(_listId));
    final supportsMerge = listSupportsMerge(_listId);
    final theme = Theme.of(context);

    final itemsList = items.valueOrNull ?? const <MasterListItem>[];

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Salir del modo selección',
                onPressed: _merging ? null : _exitSelecting,
              )
            : null,
        title: Text(
          _selecting
              ? '${_selectedIds.length} seleccionado'
                  '${_selectedIds.length == 1 ? '' : 's'}'
              : meta.valueOrNull?.name ?? 'Lista maestra',
        ),
        actions: _selecting
            ? const [ThemeModeIconButton()]
            : [
                if (supportsMerge) ...[
                  IconButton(
                    tooltip: 'Fusionar manualmente',
                    icon: const Icon(Icons.checklist_outlined),
                    onPressed: itemsList.length < 2 ? null : _enterSelecting,
                  ),
                  IconButton(
                    tooltip: 'Detectar y fusionar duplicados',
                    icon: const Icon(Icons.compress),
                    onPressed: () => context
                        .push('/admin/master-lists/$_listId/duplicates'),
                  ),
                ],
                const ThemeModeIconButton(),
              ],
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
      bottomNavigationBar: _selecting
          ? _ManualMergeBar(
              count: _selectedIds.length,
              busy: _merging,
              onApply: () => _mergeSelected(itemsList),
            )
          : null,
      body: items.when(
        loading: () => const SkeletonList(),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(
            masterListItemsProvider(MasterListItemsQuery(listId: _listId)),
          ),
        ),
        data: (data) {
          if (data.isEmpty) {
            return EmptyState(
              icon: Icons.list_alt_outlined,
              title: 'Lista vacía',
              message: 'Esta lista no tiene opciones todavía.',
              actionLabel: 'Agregar primera opción',
              onAction: _addItem,
            );
          }
          return Column(
            children: [
              if (_selecting && _selectedIds.length < 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _SelectingHint(theme: theme),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: data.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = data[i];
                    return _ItemCard(
                      item: item,
                      showParent: _hasParentPicker,
                      selecting: _selecting,
                      selected: _selectedIds.contains(item.id),
                      onTap: _selecting ? () => _toggleSelect(item.id) : null,
                      onApprove: () => _approveSuggestion(item),
                      onEdit: () => _editItem(item),
                      onDelete: () => _deleteItem(item),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Card de un item. En modo normal expone las acciones (aprobar / editar
/// / eliminar) en un popup menu. En modo selección, muestra un checkbox
/// al frente y oculta el menú — todo el tile actúa como toggle.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.showParent,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onApprove,
    required this.onEdit,
    required this.onDelete,
  });

  final MasterListItem item;
  final bool showParent;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <Widget>[];
    if (showParent) {
      subtitleParts.add(
        Row(
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 4),
            Text(
              item.parent != null && item.parent!.isNotEmpty
                  ? 'Para ${item.parent}'
                  : 'Sin material asignado · edítalo para asignar',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontStyle: (item.parent ?? '').isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ],
        ),
      );
    }
    if (item.userSuggested) {
      subtitleParts.add(
        Text(
          'Sugerida por un usuario · sin formalizar',
          style: theme.textTheme.labelSmall,
        ),
      );
    }

    return Card(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : null,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: selecting
            ? Checkbox(
                value: selected,
                onChanged: (_) => onTap?.call(),
              )
            : null,
        title: Text(item.value),
        subtitle: subtitleParts.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < subtitleParts.length; i++) ...[
                      if (i > 0) const SizedBox(height: 2),
                      subtitleParts[i],
                    ],
                  ],
                ),
              ),
        trailing: selecting
            ? null
            : PopupMenuButton<_ItemAction>(
                tooltip: 'Acciones',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case _ItemAction.approve:
                      onApprove();
                    case _ItemAction.edit:
                      onEdit();
                    case _ItemAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  if (item.userSuggested)
                    PopupMenuItem(
                      value: _ItemAction.approve,
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          const Text('Aprobar sugerencia'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: _ItemAction.edit,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: _ItemAction.delete,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20),
                        SizedBox(width: 12),
                        Text('Eliminar'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ManualMergeBar extends StatelessWidget {
  const _ManualMergeBar({
    required this.count,
    required this.busy,
    required this.onApply,
  });

  final int count;
  final bool busy;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canApply = count >= 2 && !busy;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  count < 2
                      ? 'Marcá al menos 2 items para fusionar.'
                      : '$count item${count == 1 ? '' : 's'} seleccionado'
                          '${count == 1 ? '' : 's'}.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: canApply ? onApply : null,
                // El theme de la app aplica `minimumSize: Size.fromHeight(52)`
                // (full-width) a todos los FilledButton. Acá el botón vive
                // en una Row con un Expanded al lado, así que necesita
                // shrink-to-content; sin este override crashea con
                // BoxConstraints w=Infinity.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.compress),
                label: const Text('Fusionar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectingHint extends StatelessWidget {
  const _SelectingHint({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Marcá los items que en realidad son la misma persona o '
                'cosa. Al fusionar elegís cuál se queda; los demás se '
                'borran y sus ventas se actualizan.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muestra los items seleccionados con un radio para elegir cuál queda
/// como canónico. Devuelve el item elegido o `null` si cancela.
Future<MasterListItem?> _pickCanonical(
  BuildContext context,
  List<MasterListItem> selected,
) async {
  return showDialog<MasterListItem>(
    context: context,
    builder: (ctx) => _PickCanonicalDialog(items: selected),
  );
}

class _PickCanonicalDialog extends StatefulWidget {
  const _PickCanonicalDialog({required this.items});
  final List<MasterListItem> items;

  @override
  State<_PickCanonicalDialog> createState() => _PickCanonicalDialogState();
}

class _PickCanonicalDialogState extends State<_PickCanonicalDialog> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.items.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Elegir nombre canónico'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Es el nombre que se conserva. Los demás se borran del '
              'catálogo y las ventas que los usaban quedan apuntando a este.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _selectedId,
              onChanged: (v) {
                if (v != null) setState(() => _selectedId = v);
              },
              child: Column(
                children: [
                  for (final item in widget.items)
                    RadioListTile<String>(
                      value: item.id,
                      title: Text(item.value),
                      subtitle: item.userSuggested
                          ? Text(
                              'Sugerida por un usuario',
                              style: theme.textTheme.labelSmall,
                            )
                          : null,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final picked = widget.items.firstWhere(
              (it) => it.id == _selectedId,
              orElse: () => widget.items.first,
            );
            Navigator.pop(context, picked);
          },
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

enum _ItemAction { approve, edit, delete }

class _ItemEditResult {
  const _ItemEditResult({required this.value, this.parent});
  final String value;
  final String? parent;
}

/// Diálogo de captura de un value + (opcional) un parent. Si
/// `parentOptions` está vacío, el dialog solo pide el value (mismo UX
/// que antes para listas planas). Si tiene elementos, agrega un
/// dropdown para escoger el material padre.
Future<_ItemEditResult?> _promptItem(
  BuildContext context, {
  required String title,
  String? initialValue,
  String? initialParent,
  List<String> parentOptions = const [],
  String parentLabel = 'Padre',
}) async {
  return showDialog<_ItemEditResult>(
    context: context,
    builder: (ctx) => _ItemPromptDialog(
      title: title,
      initialValue: initialValue,
      initialParent: initialParent,
      parentOptions: parentOptions,
      parentLabel: parentLabel,
    ),
  );
}

class _ItemPromptDialog extends StatefulWidget {
  const _ItemPromptDialog({
    required this.title,
    this.initialValue,
    this.initialParent,
    this.parentOptions = const [],
    this.parentLabel = 'Padre',
  });
  final String title;
  final String? initialValue;
  final String? initialParent;
  final List<String> parentOptions;
  final String parentLabel;

  @override
  State<_ItemPromptDialog> createState() => _ItemPromptDialogState();
}

class _ItemPromptDialogState extends State<_ItemPromptDialog> {
  late final TextEditingController _controller;
  String? _selectedParent;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _selectedParent = widget.initialParent;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      _ItemEditResult(value: value, parent: _selectedParent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasParentPicker = widget.parentOptions.isNotEmpty;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej. Pedro, Tipo Premium…',
            ),
            textInputAction: hasParentPicker
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: hasParentPicker ? null : (_) => _submit(),
          ),
          if (hasParentPicker) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _selectedParent,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: widget.parentLabel,
                helperText: 'A qué material principal pertenece este subtipo.',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('— Sin asignar —'),
                ),
                for (final opt in widget.parentOptions)
                  DropdownMenuItem<String?>(value: opt, child: Text(opt)),
              ],
              onChanged: (v) => setState(() => _selectedParent = v),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
