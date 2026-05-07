import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/text_match.dart';
import '../../features/admin/data/master_lists_repository.dart';

/// Campo de formulario que combina:
///  - Dropdown clásico cuando la lista NO permite captura libre
///    (ej: métodos de pago, unidades).
///  - Autocomplete con captura libre cuando la lista lo permite. Si el
///    usuario digita un valor que no existe, se guarda como sugerencia
///    (`userSuggested = true`) y queda visible para el admin.
///
/// **Anti-duplicados** (deduplicación tolerante a typos):
///  - Si el usuario escribe algo que coincide con uno existente tras
///    normalizar (case/acentos/espacios) → silenciosamente usa el valor
///    canónico, no crea uno nuevo.
///  - Si escribe algo "parecido" (distancia de Levenshtein dentro de
///    umbral) → muestra un hint "¿quisiste decir 'X'?" con un toque para
///    aceptar.
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

    // Si la meta del list todavía no existe en Firestore (ej. lista
    // nueva que el admin no ha "abierto" para disparar el seed),
    // default a allowFreeText=true. Sin esto, un usuario de ventas
    // intentando seleccionar el destino de transferencia se queda
    // con un dropdown vacío que ni se despliega ni deja escribir.
    // Con free text, escriben el valor → se crea la sugerencia.
    final meta = listAsync.valueOrNull;
    final allowFree =
        (meta?.allowFreeText ?? true) && widget.allowSuggestions;

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
            onCreateSuggestion: (text) async {
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

/// Campo con captura libre + autocompletado fuzzy + deduplicación.
///
/// Comportamiento:
///  1. Mientras escribe, aparecen sugerencias debajo (matches normalizados
///     que contienen lo digitado). Tap en una → adopta el valor canónico.
///  2. Si lo digitado coincide exactamente (tras normalizar) con uno
///     existente, se "snappea" silenciosamente al canónico al hacer
///     blur/submit.
///  3. Si lo digitado se PARECE (Levenshtein) a uno existente pero no es
///     idéntico, se muestra un banner debajo del campo "¿Quisiste decir
///     'X'? Tocar para usar este." con un botón.
///  4. Si nada de lo anterior aplica, al perder foco se llama a
///     `onCreateSuggestion(text)` para guardar el valor nuevo en la lista
///     maestra como sugerencia.
class _FreeTextField extends StatefulWidget {
  const _FreeTextField({
    required this.label,
    required this.helperText,
    required this.required,
    required this.initialValue,
    required this.values,
    required this.onChanged,
    required this.onCreateSuggestion,
  });

  final String label;
  final String? helperText;
  final bool required;
  final String? initialValue;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  final Future<void> Function(String value) onCreateSuggestion;

  @override
  State<_FreeTextField> createState() => _FreeTextFieldState();
}

class _FreeTextFieldState extends State<_FreeTextField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  /// Sugerencia "¿quisiste decir X?" calculada con Levenshtein.
  /// Visible solo cuando hay match parcial (parecido, no idéntico).
  String? _didYouMean;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode.addListener(_onFocusChange);
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
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _resolveOnBlur();
    }
  }

  /// Cuando el usuario sale del campo:
  ///   - Si lo escrito = un canónico tras normalizar → snap silencioso al
  ///     canónico (corrige caps/espacios/acentos sin friccionar).
  ///   - Si no, registra el texto como sugerencia (la rule en Firestore
  ///     deja a no-admins crear con userSuggested=true).
  Future<void> _resolveOnBlur() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final canonical = canonicalMatch(text, widget.values);
    if (canonical != null && canonical != text) {
      _controller.text = canonical;
      widget.onChanged(canonical);
      setState(() => _didYouMean = null);
      return;
    }
    if (canonical != null) return; // ya es exactamente el canónico

    // No hay match exacto. Si es nuevo, lo guardamos como sugerencia.
    // (El admin lo aprobará después editándolo o lo borrará.)
    try {
      await widget.onCreateSuggestion(text);
    } catch (_) {
      // No bloqueamos el flujo del formulario si falla la sugerencia.
    }
  }

  /// Recalcula la sugerencia "¿quisiste decir?" basada en lo que el usuario
  /// está escribiendo. Se invoca en cada `onChanged`.
  void _refreshDidYouMean(String text) {
    if (text.trim().isEmpty) {
      if (_didYouMean != null) setState(() => _didYouMean = null);
      return;
    }
    final exact = canonicalMatch(text, widget.values);
    if (exact != null) {
      // Match exacto tras normalizar — no hace falta sugerir nada,
      // el snap on-blur lo arregla.
      if (_didYouMean != null) setState(() => _didYouMean = null);
      return;
    }
    final closest = closestMatch(text, widget.values);
    if (closest != _didYouMean) {
      setState(() => _didYouMean = closest);
    }
  }

  void _useDidYouMean() {
    final v = _didYouMean;
    if (v == null) return;
    _controller.text = v;
    widget.onChanged(v);
    setState(() => _didYouMean = null);
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
    setState(() => _didYouMean = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RawAutocomplete<String>(
          textEditingController: _controller,
          focusNode: _focusNode,
          optionsBuilder: (TextEditingValue value) {
            final query = value.text.trim();
            if (query.isEmpty) return const Iterable<String>.empty();
            final nq = normalizeForMatch(query);
            // Match: cualquier valor existente cuyo normalizado contenga
            // lo escrito normalizado. Limitamos a 6 para no ahogar la UI.
            final matches = widget.values
                .where((v) => normalizeForMatch(v).contains(nq))
                .take(6)
                .toList();
            return matches;
          },
          displayStringForOption: (s) => s,
          onSelected: (selected) {
            // Tap explícito en una sugerencia → usamos el canónico.
            _controller.text = selected;
            widget.onChanged(selected);
            setState(() => _didYouMean = null);
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helperText,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down),
                  tooltip: 'Ver todas las opciones',
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
              onChanged: (text) {
                widget.onChanged(text);
                _refreshDidYouMean(text);
              },
              onFieldSubmitted: (_) {
                onSubmit();
                _resolveOnBlur();
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
                  constraints: const BoxConstraints(maxHeight: 240, maxWidth: 480),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final opt = options.elementAt(i);
                      return ListTile(
                        dense: true,
                        title: Text(opt),
                        onTap: () => onSelected(opt),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        if (_didYouMean != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: InkWell(
              onTap: _useDidYouMean,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.75),
                          ),
                          children: [
                            const TextSpan(text: '¿Quisiste decir '),
                            TextSpan(
                              text: '"$_didYouMean"',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const TextSpan(text: '? Toca para usar ese.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet con búsqueda + lista de opciones para un campo de captura
/// libre. Permite ver TODAS las opciones aunque el campo ya tenga un valor.
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
            .where((v) =>
                normalizeForMatch(v).contains(normalizeForMatch(_query)),)
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
