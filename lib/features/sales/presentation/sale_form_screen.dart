import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/duplicate_check.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../admin/data/master_lists_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../form_builder/data/form_schema_repository.dart';
import '../../form_builder/domain/form_schema.dart';
import '../../form_builder/presentation/dynamic_form_renderer.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';

const _defaultUnit = 'Kilogramos';

/// Modo de pago. Lo escogemos al renderizar el formulario y derivamos
/// `paymentMethod` (string que se persiste) de aquí al guardar.
enum _PaymentMode {
  /// 100% en efectivo. paymentMethod = 'Efectivo'.
  cash,

  /// 100% por transferencia (Bancolombia, Nequi, etc.).
  /// paymentMethod = 'Transferencia'.
  transfer,

  /// Una parte en efectivo y otra por transferencia.
  /// paymentMethod = 'Mixto'.
  mixed,
}

extension _PaymentModeExt on _PaymentMode {
  /// String que se persiste en `paymentMethod` y respeta los valores
  /// históricos ('Efectivo', 'Transferencia', 'Mixto').
  String get paymentMethodValue {
    return switch (this) {
      _PaymentMode.cash => 'Efectivo',
      _PaymentMode.transfer => 'Transferencia',
      _PaymentMode.mixed => 'Mixto',
    };
  }
}

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
  // Inputs solo para el modo de pago Mixto. En Efectivo/Transferencia
  // se calcula automáticamente (todo o nada al respectivo bucket).
  final _cashAmountCtrl = TextEditingController();
  final _transferAmountCtrl = TextEditingController();

  DateTime _date = AppClock.now();
  String _documentType = 'Cédula';
  String? _provider;
  String? _material;
  String? _materialVariant;
  String _unit = _defaultUnit;
  _PaymentMode _paymentMode = _PaymentMode.cash;
  String? _transferDestination;
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
      // Reconstruimos el modo de pago a partir de los campos guardados.
      // Ventas viejas (sin cashAmount/transferAmount) caen al método
      // string ('Efectivo' o 'Transferencia') y prellenamos el destino
      // si la venta era transferencia con destino conocido.
      _paymentMode = _inferPaymentMode(s);
      _transferDestination = s.transferDestination;
      if (_paymentMode == _PaymentMode.mixed) {
        _cashAmountCtrl.text = (s.cashAmount ?? 0).toString();
        _transferAmountCtrl.text = (s.transferAmount ?? 0).toString();
      }
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
    _cashAmountCtrl.dispose();
    _transferAmountCtrl.dispose();
    _customFieldsController.dispose();
    super.dispose();
  }

  void _setError(String msg) {
    setState(() => _formError = msg);
  }

  /// Mapea una venta existente (que puede tener el modelo viejo o el
  /// nuevo) al modo de pago actual del form. Prioridad:
  ///   1. Si tiene cashAmount Y transferAmount con ambos > 0 → mixed
  ///   2. Si paymentMethod == 'Mixto' (compat por si se guardó sin
  ///      desglose) → mixed
  ///   3. Si paymentMethod == 'Transferencia' → transfer
  ///   4. Cualquier otra cosa (Efectivo) → cash
  _PaymentMode _inferPaymentMode(Sale s) {
    final cash = s.cashAmount ?? 0;
    final transfer = s.transferAmount ?? 0;
    if (cash > 0 && transfer > 0) return _PaymentMode.mixed;
    if (s.paymentMethod.toLowerCase() == 'mixto') return _PaymentMode.mixed;
    if (s.paymentMethod.toLowerCase() == 'transferencia') {
      return _PaymentMode.transfer;
    }
    return _PaymentMode.cash;
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

    // Anti-duplicados (última línea de defensa antes de escribir la
    // venta): si "Cliente" o "Quién recibe" se parecen sospechosamente
    // a alguien existente y el field no logró auto-snap, abrimos un
    // modal para que el usuario confirme cuál usar. Si cancela, no
    // guardamos.
    final schema = ref.read(formSchemaProvider('sales')).valueOrNull;
    final providerListId = schema?.fields
            .firstWhereOrNull((f) => f.id == 'providerName')
            ?.masterListId ??
        'providers';
    final payerListId = schema?.fields
            .firstWhereOrNull((f) => f.id == 'payerName')
            ?.masterListId ??
        'payers';

    final candidates = <DuplicateCandidate>[
      if (_provider != null && _provider!.isNotEmpty)
        DuplicateCandidate(
          label: 'Cliente',
          value: _provider!,
          listId: providerListId,
        ),
      if (_payer != null && _payer!.isNotEmpty)
        DuplicateCandidate(
          label: 'Quién recibe',
          value: _payer!,
          listId: payerListId,
        ),
    ];
    if (candidates.isNotEmpty) {
      final resolved = await confirmFreeTextValues(context, ref, candidates);
      if (!mounted) return;
      if (resolved == null) return; // usuario canceló el modal
      _provider = resolved['Cliente'] ?? _provider;
      _payer = resolved['Quién recibe'] ?? _payer;
    }

    final quantity = num.parse(_quantityCtrl.text.replaceAll(',', '.'));
    final unitPrice = num.parse(_unitPriceCtrl.text.replaceAll(',', '.'));
    final totalValue = quantity * unitPrice;

    // Calcula los montos cash/transfer según el modo. En Mixto los
    // valores los digita el usuario y se valida que sumen el total
    // (con tolerancia de 1 peso para evitar problemas de redondeo).
    num? cashAmount;
    num? transferAmount;
    String? transferDestination;

    switch (_paymentMode) {
      case _PaymentMode.cash:
        cashAmount = totalValue;
        transferAmount = null;
        transferDestination = null;
      case _PaymentMode.transfer:
        cashAmount = null;
        transferAmount = totalValue;
        transferDestination = _transferDestination;
        if (transferDestination == null || transferDestination.isEmpty) {
          _setError('Selecciona el destino de la transferencia.');
          return;
        }
      case _PaymentMode.mixed:
        final cashStr = _cashAmountCtrl.text.replaceAll(',', '.').trim();
        final transferStr =
            _transferAmountCtrl.text.replaceAll(',', '.').trim();
        final cash = num.tryParse(cashStr);
        final transfer = num.tryParse(transferStr);
        if (cash == null || transfer == null || cash < 0 || transfer < 0) {
          _setError('Ingresa los montos en efectivo y por transferencia.');
          return;
        }
        if ((cash + transfer - totalValue).abs() > 1) {
          _setError(
            'La suma de efectivo (${formatCop(cash)}) más '
            'transferencia (${formatCop(transfer)}) debe ser igual al '
            'total (${formatCop(totalValue)}).',
          );
          return;
        }
        cashAmount = cash;
        transferAmount = transfer;
        transferDestination = _transferDestination;
        if (transferDestination == null || transferDestination.isEmpty) {
          _setError('Selecciona el destino de la transferencia.');
          return;
        }
    }

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
              paymentMethod: _paymentMode.paymentMethodValue,
              cashAmount: cashAmount,
              clearCashAmount: cashAmount == null,
              transferAmount: transferAmount,
              clearTransferAmount: transferAmount == null,
              transferDestination: transferDestination,
              clearTransferDestination: transferDestination == null,
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
              paymentMethod: _paymentMode.paymentMethodValue,
              cashAmount: cashAmount,
              transferAmount: transferAmount,
              transferDestination: transferDestination,
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
    final schemaAsync = ref.watch(formSchemaProvider('sales'));
    final role = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.role,
    ),);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar venta' : 'Nueva venta'),
        actions: const [ThemeModeIconButton()],
      ),
      body: schemaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(error: e),
        data: (schema) => AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + keyboardInset),
              children: [
                if (_isEdit) ...[
                  _ConsecutiveBadge(
                      consecutive: widget.editingSale!.consecutive,),
                  const SizedBox(height: 16),
                ],
                ..._renderSchemaFields(schema, role),
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
      ),
    );
  }

  /// Renderiza los campos del formulario en el orden que el admin definió
  /// en el Constructor de formularios. Los campos `coreField` tienen
  /// widgets específicos con su lógica (controllers, validators,
  /// condicionales como Tipo de lámina ↔ Material LAMINA). Los campos
  /// no-core se delegan a `buildDynamicField` del renderer dinámico.
  List<Widget> _renderSchemaFields(FormSchema schema, AppRole? role) {
    final widgets = <Widget>[];
    for (final f in schema.fields) {
      // Visibilidad por rol según el schema. Si el campo no está marcado
      // como visible para el rol activo, lo omitimos por completo.
      if (role != null && !f.visibleToRoles.contains(role.id)) continue;

      Widget? w;
      if (f.coreField) {
        w = _buildCoreField(f);
      } else {
        w = buildDynamicField(
          field: f,
          controller: _customFieldsController,
          role: role,
        );
      }
      if (w == null) continue;

      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 12));
      widgets.add(w);
    }
    return widgets;
  }

  /// Mapea cada `id` de campo core al widget que lleva su lógica
  /// específica. Devuelve `null` si el campo está oculto por una
  /// condición (ej. Tipo de lámina solo aplica si Material == LAMINA).
  Widget? _buildCoreField(FieldDefinition f) {
    switch (f.id) {
      case 'date':
        return _DateField(value: _date, onTap: _pickDate);
      case 'documentType':
        return DropdownButtonFormField<String>(
          initialValue: _documentType,
          decoration: InputDecoration(labelText: f.label),
          items: const [
            DropdownMenuItem(value: 'Cédula', child: Text('Cédula')),
            DropdownMenuItem(value: 'NIT', child: Text('NIT')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _documentType = v);
          },
        );
      case 'documentNumber':
        return TextFormField(
          controller: _docNumberCtrl,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(labelText: f.label),
          validator: (v) => (f.required && (v == null || v.trim().isEmpty))
              ? 'Este campo es obligatorio.'
              : null,
        );
      case 'providerName':
        return MasterListField(
          listId: f.masterListId ?? 'providers',
          label: f.label,
          initialValue: _provider,
          required: f.required,
          onChanged: (v) => setState(() => _provider = v),
          helperText:
              f.helperText ?? 'Si no existe, escríbelo y queda como sugerencia.',
        );
      case 'material':
        return MasterListField(
          listId: f.masterListId ?? 'materials',
          label: f.label,
          initialValue: _material,
          required: f.required,
          // Al cambiar de material, reseteamos el subtipo: cada material
          // tiene sus propios subtipos y los del anterior pueden no
          // aplicar. Si vuelven al mismo material el usuario reescoge.
          onChanged: (v) => setState(() {
            _material = v;
            _materialVariant = null;
          }),
        );
      case 'materialVariant':
        // Genérico: el campo aparece para CUALQUIER material que tenga
        // subtipos registrados en el catálogo (no solo LAMINA). Si el
        // material seleccionado no tiene subtipos, ocultamos el campo
        // (return null) para no ensuciar el form.
        final mat = _material;
        if (mat == null || mat.isEmpty) return null;
        final variantListId = f.masterListId ?? 'lamina_brands';
        final variantsAsync = ref.watch(
          masterListItemsProvider(
            MasterListItemsQuery(listId: variantListId, parent: mat),
          ),
        );
        // Mientras carga la primera vez NO mostramos el campo (evita
        // un parpadeo). Una vez con data: mostramos solo si hay >= 1.
        final variants = variantsAsync.valueOrNull;
        if (variants == null || variants.isEmpty) return null;
        return MasterListField(
          listId: variantListId,
          parent: mat,
          label: f.label,
          initialValue: _materialVariant,
          onChanged: (v) => setState(() => _materialVariant = v),
        );
      case 'unit':
        return MasterListField(
          listId: f.masterListId ?? 'units',
          label: f.label,
          initialValue: _unit,
          required: f.required,
          allowSuggestions: false,
          onChanged: (v) => setState(() => _unit = v ?? _defaultUnit),
        );
      case 'quantity':
        return TextFormField(
          controller: _quantityCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: f.label,
            helperText: f.helperText ?? _unit,
          ),
          validator: _validatePositiveNumber,
        );
      case 'unitPrice':
        return TextFormField(
          controller: _unitPriceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: f.label,
            prefixText: r'$ ',
          ),
          validator: _validatePositiveNumber,
        );
      case 'totalValue':
        return _TotalCard(
          label: f.label,
          quantityCtrl: _quantityCtrl,
          unitPriceCtrl: _unitPriceCtrl,
        );
      case 'paymentMethod':
        return _PaymentSection(
          label: f.label,
          mode: _paymentMode,
          transferDestination: _transferDestination,
          cashAmountCtrl: _cashAmountCtrl,
          transferAmountCtrl: _transferAmountCtrl,
          quantityCtrl: _quantityCtrl,
          unitPriceCtrl: _unitPriceCtrl,
          onModeChanged: (v) {
            setState(() {
              _paymentMode = v;
              // Al cambiar a Solo efectivo limpiamos los campos de
              // transferencia. Al cambiar a Solo transferencia
              // limpiamos los inputs de mixto. En Mixto dejamos
              // todo lo que el usuario ya tipeó.
              if (v == _PaymentMode.cash) {
                _transferDestination = null;
                _cashAmountCtrl.clear();
                _transferAmountCtrl.clear();
              } else if (v == _PaymentMode.transfer) {
                _cashAmountCtrl.clear();
                _transferAmountCtrl.clear();
              }
            });
          },
          onDestinationChanged: (v) =>
              setState(() => _transferDestination = v),
        );
      case 'payerName':
        return MasterListField(
          listId: f.masterListId ?? 'payers',
          label: f.label,
          initialValue: _payer,
          required: f.required,
          onChanged: (v) => setState(() => _payer = v),
          helperText:
              f.helperText ?? 'Si no existe, escríbelo y queda como sugerencia.',
        );
      default:
        return null;
    }
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
    required this.label,
    required this.quantityCtrl,
    required this.unitPriceCtrl,
  });

  final String label;
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
                      label,
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

