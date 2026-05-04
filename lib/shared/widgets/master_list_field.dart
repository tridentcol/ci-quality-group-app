import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/data/master_lists_repository.dart';

/// Campo de formulario que combina:
///  - Dropdown clásico cuando la lista NO permite captura libre
///    (ej: métodos de pago, unidades).
///  - Autocomplete con captura libre cuando la lista lo permite. Si el
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
  String? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant MasterListField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue &&
        widget.initialValue != _value) {
      _value = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final query =
        MasterListItemsQuery(listId: widget.listId, parent: widget.parent);
    final itemsAsync = ref.watch(masterListItemsProvider(query));
    final listAsync = ref.watch(masterListMetaProvider(widget.listId));

    final allowFree = (listAsync.valueOrNull?.allowFreeText ?? false) &&
        widget.allowSuggestions;

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
        if (allowFree) {
          return _FreeTextField(
            label: widget.label,
            helperText: widget.helperText,
            required: widget.required,
            initialValue: _value,
            values: values,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged?.call(v);
            },
            onSuggestion: (text) async {
              await ref.read(masterListsRepositoryProvider).addItem(
                    widget.listId,
                    value: text,
                    parent: widget.parent,
                    userSuggested: true,
                  );
            },
          );
        }
        return _DropdownField(
          label: widget.label,
          helperText: widget.helperText,
          required: widget.required,
          value: _value,
          values: values,
          onChanged: (v) {
            setState(() => _value = v);
            widget.onChanged?.call(v);
          },
        );
      },
    );
  }
}

/// Dropdown estricto: solo deja escoger entre los valores ya existentes
/// en la lista maestra. Se usa para `payment_methods`, `units`, etc.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.helperText,
    required this.required,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? helperText;
  final bool required;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Si el value actual no está en la lista (por ejemplo, una venta antigua
    // con un método ya borrado), lo añadimos al final como opción
    // seleccionable para no romper la edición.
    final allValues = [...values];
    if (value != null && value!.isNotEmpty && !allValues.contains(value)) {
      allValues.add(value!);
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
      ),
      items: allValues
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: onChanged,
      validator: (v) {
        if (!required) return null;
        if (v == null || v.trim().isEmpty) {
          return 'Este campo es obligatorio.';
        }
        return null;
      },
    );
  }
}

/// Campo con captura libre: muestra el valor actual, deja desplegar todas
/// las opciones existentes y permite escribir un valor nuevo (queda como
/// sugerencia). Se usa para `providers`, `payers`, `materials`, etc.
class _FreeTextField extends StatefulWidget {
  const _FreeTextField({
    required this.label,
    required this.helperText,
    required this.required,
    required this.initialValue,
    required this.values,
    required this.onChanged,
    required this.onSuggestion,
  });

  final String label;
  final String? helperText;
  final bool required;
  final String? initialValue;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  final Future<void> Function(String value) onSuggestion;

  @override
  State<_FreeTextField> createState() => _FreeTextFieldState();
}

class _FreeTextFieldState extends State<_FreeTextField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(covariant _FreeTextField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          _OptionsPickerSheet(label: widget.label, values: widget.values),
    );
    if (selected == null) return;
    _controller.text = selected;
    widget.onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_drop_down),
          tooltip: 'Ver opciones',
          onPressed: _openPicker,
        ),
      ),
      validator: (v) {
        if (!widget.required) return null;
        if (v == null || v.trim().isEmpty) {
          return 'Este campo es obligatorio.';
        }
        return null;
      },
      onChanged: (text) => widget.onChanged(text),
      onFieldSubmitted: (text) async {
        final trimmed = text.trim();
        if (trimmed.isEmpty) return;
        final exists =
            widget.values.any((v) => v.toLowerCase() == trimmed.toLowerCase());
        if (!exists) {
          await widget.onSuggestion(trimmed);
        }
      },
    );
  }
}

/// Bottom sheet con búsqueda + lista de opciones para un campo de captura
/// libre. Permite ver TODAS las opciones aunque el campo ya tenga un valor,
/// que era el bug del Autocomplete (filtraba por el texto actual y dejaba
/// fuera otras opciones válidas como "Transferencia").
class _OptionsPickerSheet extends StatefulWidget {
  const _OptionsPickerSheet({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  State<_OptionsPickerSheet> createState() => _OptionsPickerSheetState();
}

class _OptionsPickerSheetState extends State<_OptionsPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _query.trim().isEmpty
        ? widget.values
        : widget.values
            .where((v) => v.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar…',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Sin resultados. Cierra y escribe el valor en el campo '
                        'para guardarlo como sugerencia.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final v = filtered[i];
                        return ListTile(
                          title: Text(v),
                          onTap: () => Navigator.of(context).pop(v),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: const Row(
        children: [
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
