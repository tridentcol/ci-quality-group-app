import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../data/master_lists_repository.dart';
import '../domain/master_list.dart';

class MasterListDetailScreen extends ConsumerWidget {
  const MasterListDetailScreen({super.key, required this.listId});

  final String listId;

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final value = await _promptValue(context, title: 'Nueva opción');
    if (value == null || value.isEmpty) return;
    try {
      await ref
          .read(masterListsRepositoryProvider)
          .addItem(listId, value: value);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _editItem(
      BuildContext context, WidgetRef ref, MasterListItem item,) async {
    final value = await _promptValue(
      context,
      title: 'Editar opción',
      initial: item.value,
    );
    if (value == null || value.isEmpty || value == item.value) return;
    try {
      await ref.read(masterListsRepositoryProvider).updateItem(
            listId,
            item.id,
            value: value,
            userSuggested: false,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _deleteItem(
      BuildContext context, WidgetRef ref, MasterListItem item,) async {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(meta.valueOrNull?.name ?? 'Lista maestra'),
        actions: const [ThemeModeIconButton()],
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
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(item.value),
                  subtitle: item.userSuggested
                      ? Text(
                          'Sugerida por un usuario · sin formalizar',
                          style: Theme.of(context).textTheme.labelSmall,
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.userSuggested)
                        IconButton(
                          tooltip: 'Aprobar sugerencia',
                          icon: const Icon(Icons.check_circle_outline),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: () => _approveSuggestion(ref, item),
                        ),
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editItem(context, ref, item),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteItem(context, ref, item),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Diálogo de captura de un valor de texto. El controller se crea/dispone
/// dentro de un StatefulBuilder para no leakear (el patrón anterior lo
/// dejaba colgando en cada apertura).
Future<String?> _promptValue(
  BuildContext context, {
  required String title,
  String? initial,
}) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PromptDialog(title: title, initial: initial),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, this.initial});
  final String title;
  final String? initial;
  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Valor'),
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