/// Sección de pago — reemplaza el simple dropdown de método de pago
/// con un selector de modo (Efectivo / Transferencia / Mixto), sus
/// inputs específicos según el modo elegido, y el dropdown de destino
/// de transferencia (lista maestra `transfer_destinations`) cuando
/// aplica.
class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.label,
    required this.mode,
    required this.transferDestination,
    required this.cashAmountCtrl,
    required this.transferAmountCtrl,
    required this.quantityCtrl,
    required this.unitPriceCtrl,
    required this.onModeChanged,
    required this.onDestinationChanged,
  });

  final String label;
  final _PaymentMode mode;
  final String? transferDestination;
  final TextEditingController cashAmountCtrl;
  final TextEditingController transferAmountCtrl;
  // Para mostrar el total esperado y la diferencia en modo Mixto.
  final TextEditingController quantityCtrl;
  final TextEditingController unitPriceCtrl;
  final ValueChanged<_PaymentMode> onModeChanged;
  final ValueChanged<String?> onDestinationChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_PaymentMode>(
            segments: const [
              ButtonSegment(
                value: _PaymentMode.cash,
                label: Text('Efectivo'),
                icon: Icon(Icons.payments_outlined),
              ),
              ButtonSegment(
                value: _PaymentMode.transfer,
                label: Text('Transferencia'),
                icon: Icon(Icons.account_balance_outlined),
              ),
              ButtonSegment(
                value: _PaymentMode.mixed,
                label: Text('Mixto'),
                icon: Icon(Icons.call_split_outlined),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
        ),
        if (mode == _PaymentMode.transfer) ...[
          const SizedBox(height: 12),
          MasterListField(
            listId: 'transfer_destinations',
            label: 'Destino de transferencia',
            initialValue: transferDestination,
            required: true,
            onChanged: onDestinationChanged,
            helperText: 'Bancolombia, Nequi, Daviplata, etc. Si no existe, '
                'escríbelo y queda como sugerencia.',
          ),
        ],
        if (mode == _PaymentMode.mixed) ...[
          const SizedBox(height: 12),
          _MixedAmountsRow(
            cashAmountCtrl: cashAmountCtrl,
            transferAmountCtrl: transferAmountCtrl,
            quantityCtrl: quantityCtrl,
            unitPriceCtrl: unitPriceCtrl,
          ),
          const SizedBox(height: 12),
          MasterListField(
            listId: 'transfer_destinations',
            label: 'Destino de transferencia',
            initialValue: transferDestination,
            required: true,
            onChanged: onDestinationChanged,
            helperText: 'Bancolombia, Nequi, Daviplata, etc. Si no existe, '
                'escríbelo y queda como sugerencia.',
          ),
        ],
      ],
    );
  }
}

