import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../../shared/widgets/section_label.dart';
import '../../auth/data/auth_repository.dart';
import '../../form_builder/data/form_schema_repository.dart';
import '../../form_builder/domain/form_schema.dart';
import '../../form_builder/presentation/dynamic_form_renderer.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';

const _laminaMaterial = 'LAMINA';
const _defaultUnit = 'Kilogramos';
const _defaultPaymentMethod = 'Efectivo';

/// Pantalla para crear una nueva venta o editar una existente (si está
/// dentro de la ventana de 24 h o el usuario es admin).
class SaleFormScreen extends ConsumerStatefulWidget {
  const SaleFormScreen({super.key, this.editingSale});

  final Sale? editingSale;

  @override
  ConsumerState<SaleFormScreen> createState() => _SaleFormScreenState();
}

class _SaleFormScreenState extends ConsumerState<SaleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _docNumberCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController();

  DateTime _date = AppClock.now();
  String _documentType = 'Cédula';
  String? _provider;
  String? _material;
  String? _materialVariant;
  String _unit = _defaultUnit;
  String _paymentMethod = _defaultPaymentMethod;
  String? _payer;

  bool _saving = false;
  String? _formError;

  /// Controller para los campos custom (no-core) definidos por el admin
  /// en el constructor de formularios. Va separado del estado de los
  /// campos core para no mezclar lógica.
  late final DynamicFormController _customFieldsController;

  bool get _isEdit => widget.editingSale != null;

  @override
  void initState() {
    super.initState();
    final s = widget.editingSale;
    if (s != null) {
      _date = s.date;
      _documentType = s.documentType;
      _docNumberCtrl.text = s.documentNumber;
      _provider = s.providerName;
      _material = s.material;
      _materialVariant = s.materialVariant;
      _unit = s.unit;
      _quantityCtrl.text = s.quantity.toString();
      _unitPriceCtrl.text = s.unitPrice.toString();
      _paymentMethod = s.paymentMethod;
      _payer = s.payerName;
    }
    _customFieldsController =
        DynamicFormController(initial: s?.customFields ?? {});
    // Antes hacíamos `addListener(_recompute)` que disparaba setState global
    // en cada tecla y rebuildeaba 12+ widgets. Ahora _TotalCard escucha
    // directamente los controllers vía ListenableBuilder.
  }

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    _quantityCtrl.dispose();
    _unitPriceCtrl.dispose();
    _customFieldsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 1)),
      helpText: 'Selecciona la fecha de la venta',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    final quantity = num.parse(_quantityCtrl.text.replaceAll(',', '.'));
    final unitPrice = num.parse(_unitPriceCtrl.text.replaceAll(',', '.'));

    setState(() => _saving = true);
    try {
      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) {
        throw StateError('Sesión no válida.');
      }

      // Solo persistimos los customFields que siguen vigentes en el
      // schema actual. Si el admin eliminó un campo del constructor,
      // los valores huérfanos del controller se descartan al guardar
      // (no se arrastran indefinidamente en cada edición).
      final schema = ref.read(formSchemaProvider('sales')).valueOrNull;
      final allowedIds = schema?.fields
              .where((f) => !f.coreField)
              .map((f) => f.id)
              .toSet() ??
          const <String>{};
      final customFields = <String, dynamic>{};
      _customFieldsController.values.forEach((k, v) {
        if (!allowedIds.contains(k)) return;
        if (v == null) return;
        if (v is String && v.isEmpty) return;
        customFields[k] = v;
      });

      if (_isEdit) {
        await ref.read(salesRepositoryProvider).updateSale(
              widget.editingSale!.id,
              date: _date,
              documentType: _documentType,
              documentNumber: _docNumberCtrl.text.trim(),
              providerName: _provider!,
              material: _material!,
              materialVariant: _materialVariant,
              unit: _unit,
              quantity: quantity,
              unitPrice: unitPrice,
              paymentMethod: _paymentMethod,
              payerName: _payer!,
              customFields: customFields,
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Venta actualizada.')),
          );
          context.pop();
        }
      } else {
        final sale = await ref.read(salesRepositoryProvider).createSale(
              date: _date,
              documentType: _documentType,
              documentNumber: _docNumberCtrl.text.trim(),
              providerName: _provider!,
              material: _material!,
              materialVariant: _materialVariant,
              unit: _unit,
              quantity: quantity,
              unitPrice: unitPrice,
              paymentMethod: _paymentMethod,
              payerName: _payer!,
              createdBy: profile.uid,
              createdByName: profile.fullName,
              customFields: customFields,
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Venta ${sale.consecutive} registrada.')),
          );
          context.pop();
        }
      }
    } catch (e) {
      setState(() => _formError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar venta' : 'Nueva venta'),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + keyboardInset),
            children: [
              if (_isEdit) ...[
                _ConsecutiveBadge(consecutive: widget.editingSale!.consecutive),
                const SizedBox(height: 16),
              ],
              const SectionLabel('Información de la venta'),
              const SizedBox(height: 8),
              _DateField(value: _date, onTap: _pickDate),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _documentType,
                decoration:
                    const InputDecoration(labelText: 'Tipo de documento'),
                items: const [
                  DropdownMenuItem(value: 'Cédula', child: Text('Cédula')),
                  DropdownMenuItem(value: 'NIT', child: Text('NIT')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _documentType = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _docNumberCtrl,
                keyboardType: TextInputType.text,
                decoration:
                    const InputDecoration(labelText: 'Número de documento'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Este campo es obligatorio.'
                    : null,
              ),
              const SizedBox(height: 12),
              MasterListField(
                listId: 'providers',
                label: 'Nombre del cliente',
                initialValue: _provider,
                required: true,
                onChanged: (v) => setState(() => _provider = v),
                helperText: 'Si no existe, escríbelo y queda como sugerencia.',
              ),
              const SizedBox(height: 24),
              const SectionLabel('Material y cantidad'),
              const SizedBox(height: 8),
              MasterListField(
                listId: 'materials',
                label: 'Material',
                initialValue: _material,
                required: true,
                onChanged: (v) => setState(() {
                  _material = v;
                  if (v != _laminaMaterial) _materialVariant = null;
                }),
              ),
              if (_material == _laminaMaterial) ...[
                const SizedBox(height: 12),
                MasterListField(
                  listId: 'lamina_brands',
                  label: 'Tipo de lámina',
                  initialValue: _materialVariant,
                  onChanged: (v) => setState(() => _materialVariant = v),
                ),
              ],
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final isAdmin = ref.watch(currentProfileProvider.select(
                    (a) => a.valueOrNull?.role == AppRole.admin,
                  ));
                  if (!isAdmin) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MasterListField(
                      listId: 'units',
                      label: 'Unidad de medida',
                      initialValue: _unit,
                      required: true,
                      allowSuggestions: false,
                      onChanged: (v) =>
                          setState(() => _unit = v ?? _defaultUnit),
                    ),
                  );
                },
              ),
              TextFormField(
                controller: _quantityCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  helperText: _unit,
                ),
                validator: _validatePositiveNumber,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitPriceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Valor unitario',
                  prefixText: r'$ ',
                ),
                validator: _validatePositiveNumber,
              ),
              const SizedBox(height: 12),
              _TotalCard(
                quantityCtrl: _quantityCtrl,
                unitPriceCtrl: _unitPriceCtrl,
              ),
              const SizedBox(height: 24),
              const SectionLabel('Pago'),
              const SizedBox(height: 8),
              MasterListField(
                listId: 'payment_methods',
                label: 'Método de pago',
                initialValue: _paymentMethod,
                required: true,
                allowSuggestions: false,
                onChanged: (v) =>
                    setState(() => _paymentMethod = v ?? _defaultPaymentMethod),
              ),
              const SizedBox(height: 12),
              MasterListField(
                listId: 'payers',
                label: 'Quién recibe',
                initialValue: _payer,
                required: true,
                onChanged: (v) => setState(() => _payer = v),
                helperText: 'Si no existe, escríbelo y queda como sugerencia.',
              ),
              // Campos custom definidos por el admin en el constructor de
              // formularios. Solo aparecen los que el rol puede ver.
              _CustomFieldsBlock(controller: _customFieldsController),
              if (_formError != null) ...[
                const SizedBox(height: 16),
                FormErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 24),
              LoadingButton(
                onPressed: _submit,
                loading: _saving,
                label: _isEdit ? 'Guardar cambios' : 'Registrar venta',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bloque que renderiza los campos custom (no-core) del schema de ventas.
/// Si el admin no agregó nada, no ocupa espacio.
class _CustomFieldsBlock extends ConsumerWidget {
  const _CustomFieldsBlock({required this.controller});

  final DynamicFormController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schemaAsync = ref.watch(formSchemaProvider('sales'));
    return schemaAsync.maybeWhen(
      data: (schema) {
        final custom = schema.fields.where((f) => !f.coreField).toList();
        if (custom.isEmpty) return const SizedBox.shrink();
        // Construye un sub-schema con solo los custom para reusar el
        // renderer.
        final subSchema = FormSchema(
          id: schema.id,
          module: schema.module,
          version: schema.version,
          fields: custom,
          updatedAt: schema.updatedAt,
          updatedBy: schema.updatedBy,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const SectionLabel('Campos adicionales'),
            const SizedBox(height: 8),
            DynamicFormRenderer(
              schema: subSchema,
              controller: controller,
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

String? _validatePositiveNumber(String? v) {
  if (v == null || v.trim().isEmpty) return 'Ingresa un valor.';
  final n = num.tryParse(v.replaceAll(',', '.'));
  if (n == null || n <= 0) return 'Valor inválido.';
  return null;
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap});
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Fecha',
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: Text(formatDate(value)),
      ),
    );
  }
}

/// Card del total. Escucha ambos controllers vía ListenableBuilder, así
/// solo este widget rebuildea cuando cambia el texto, no toda la pantalla.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.quantityCtrl,
    required this.unitPriceCtrl,
  });

  final TextEditingController quantityCtrl;
  final TextEditingController unitPriceCtrl;

  num? _compute() {
    final q = num.tryParse(quantityCtrl.text.replaceAll(',', '.'));
    final p = num.tryParse(unitPriceCtrl.text.replaceAll(',', '.'));
    if (q == null || p == null) return null;
    return q * p;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([quantityCtrl, unitPriceCtrl]),
      builder: (context, _) {
        final total = _compute();
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
                      'Valor total',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        total == null ? 'Pendiente' : formatCop(total),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConsecutiveBadge extends StatelessWidget {
  const _ConsecutiveBadge({required this.consecutive});
  final String consecutive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tag, size: 14, color: theme.colorScheme.onPrimary),
          const SizedBox(width: 4),
          Text(
            consecutive,
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
