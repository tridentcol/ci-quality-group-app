import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../../shared/widgets/section_label.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/form_schema.dart';
import '../domain/formula_engine.dart';

/// Controlador del estado de un formulario dinámico. Lleva los valores
/// actuales por fieldId y notifica cambios a sus listeners.
class DynamicFormController extends ChangeNotifier {
  DynamicFormController({Map<String, Object?>? initial})
      : _values = {...?initial};

  final Map<String, Object?> _values;
  bool _disposed = false;

  Map<String, Object?> get values => Map.unmodifiable(_values);

  Object? get(String id) => _values[id];

  /// Acceso a string con coerción tolerante: si el valor guardado en
  /// Firestore es un `num`/`bool` (legacy o cambio de tipo del campo),
  /// no tiramos `TypeError`; lo serializamos a String.
  String? getString(String id) {
    final v = _values[id];
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  bool getBool(String id) {
    final v = _values[id];
    if (v is bool) return v;
    if (v is String) return v == 'true';
    if (v is num) return v != 0;
    return false;
  }

  void set(String id, Object? value) {
    if (_disposed) return; // No-op tras dispose para no romper llamadas tardías.
    if (_values[id] == value) return;
    _values[id] = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Devuelve los valores agrupados en `core` y `custom`, listo para
  /// pasar al repositorio. Los core son los `coreField=true` del schema
  /// (van a campos tipados de Sale); el resto va a `customFields`.
  ({Map<String, Object?> core, Map<String, dynamic> custom}) split(
      FormSchema schema) {
    final core = <String, Object?>{};
    final custom = <String, dynamic>{};
    for (final f in schema.fields) {
      final v = _values[f.id];
      if (f.coreField) {
        core[f.id] = v;
      } else {
        // Solo persistimos valores no nulos para no inflar el doc.
        if (v != null && v.toString().isNotEmpty) {
          custom[f.id] = v;
        }
      }
    }
    return (core: core, custom: custom);
  }
}

/// Renderiza un FormSchema. Todos los campos visibles para el rol actual
/// se renderizan; los `editableByRoles` que no incluyen el rol del usuario
/// quedan readonly. Los campos `computed` se recalculan automáticamente
/// con `FormulaEngine`.
class DynamicFormRenderer extends ConsumerWidget {
  const DynamicFormRenderer({
    super.key,
    required this.schema,
    required this.controller,
    this.coreFieldOverrides = const {},
  });

  final FormSchema schema;
  final DynamicFormController controller;

  /// Permite a la pantalla padre inyectar widgets custom para campos core
  /// que tienen lógica especial (ej. `date` con DatePicker estándar,
  /// `material` con dependencia de `materialVariant`, etc.).
  /// Si la clave coincide con un fieldId, ese widget se usa en vez del
  /// renderer por defecto.
  final Map<String, Widget Function(FieldDefinition field)> coreFieldOverrides;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.role,
    ));
    final visibleFields = schema.fields
        .where((f) => role == null || f.visibleToRoles.contains(role.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < visibleFields.length; i++) ...[
              _renderField(visibleFields[i], role),
              if (i < visibleFields.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _renderField(FieldDefinition field, AppRole? role) {
    final readonly = role != null && !field.editableByRoles.contains(role.id);
    final override = coreFieldOverrides[field.id];
    if (override != null) return override(field);
    switch (field.type) {
      case FieldType.text:
        return _TextFieldWidget(
            field: field, controller: controller, readonly: readonly);
      case FieldType.multiline:
        return _TextFieldWidget(
            field: field,
            controller: controller,
            readonly: readonly,
            maxLines: 4);
      case FieldType.number:
      case FieldType.decimal:
        return _NumberFieldWidget(
            field: field, controller: controller, readonly: readonly);
      case FieldType.toggle:
        return _ToggleWidget(
            field: field, controller: controller, readonly: readonly);
      case FieldType.dropdown:
        return _DropdownWidget(
            field: field, controller: controller, readonly: readonly);
      case FieldType.masterListReference:
        return _MasterListWidget(
            field: field, controller: controller, readonly: readonly);
      case FieldType.date:
        return _DateWidget(field: field, controller: controller);
      case FieldType.datetime:
        return _DateTimeWidget(field: field, controller: controller);
      case FieldType.computed:
        return _ComputedWidget(field: field, controller: controller);
    }
  }
}

class _TextFieldWidget extends StatefulWidget {
  const _TextFieldWidget({
    required this.field,
    required this.controller,
    required this.readonly,
    this.maxLines = 1,
  });

  final FieldDefinition field;
  final DynamicFormController controller;
  final bool readonly;
  final int maxLines;

  @override
  State<_TextFieldWidget> createState() => _TextFieldWidgetState();
}

class _TextFieldWidgetState extends State<_TextFieldWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    // Coerción tolerante: si el valor guardado es num/bool (legacy o
    // cambio de tipo del campo), no tiramos TypeError. `getString`
    // hace `toString()` para tolerar la migración suave.
    _ctrl = TextEditingController(
      text: widget.controller.getString(widget.field.id) ?? '',
    );
    _ctrl.addListener(_propagate);
  }

  void _propagate() {
    widget.controller.set(widget.field.id, _ctrl.text);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_propagate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      readOnly: widget.readonly,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.field.label,
        hintText: widget.field.placeholder,
        helperText: widget.field.helperText,
      ),
      validator: (v) {
        if (!widget.field.required) return null;
        if (v == null || v.trim().isEmpty) return 'Este campo es obligatorio.';
        return null;
      },
    );
  }
}

