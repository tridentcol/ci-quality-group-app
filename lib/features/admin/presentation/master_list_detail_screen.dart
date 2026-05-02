import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/master_lists_repository.dart';
import '../domain/master_list.dart';

class MasterListDetailScreen extends ConsumerStatefulWidget {
  const MasterListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<MasterListDetailScreen> createState() =>
      _MasterListDetailScreenState();
}

class _MasterListDetailScreenState
    extends ConsumerState<MasterListDetailScreen> {
  Future<MasterList?>? _listFuture;

  @override
  void initState() {
    super.initState();
    _listFuture =
        ref.read(masterListsRepositoryProvider).getList(widget.listId);
  }

  Future<void> _addItem() async {
    final value = await _promptValue(context, title: 'Nueva opción');
    if (value == null || value.isEmpty) return;
    await ref
        .read(masterListsRepositoryProvider)
        .addItem(widget.listId, value: value);
  }

  Future<void> _editItem(MasterListItem item) async {
    final value = await _promptValue(
      context,
      title: 'Editar opción',
      initial: item.value,
    );
    if (value == null || value.isEmpty || value == item.value) return;
    await ref
        .read(masterListsRepositoryProvider)
        .updateItem(widget.listId, item.id, value: value, userSuggested: false);
  }

  Future<void> _deleteItem(MasterListItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar opción'),
        content: Text(
          'Se eliminará "${item.value}" de la lista. Las ventas o registros '
          'que ya la usen no se verán afectados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref
        .read(masterListsRepositoryProvider)
        .deleteItem(widget.listId, item.id);
  }

  Future<void> _approveSuggestion(MasterListItem item) async {
    await ref.read(masterListsRepositoryProvider).updateItem(
          widget.listId,
          item.id,
          userSuggested: false,
        );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(
      masterListItemsProvider(MasterListItemsQuery(listId: widget.listId)),
    );

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<MasterList?>(
          future: _listFuture,
          builder: (context, snap) =>
              Text(snap.data?.name ?? 'Lista maestra'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(e.toString())),
        ),
        data: (data) {
          if (data.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Esta lista no tiene opciones todavía.\nUsa el botón Agregar.',
                  textAlign: TextAlign.center,
                ),
              ),
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
                      ? const Text(
                          'Sugerida por un usuario · sin formalizar',
                          style: TextStyle(fontSize: 12),
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
                          onPressed: () => _approveSuggestion(item),
                        ),
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editItem(item),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteItem(item),
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

Future<String?> _promptValue(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Valor'),
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
