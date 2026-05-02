import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/data/master_lists_repository.dart';
import '../../features/admin/domain/master_list.dart';

/// Campo de formulario que combina:
///  - Dropdown de opciones existentes en una lista maestra.
///  - Captura libre cuando la lista lo permite (`allowFreeText`). Si el
///    usuario digita un valor que no existe, se guarda como sugerencia
///    (`userSuggested = true`) y queda visible para el admin.
///
/// Devuelve siempre un `String` con el valor escogido o digitado.
class MasterListField extends ConsumerStatefulWidget {
  const MasterListField({
    super.key,
    required this.listId,
    required this.label,
    this.parent,
    this.initialValue,
    this.onChanged,
    this.required = false,
    this.helperText,
    this.allowSuggestions = true,
  });

  final String listId;
  final String label;

  /// Filtra opciones a las que tienen este parent. Útil para sublistas
  /// como "marcas de lámina" filtradas por material.
  final String? parent;

  final String? initialValue;
  final ValueChanged<String?>? onChanged;
  final bool required;
  final String? helperText;

  /// Si `false`, ignora la configuración de `allowFreeText` y bloquea la
  /// captura libre incluso si la lista la permite.
  final bool allowSuggestions;

  @override
  ConsumerState<MasterListField> createState() => _MasterListFieldState();
}

class _MasterListFieldState extends ConsumerState<MasterListField> {
  late final TextEditingController _controller;
  String? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(covariant MasterListField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue && widget.initialValue != _value) {
      _value = widget.initialValue;
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = MasterListItemsQuery(listId: widget.listId, parent: widget.parent);
    final itemsAsync = ref.watch(masterListItemsProvider(query));

    return FutureBuilder<MasterList?>(
      future: ref
          .read(masterListsRepositoryProvider)
          .getList(widget.listId),
      builder: (context, listSnap) {
        final list = listSnap.data;
        final allowFree = (list?.allowFreeText ?? false) && widget.allowSuggestions;

        return itemsAsync.when(
          loading: () => _LoadingPlaceholder(label: widget.label),
          error: (e, _) => InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: 'Error: $e',
            ),
          ),
          data: (items) {
            final values = items.map((e) => e.value).toList();
            return Autocomplete<String>(
              initialValue: TextEditingValue(text: _value ?? ''),
              optionsBuilder: (text) {
                final query = text.text.trim().toLowerCase();
                if (query.isEmpty) return values;
                return values.where(
                    (v) => v.toLowerCase().contains(query));
              },
              onSelected: (value) {
                setState(() => _value = value);
                widget.onChanged?.call(value);
              },
              fieldViewBuilder: (context, controller, focusNode, _) {
                _syncControllers(controller);
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: !allowFree,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    helperText: widget.helperText,
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                  ),
                  validator: (v) {
                    if (!widget.required) return null;
                    if (v == null || v.trim().isEmpty) {
                      return 'Este campo es obligatorio.';
                    }
                    return null;
                  },
                  onChanged: (text) async {
                    setState(() => _value = text);
                    widget.onChanged?.call(text);
                  },
                  onFieldSubmitted: (text) async {
                    final trimmed = text.trim();
                    if (trimmed.isEmpty) return;
                    final exists = values.any((v) =>
                        v.toLowerCase() == trimmed.toLowerCase());
                    if (!exists && allowFree) {
                      // Persistimos la sugerencia para que el admin la revise.
                      await ref.read(masterListsRepositoryProvider).addItem(
                            widget.listId,
                            value: trimmed,
                            parent: widget.parent,
                            userSuggested: true,
                          );
                    }
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, thickness: 1),
                        itemBuilder: (context, i) {
                          final option = options.elementAt(i);
                          return ListTile(
                            dense: true,
                            title: Text(option),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _syncControllers(TextEditingController autocompleteCtrl) {
    if (autocompleteCtrl.text != (_value ?? '')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        autocompleteCtrl.text = _value ?? '';
      });
    }
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: const [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Cargando opciones…'),
        ],
      ),
    );
  }
}