class _NumberFieldWidget extends StatefulWidget {
  const _NumberFieldWidget({
    required this.field,
    required this.controller,
    required this.readonly,
  });

  final FieldDefinition field;
  final DynamicFormController controller;
  final bool readonly;

  @override
  State<_NumberFieldWidget> createState() => _NumberFieldWidgetState();
}

class _NumberFieldWidgetState extends State<_NumberFieldWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final v = widget.controller.get(widget.field.id);
    _ctrl = TextEditingController(text: v?.toString() ?? '');
    _ctrl.addListener(_propagate);
  }

  void _propagate() {
    final parsed = num.tryParse(_ctrl.text.replaceAll(',', '.'));
    widget.controller.set(widget.field.id, parsed);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_propagate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      readOnly: widget.readonly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: widget.field.label,
        helperText: widget.field.helperText,
      ),
      validator: (v) {
        if (!widget.field.required) return null;
        if (v == null || v.trim().isEmpty) return 'Ingresa un valor.';
        final n = num.tryParse(v.replaceAll(',', '.'));
        if (n == null) return 'Valor inválido.';
        return null;
      },
    );
  }
}

class _ToggleWidget extends StatelessWidget {
  const _ToggleWidget({
    required this.field,
    required this.controller,
    required this.readonly,
  });

  final FieldDefinition field;
  final DynamicFormController controller;
  final bool readonly;

  @override
  Widget build(BuildContext context) {
    final value = controller.getBool(field.id);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(field.label),
      subtitle: field.helperText != null ? Text(field.helperText!) : null,
      value: value,
      onChanged: readonly ? null : (v) => controller.set(field.id, v),
    );
  }
}

class _DropdownWidget extends StatelessWidget {
  const _DropdownWidget({
    required this.field,
    required this.controller,
    required this.readonly,
  });

  final FieldDefinition field;
  final DynamicFormController controller;
  final bool readonly;

  @override
  Widget build(BuildContext context) {
    final value = controller.getString(field.id);
    return DropdownButtonFormField<String>(
      value: field.options.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.helperText,
      ),
      items: field.options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: readonly ? null : (v) => controller.set(field.id, v),
      validator: (v) {
        if (!field.required) return null;
        if (v == null || v.trim().isEmpty) return 'Este campo es obligatorio.';
        return null;
      },
    );
  }
}