/// Inputs de monto en efectivo + monto por transferencia para el modo
/// Mixto. Muestra debajo el total esperado y la diferencia con un
/// color que cambia según si la suma cuadra (verde) o no (naranja).
class _MixedAmountsRow extends StatelessWidget {
  const _MixedAmountsRow({
    required this.cashAmountCtrl,
    required this.transferAmountCtrl,
    required this.quantityCtrl,
    required this.unitPriceCtrl,
  });

  final TextEditingController cashAmountCtrl;
  final TextEditingController transferAmountCtrl;
  final TextEditingController quantityCtrl;
  final TextEditingController unitPriceCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        cashAmountCtrl,
        transferAmountCtrl,
        quantityCtrl,
        unitPriceCtrl,
      ]),
      builder: (context, _) {
        final q = num.tryParse(quantityCtrl.text.replaceAll(',', '.'));
        final p = num.tryParse(unitPriceCtrl.text.replaceAll(',', '.'));
        final total = (q != null && p != null) ? q * p : null;
        final cash = num.tryParse(cashAmountCtrl.text.replaceAll(',', '.'));
        final transfer =
            num.tryParse(transferAmountCtrl.text.replaceAll(',', '.'));
        num? diff;
        if (total != null && cash != null && transfer != null) {
          diff = total - cash - transfer;
        }
        final ok = diff != null && diff.abs() <= 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: cashAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Efectivo',
                      prefixText: r'$ ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: transferAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Transferencia',
                      prefixText: r'$ ',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Hint con el total esperado y diferencia. Verde si cuadra,
            // ámbar si no, gris si todavía no hay total.
            Builder(builder: (_) {
              if (total == null) {
                return Text(
                  'Ingresa cantidad y valor unitario para validar la suma.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                );
              }
              final color = ok
                  ? theme.colorScheme.primary
                  : theme.colorScheme.tertiary;
              final diffText = diff == null
                  ? ''
                  : (ok
                      ? '✓ Suma cuadra'
                      : (diff > 0
                          ? '· Falta ${formatCop(diff)}'
                          : '· Sobra ${formatCop(-diff)}'));
              return Text(
                'Total: ${formatCop(total)} $diffText',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              );
            },),
          ],
        );
      },
    );
  }
}
