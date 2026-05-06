import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
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

class MasterListDetailScreen extends ConsumerWidget {
  const MasterListDetailScreen({super.key, required this.listId});

  final String listId;

  bool get _hasParentPicker => _listsWithParentPicker.contains(listId);

  /// Carga la lista de materiales para usar como opciones del picker
  /// de parent. Se hace por demanda (al abrir el dialog) en lugar de
  /// watch en el build, para no causar rebuilds extra.
  Future<List<String>> _loadParentOptions(WidgetRef ref) async {
    if (!_hasParentPicker) return const [];
    final items = await ref
        .read(masterListsRepositoryProvider)
        .fetchItemsOnce(_parentSourceListId);
    return items.map((it) => it.value).toList();
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final parentOptions = await _loadParentOptions(ref);
    if (!context.mounted) return;
    final result = await _promptItem(
      context,
      title: 'Nueva opción',
      parentOptions: parentOptions,
      parentLabel: 'Material padre',
    );
    if (result == null || result.value.isEmpty) return;
    try {
      await ref.read(masterListsRepositoryProvider).addItem(
            listId,
            value: result.value,
            parent: result.parent,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _editItem(
    BuildContext context,
    WidgetRef ref,
    MasterListItem item,
  ) async {
    final parentOptions = await _loadParentOptions(ref);
    if (!context.mounted) return;
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
      // Si el parent cambió, lo actualizamos primero (sin propagación
      // a sales — el parent es metadata del catálogo, no se referencia
      // en sales documents).
      if (parentChanged) {
        await ref.read(masterListsRepositoryProvider).updateItem(
              listId,
              item.id,
              parent: result.parent,
            );
      }
      // Si el value cambió, renameItem lo actualiza Y propaga el rename
      // a todas las ventas que apuntan al value viejo.
      var salesUpdated = 0;
      if (valueChanged) {
        salesUpdated =
            await ref.read(masterListsRepositoryProvider).renameItem(
                  listId: listId,
                  itemId: item.id,
                  oldValue: item.value,
                  newValue: result.value,
                );
      }
      if (context.mounted) {
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
      if (context.mounted) {
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

  Future<void> _deleteItem(
    BuildContext context,
    WidgetRef ref,
    MasterListItem item,
  ) async {
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
      await ref.read(masterListsRepositoryProvider).deleteItem(listId, item.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _approveSuggestion(WidgetRef ref, MasterListItem item) async {
    await ref.read(masterListsRepositoryProvider).updateItem(
          listId,
          item.id,
          userSuggested: false,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(
      masterListItemsProvider(MasterListItemsQuery(listId: listId)),
    );
    final meta = ref.watch(masterListMetaProvider(listId));

    final supportsMerge = listSupportsMerge(listId);

    return Scaffold(
      appBar: AppBar(
        title: Text(meta.valueOrNull?.name ?? 'Lista maestra'),
        actions: [
          if (supportsMerge)
            IconButton(
              tooltip: 'Detectar y fusionar duplicados',
              icon: const Icon(Icons.merge),
              onPressed: () =>
                  context.push('/admin/master-lists/$listId/duplicates'),
            ),
          const ThemeModeIconButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItem(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: items.when(
        loading: () => const SkeletonList(),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(
            masterListItemsProvider(MasterListItemsQuery(listId: listId)),
          ),
        ),
        data: (data) {
          if (data.isEmpty) {
            return EmptyState(
              icon: Icons.list_alt_outlined,
              title: 'Lista vacía',
              message: 'Esta lista no tiene opciones todavía.',
              actionLabel: 'Agregar primera opción',
              onAction: () => _addItem(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: data.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = data[i];
              return _ItemCard(
                item: item,
                showParent: _hasParentPicker,
                onApprove: () => _approveSuggestion(ref, item),
                onEdit: () => _editItem(context, ref, item),
                onDelete: () => _deleteItem(context, ref, item),
              );
            },
          );
        },
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.showParent,
    required this.onApprove,
    required this.onEdit,
    required this.onDelete,
  });

  final MasterListItem item;
  final bool showParent;
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
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
        trailing: PopupMenuButton<_ItemAction>(
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
