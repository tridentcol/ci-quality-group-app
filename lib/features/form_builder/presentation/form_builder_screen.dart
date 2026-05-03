import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/errors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/section_label.dart';
import '../../admin/presentation/admin_shell.dart';
import '../../auth/data/auth_repository.dart';
import '../data/form_schema_repository.dart';
import '../domain/form_schema.dart';

/// Constructor del esquema dinámico de formularios. El admin puede:
///  - Reordenar campos arrastrando.
///  - Editar label / helperText / required / visibilidad por rol.
///  - Agregar campos custom (no-core).
///  - Eliminar campos custom (los core no se pueden borrar).
///  - Restaurar al esquema por defecto.
class FormBuilderScreen extends ConsumerStatefulWidget {
  const FormBuilderScreen({super.key, required this.module});

  final String module;

  @override
  ConsumerState<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends ConsumerState<FormBuilderScreen> {
  /// Copia editable. Se sincroniza con el provider la primera vez que llega.
  List<FieldDefinition>? _draft;
  int _baseVersion = 0;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final schemaAsync = ref.watch(formSchemaProvider(widget.module));
    // Inicialización: la primera vez que llega un schema y _draft está
    // vacío, lo absorbemos como snapshot inicial. Después de eso _draft
    // es la fuente de verdad local hasta que el admin guarde o salga.
    // No se reinicializa desde el stream para evitar pisar reorderings
    // recién guardados antes de que la suscripción los emita de vuelta.
    schemaAsync.whenData((schema) {
      if (_draft == null) {
        _baseVersion = schema.version;
        _draft = [...schema.fields];
      }
    });
    return Scaffold(
      drawer: adminDrawerOrNull(context, '/admin/form-builder'),
      appBar: AppBar(
        title: const Text('Constructor de formularios'),
        actions: [
          IconButton(
            tooltip: 'Restaurar al esquema por defecto',
            icon: const Icon(Icons.restart_alt),
            onPressed: _restoreDefaults,
          ),
        ],
      ),
      body: schemaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(formSchemaProvider(widget.module)),
        ),
        data: (schema) {
          // El draft / baseVersion se sincronizan en el `ref.listen` de
          // arriba. Aquí solo leemos.
          final draft = _draft ?? [...schema.fields];
          return Column(
            children: [
              const _ModuleHeader(),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: draft.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = draft.removeAt(oldIndex);
                      draft.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, i) {
                    final f = draft[i];
                    return Padding(
                      key: ValueKey(f.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FieldRow(
                        field: f,
                        index: i,
                        onEdit: () => _editField(i),
                        onDelete: f.coreField ? null : () => _deleteField(i),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: schemaAsync.maybeWhen(
        data: (_) => FloatingActionButton.extended(
          onPressed: _addField,
          icon: const Icon(Icons.add),
          label: const Text('Agregar campo'),
        ),
        orElse: () => null,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: LoadingButton(
            onPressed: _draft == null ? null : _save,
            loading: _saving,
            label: 'Guardar cambios',
            icon: Icons.save_outlined,
          ),
        ),
      ),
    );
  }

  Future<void> _addField() async {
    final newField = await _editFieldDialog(context, null);
    if (!mounted) return;
    if (newField == null || _draft == null) return;
    setState(() {
      _draft!.add(FieldDefinition(
        id: newField.id,
        label: newField.label,
        type: newField.type,
        required: newField.required,
        visibleToRoles: newField.visibleToRoles,
        editableByRoles: newField.editableByRoles,
        options: newField.options,
        masterListId: newField.masterListId,
        formula: newField.formula,
        placeholder: newField.placeholder,
        helperText: newField.helperText,
        defaultValue: newField.defaultValue,
        order: _draft!.length + 1,
        coreField: false,
      ));
    });
  }

  Future<void> _editField(int index) async {
    final draft = _draft;
    if (draft == null) return;
    final updated = await _editFieldDialog(context, draft[index]);
    if (!mounted) return;
    if (updated == null || _draft == null || index >= _draft!.length) return;
    setState(() => _draft![index] = updated);
  }

  Future<void> _deleteField(int index) async {
    final field = _draft![index];
    final ok = await showConfirmDialog(
      context,
      title: 'Eliminar campo',
      message:
          'Se quitará "${field.label}" del formulario. Los registros existentes '
          'que tengan datos en este campo conservan el valor histórico.',
      confirmLabel: 'Eliminar',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    setState(() => _draft!.removeAt(index));
  }

  Future<void> _restoreDefaults() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Restaurar formulario',
      message: 'Se descartarán los cambios actuales y el formulario volverá al '
          'esquema por defecto. Los datos guardados no se ven afectados.',
      confirmLabel: 'Restaurar',
      destructive: true,
      icon: Icons.restart_alt,
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final me = ref.read(currentProfileProvider).valueOrNull;
      await ref.read(formSchemaRepositoryProvider).resetToDefaults(
            module: widget.module,
            updatedBy: me?.uid ?? 'system',
          );
      // Reset a defaults sí descarta el draft local: el admin pidió
      // explícitamente volver al esquema por defecto.
      ref.invalidate(formSchemaProvider(widget.module));
      if (mounted) {
        setState(() {
          _draft = null;
          _baseVersion = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formulario restaurado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_draft == null) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      final me = ref.read(currentProfileProvider).valueOrNull;
      await ref.read(formSchemaRepositoryProvider).saveSchema(
            module: widget.module,
            fields: _draft!,
            updatedBy: me?.uid ?? 'system',
            previousVersion: _baseVersion,
          );
      // Mantenemos `_draft` con lo que el admin acaba de guardar (es la
      // fuente de verdad ahora) y avanzamos `_baseVersion` para que el
      // siguiente save use el previousVersion correcto. NO reseteamos a
      // null: hacerlo dispara una race con el Stream donde a veces el
      // próximo build se reinicializa con el schema viejo (pre-emit) y
      // se pisa el reorden recién guardado.
      //
      // Forzamos invalidación del provider para que SaleFormScreen y
      // cualquier otra pantalla con `ref.watch(formSchemaProvider)` re-
      // sincronicen con los datos frescos en Firestore.
      ref.invalidate(formSchemaProvider(widget.module));
      if (mounted) {
        setState(() => _baseVersion += 1);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formulario actualizado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Formulario de ventas'),
          const SizedBox(height: 8),
          Text(
            'Mantén pulsado el icono ☰ para reordenar. Los campos marcados '
            'como "core" no se pueden eliminar pero sí ocultar a roles. '
            'Los cambios se publican al guardar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  final FieldDefinition field;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(field.type),
                    color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            field.label,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (field.required)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '*',
                              style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _typeLabel(field.type) +
                          (field.coreField ? ' · core' : ''),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final r in AppRole.values)
                          _RoleBadge(
                            role: r,
                            visible: field.visibleToRoles.contains(r.id),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _typeLabel(FieldType t) => switch (t) {
        FieldType.text => 'Texto',
        FieldType.multiline => 'Texto largo',
        FieldType.number => 'Número',
        FieldType.decimal => 'Decimal',
        FieldType.date => 'Fecha',
        FieldType.datetime => 'Fecha y hora',
        FieldType.toggle => 'Sí / No',
        FieldType.dropdown => 'Lista de opciones',
        FieldType.masterListReference => 'Lista maestra',
        FieldType.computed => 'Calculado',
      };

  static IconData _iconFor(FieldType t) => switch (t) {
        FieldType.text => Icons.short_text,
        FieldType.multiline => Icons.notes,
        FieldType.number => Icons.pin,
        FieldType.decimal => Icons.calculate_outlined,
        FieldType.date => Icons.calendar_today_outlined,
        FieldType.datetime => Icons.event_outlined,
        FieldType.toggle => Icons.toggle_on_outlined,
        FieldType.dropdown => Icons.arrow_drop_down_circle_outlined,
        FieldType.masterListReference => Icons.list_alt_outlined,
        FieldType.computed => Icons.functions,
      };
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, required this.visible});
  final AppRole role;
  final bool visible;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = visible
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final bg = visible
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : theme.colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            role.label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Diálogo de edición de un campo. Devuelve la nueva FieldDefinition o
/// `null` si el usuario cancela.
Future<FieldDefinition?> _editFieldDialog(
    BuildContext context, FieldDefinition? initial) async {
  return showDialog<FieldDefinition>(
    context: context,
    builder: (ctx) => _FieldEditorDialog(initial: initial),
  );
}

class _FieldEditorDialog extends StatefulWidget {
  const _FieldEditorDialog({this.initial});
  final FieldDefinition? initial;
  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _id;
  late final TextEditingController _helper;
  late final TextEditingController _options; // separado por comas
  late final TextEditingController _masterListId;
  late final TextEditingController _formula;
  late FieldType _type;
  late bool _required;
  late Set<String> _visibleRoles;
  late Set<String> _editableRoles;

  bool get _isNew => widget.initial == null;
  bool get _isCore => widget.initial?.coreField ?? false;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _label = TextEditingController(text: f?.label ?? '');
    _id = TextEditingController(text: f?.id ?? '');
    _helper = TextEditingController(text: f?.helperText ?? '');
    _options = TextEditingController(text: f?.options.join(', ') ?? '');
    _masterListId = TextEditingController(text: f?.masterListId ?? '');
    _formula = TextEditingController(text: f?.formula ?? '');
    _type = f?.type ?? FieldType.text;
    _required = f?.required ?? false;
    _visibleRoles = {...(f?.visibleToRoles ?? AppRole.values.map((r) => r.id))};
    _editableRoles = {
      ...(f?.editableByRoles ?? AppRole.values.map((r) => r.id))
    };
  }

  @override
  void dispose() {
    _label.dispose();
    _id.dispose();
    _helper.dispose();
    _options.dispose();
    _masterListId.dispose();
    _formula.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'Nuevo campo' : 'Editar campo'),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Etiqueta visible'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _id,
              enabled: _isNew,
              decoration: InputDecoration(
                labelText: 'ID interno',
                helperText: _isNew
                    ? 'Sin espacios, ej. "notas". No se puede cambiar después.'
                    : 'No editable.',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FieldType>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Tipo de campo'),
              items: FieldType.values
                  .where((t) => _isCore ? t == _type : true)
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(_FieldRow._typeLabel(t)),
                      ))
                  .toList(),
              onChanged:
                  _isCore ? null : (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _helper,
              decoration: const InputDecoration(
                labelText: 'Texto de ayuda (opcional)',
              ),
            ),
            if (_type == FieldType.dropdown) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _options,
                decoration: const InputDecoration(
                  labelText: 'Opciones separadas por coma',
                  hintText: 'Sí, No, A revisar',
                ),
              ),
            ],
            if (_type == FieldType.masterListReference) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _masterListId,
                decoration: const InputDecoration(
                  labelText: 'ID de la lista maestra',
                  helperText: 'Ej. providers, materials, payment_methods.',
                ),
              ),
            ],
            if (_type == FieldType.computed) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _formula,
                decoration: const InputDecoration(
                  labelText: 'Fórmula',
                  helperText:
                      'Usa {fieldId} y operadores + - * /. Ej. {quantity} * {unitPrice}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Obligatorio'),
              value: _required,
              onChanged: (v) => setState(() => _required = v),
            ),
            const SizedBox(height: 8),
            Text('Visible para', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final r in AppRole.values)
                  FilterChip(
                    label: Text(r.label),
                    selected: _visibleRoles.contains(r.id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _visibleRoles.add(r.id);
                      } else {
                        _visibleRoles.remove(r.id);
                        _editableRoles.remove(r.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Puede editar', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final r in AppRole.values)
                  FilterChip(
                    label: Text(r.label),
                    selected: _editableRoles.contains(r.id),
                    onSelected: _visibleRoles.contains(r.id)
                        ? (v) => setState(() {
                              if (v) {
                                _editableRoles.add(r.id);
                              } else {
                                _editableRoles.remove(r.id);
                              }
                            })
                        : null,
                  ),
              ],
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
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _save() {
    final label = _label.text.trim();
    final id = _id.text.trim();
    if (label.isEmpty || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Etiqueta e ID son obligatorios.')),
      );
      return;
    }
    final result = FieldDefinition(
      id: id,
      label: label,
      type: _type,
      required: _required,
      visibleToRoles: _visibleRoles.toList(),
      editableByRoles: _editableRoles.toList(),
      options: _type == FieldType.dropdown
          ? _options.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : const [],
      masterListId: _type == FieldType.masterListReference
          ? (_masterListId.text.trim().isEmpty
              ? null
              : _masterListId.text.trim())
          : null,
      formula: _type == FieldType.computed
          ? (_formula.text.trim().isEmpty ? null : _formula.text.trim())
          : null,
      helperText: _helper.text.trim().isEmpty ? null : _helper.text.trim(),
      order: widget.initial?.order ?? 9999,
      coreField: _isCore,
      defaultValue: widget.initial?.defaultValue,
    );
    Navigator.pop(context, result);
  }
}