class _MasterListWidget extends StatelessWidget {
  const _MasterListWidget({
    required this.field,
    required this.controller,
    required this.readonly,
  });

  final FieldDefinition field;
  final DynamicFormController controller;
  final bool readonly;

  @override
  Widget build(BuildContext context) {
    if (field.masterListId == null) {
      return Text('Campo "${field.label}" sin lista maestra asignada.');
    }
    if (readonly) {
      // Renderizado readonly: solo muestra el valor actual sin permitir
      // edición. El usuario sin permiso no debería ver siquiera el campo,
      // así que esto es un fallback defensivo.
      final v = controller.getString(field.id);
      return InputDecorator(
        decoration: InputDecoration(labelText: field.label),
        child: Text(v ?? '—'),
      );
    }
    return MasterListField(
      listId: field.masterListId!,
      label: field.label,
      initialValue: controller.getString(field.id),
      required: field.required,
      onChanged: (v) => controller.set(field.id, v),
      helperText: field.helperText,
    );
  }
}

class _DateWidget extends StatelessWidget {
  const _DateWidget({required this.field, required this.controller});
  final FieldDefinition field;
  final DynamicFormController controller;

  @override
  Widget build(BuildContext context) {
    // Coerción tolerante: el valor puede venir de Firestore como
    // Timestamp/string/etc. Si no es DateTime, lo ignoramos.
    final raw = controller.get(field.id);
    final DateTime? value = raw is DateTime ? raw : null;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          helpText: field.label,
          confirmText: 'Aceptar',
          cancelText: 'Cancelar',
        );
        if (picked != null) controller.set(field.id, picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.helperText,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value != null ? formatDate(value) : '—'),
      ),
    );
  }
}

class _DateTimeWidget extends StatelessWidget {
  const _DateTimeWidget({required this.field, required this.controller});
  final FieldDefinition field;
  final DynamicFormController controller;

  @override
  Widget build(BuildContext context) {
    // Coerción tolerante: el valor puede venir de Firestore como
    // Timestamp/string/etc. Si no es DateTime, lo ignoramos.
    final raw = controller.get(field.id);
    final DateTime? value = raw is DateTime ? raw : null;
    return InkWell(
      onTap: () async {
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (pickedDate == null) return;
        if (!context.mounted) return;
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: value != null
              ? TimeOfDay(hour: value.hour, minute: value.minute)
              : TimeOfDay.now(),
        );
        if (pickedTime == null) return;
        controller.set(
          field.id,
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
              pickedTime.hour, pickedTime.minute),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.helperText,
          suffixIcon: const Icon(Icons.event_outlined),
        ),
        child: Text(value != null ? formatDateTime(value) : '—'),
      ),
    );
  }
}

/// Campo `computed`: muestra el resultado de la fórmula en una card
/// destacada. Re-evalúa cuando los campos referenciados cambian.
class _ComputedWidget extends StatelessWidget {
  const _ComputedWidget({required this.field, required this.controller});
  final FieldDefinition field;
  final DynamicFormController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formula = field.formula;
    num? value;
    if (formula != null && formula.isNotEmpty) {
      value = FormulaEngine.evaluate(formula, controller.values);
    }
    // Persistimos el valor calculado en el controller para que `split()`
    // lo entregue al guardar (ej. `totalValue` se manda a Sale).
    if (value != controller.get(field.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.set(field.id, value);
      });
    }
    final display = value != null ? formatCop(value) : 'Pendiente';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    display,
                    style: theme.textTheme.headlineSmall,
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

/// Helper para encabezados visuales dentro del formulario (ej. agrupar
/// "Información del cliente" / "Material y cantidad" / "Pago").
class FormSectionDivider extends StatelessWidget {
  const FormSectionDivider({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: SectionLabel(label),
    );
  }
}
