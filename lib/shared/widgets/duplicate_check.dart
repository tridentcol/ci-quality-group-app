import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/text_match.dart';
import '../../features/admin/data/master_lists_repository.dart';

/// Un campo de un formulario sujeto a chequeo de duplicados antes de
/// guardar. Apunta a un valor escrito por el usuario y a la lista
/// maestra contra la que se debe verificar.
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.label,
    required this.value,
    required this.listId,
    this.parent,
  });

  /// Texto visible en el modal ("Cliente", "Quién recibe", etc).
  final String label;

  /// Valor que el usuario escribió o seleccionó.
  final String value;

  /// ID de la lista maestra contra la que comparar.
  final String listId;

  /// Filtro opcional por parent (ej. para sublistas).
  final String? parent;
}

/// Si alguno de los [candidates] se parece sospechosamente a un valor que
/// ya existe en su lista maestra (typos, espacios, b/v, h muda, etc.),
/// muestra un modal para que el usuario confirme cuál usar antes de
/// guardar la venta.
///
/// Devuelve:
///  - `Map<label, valor a usar>` con los valores finales a guardar (puede
///    venir con el typed original O con el canónico, según lo que escogió
///    el usuario)
///  - `null` si el usuario canceló el modal (la venta NO debe guardarse)
///
/// Si no hay nada sospechoso, devuelve directamente el mapa de inputs sin
/// abrir el modal.
Future<Map<String, String>?> confirmFreeTextValues(
  BuildContext context,
  WidgetRef ref,
  List<DuplicateCandidate> candidates,
) async {
  final repo = ref.read(masterListsRepositoryProvider);

  final suspicious = <_Suspicious>[];
  for (final c in candidates) {
    if (c.value.trim().isEmpty) continue;
    final items = await repo.fetchItemsOnce(c.listId, parent: c.parent);
    final values = items.map((i) => i.value).toList();

    // Si el typed coincide exactamente con alguno existente, todo bien.
    if (values.contains(c.value)) continue;

    // Si normaliza a un canónico exacto, también todo bien — el field
    // ya hizo el snap. Pero por si acaso nos pasaron el valor sin pasar
    // por el snap, lo verificamos aquí también.
    final canonical = canonicalMatch(c.value, values);
    if (canonical != null && canonical == c.value) continue;

    if (canonical != null) {
      // Hay match canónico (post-normalización fonética) pero el value
      // pasado no coincide letra por letra. Tratamos como sospechoso
      // para que el usuario confirme el snap.
      suspicious.add(_Suspicious(c.label, c.value, canonical));
      continue;
    }

    // Match más laxo (Levenshtein dentro de umbral).
    final close = closestMatch(c.value, values);
    if (close != null && close != c.value) {
      suspicious.add(_Suspicious(c.label, c.value, close));
    }
  }

  if (suspicious.isEmpty) {
    return {for (final c in candidates) c.label: c.value};
  }

  // Mapa inicial: para cada sospechoso, la opción seleccionada por
  // defecto es "usar el existente" (índice 0). Para los no sospechosos
  // copiamos su valor tal cual.
  final selections = <String, _Choice>{
    for (final s in suspicious) s.label: _Choice.useExisting,
  };

  final resolved = await showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DuplicateConfirmModal(
      candidates: candidates,
      suspicious: suspicious,
      initialSelections: selections,
    ),
  );

  return resolved;
}

class _Suspicious {
  const _Suspicious(this.label, this.typed, this.existing);
  final String label;
  final String typed;
  final String existing;
}

enum _Choice { useExisting, createNew }

class _DuplicateConfirmModal extends StatefulWidget {
  const _DuplicateConfirmModal({
    required this.candidates,
    required this.suspicious,
    required this.initialSelections,
  });

  final List<DuplicateCandidate> candidates;
  final List<_Suspicious> suspicious;
  final Map<String, _Choice> initialSelections;

  @override
  State<_DuplicateConfirmModal> createState() => _DuplicateConfirmModalState();
}

class _DuplicateConfirmModalState extends State<_DuplicateConfirmModal> {
  late Map<String, _Choice> _selections;

  @override
  void initState() {
    super.initState();
    _selections = Map.of(widget.initialSelections);
  }

  Map<String, String> _resolve() {
    final out = <String, String>{};
    for (final c in widget.candidates) {
      final s = widget.suspicious.firstWhere(
        (x) => x.label == c.label,
        orElse: () => _Suspicious(c.label, c.value, c.value),
      );
      // Si NO hay sospecha (s.typed == s.existing == c.value), usamos el
      // value original.
      if (s.typed == s.existing) {
        out[c.label] = c.value;
        continue;
      }
      final choice = _selections[c.label] ?? _Choice.useExisting;
      out[c.label] = choice == _Choice.useExisting ? s.existing : s.typed;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.error_outline),
          SizedBox(width: 8),
          Expanded(child: Text('Confirmar valores')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Algunos valores se parecen a opciones que ya existen. '
              'Para evitar duplicados, confirma cuál usar:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            for (final s in widget.suspicious)
              _SuspiciousBlock(
                suspicious: s,
                selection: _selections[s.label] ?? _Choice.useExisting,
                onChanged: (choice) {
                  setState(() => _selections[s.label] = choice);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_resolve()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _SuspiciousBlock extends StatelessWidget {
  const _SuspiciousBlock({
    required this.suspicious,
    required this.selection,
    required this.onChanged,
  });

  final _Suspicious suspicious;
  final _Choice selection;
  final ValueChanged<_Choice> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            suspicious.label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          RadioGroup<_Choice>(
            groupValue: selection,
            onChanged: (v) => v != null ? onChanged(v) : null,
            child: Column(
              children: [
                RadioListTile<_Choice>(
                  value: _Choice.useExisting,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    suspicious.existing,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: const Text('Usar el existente (recomendado)'),
                ),
                RadioListTile<_Choice>(
                  value: _Choice.createNew,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(suspicious.typed),
                  subtitle: const Text('Crear este como una persona/valor distinto'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
