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
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../admin/data/master_lists_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';

const _defaultUnit = 'Kilogramos';

/// Pantalla para crear una nueva venta o editar una existente (si está
/// dentro de la ventana fija de 24 h desde `createdAt` o el usuario es
/// admin).
///
/// El formulario soporta uno o varios materiales por venta. El primer
/// material es obligatorio; los adicionales se agregan con el botón
/// "Agregar otro material" y se pueden quitar.
class SaleFormScreen extends ConsumerStatefulWidget {
  const SaleFormScreen({super.key, this.editingSale});

  final Sale? editingSale;

  @override
  ConsumerState<SaleFormScreen> createState() => _SaleFormScreenState();
}

class _SaleFormScreenState extends ConsumerState<SaleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _docNumberCtrl = TextEditingController();

  DateTime _date = AppClock.now();
  String _documentType = 'Cédula';
  String? _provider;

  /// Cada item del formulario lleva sus propios controllers + selección
  /// reactiva de material/variante/unidad. La lista nunca queda vacía:
  /// arrancamos siempre con un item.
  late List<_ItemFormState> _items;

  bool _saving = false;
  String? _formError;

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
      _items = s.items.map(_ItemFormState.fromSaleItem).toList();
    } else {
      _items = [_ItemFormState.empty()];
    }
  }

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  void _setError(String msg) {
    setState(() => _formError = msg);
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

  void _addItem() {
    setState(() => _items.add(_ItemFormState.empty()));
  }

  void _removeItem(int index) {
    // Bounds guard contra taps duplicados o rebuilds concurrentes:
    // si por algún motivo el index ya no está, no hacemos nada en lugar
    // de tirar RangeError.
    if (index < 0 || index >= _items.length) return;
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    // Si está editando una venta existente, verificar que la ventana de
    // 24 h no haya expirado mientras tenía el form abierto. Sin este
    // chequeo client-side, Firestore rebota el update con
    // `permission-denied` opaco; el user ve "no tienes permisos" en
    // lugar de "la ventana expiró".
    final editing = widget.editingSale;
    if (editing != null) {
      final profile = ref.read(currentProfileProvider).valueOrNull;
      final until = editing.editableUntil;
      // Admin pasa por encima de la ventana. Sales depende de ella.
      if (profile != null &&
          profile.role != AppRole.admin &&
          until != null &&
          !AppClock.now().isBefore(until)) {
        _setError(
          'La ventana de edición de 24 h ya expiró. Solo el admin puede modificar esta venta.',
        );
        return;
      }
    }

    // Validaciones de items que el FormField no cubre: que todos tengan
    // material seleccionado.
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].material == null || _items[i].material!.trim().isEmpty) {
        _setError(
          _items.length == 1
              ? 'Selecciona el material.'
              : 'Selecciona el material del item ${i + 1}.',
        );
        return;
      }
    }

    // Anti-duplicados: si el "Cliente" se parece sospechosamente a uno
    // existente, abrimos el modal para confirmar. Cancelar aborta.
    if (_provider != null && _provider!.isNotEmpty) {
      final resolved = await confirmFreeTextValues(context, ref, [
        DuplicateCandidate(
          label: 'Cliente',
          value: _provider!,
          listId: 'providers',
        ),
      ]);
      if (!mounted) return;
      if (resolved == null) return;
      _provider = resolved['Cliente'] ?? _provider;
    }

    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile == null) {
      _setError('Sesión no válida.');
      return;
    }

    final saleItems = _items.map((s) => s.toSaleItem()).toList();

    // Toda venta nueva entra al flujo de caja: arranca en `generada`,
    // sin método de pago, sin destino de transferencia, sin payerName.
    // Cajero define esos campos al registrar cada abono.
    const paymentMethodValue = '';
    const createState = SaleState.generada;

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await ref.read(salesRepositoryProvider).updateSale(
              widget.editingSale!.id,
              date: _date,
              documentType: _documentType,
              documentNumber: _docNumberCtrl.text.trim(),
              providerName: _provider!,
              items: saleItems,
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
              items: saleItems,
              paymentMethod: paymentMethodValue,
              payerName: '',
              createdBy: profile.uid,
              createdByName: profile.fullName,
              state: createState,
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
        actions: const [ThemeModeIconButton()],
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
                _ConsecutiveBadge(
                  consecutive: widget.editingSale!.consecutive,
                ),
                const SizedBox(height: 16),
              ],
              const SectionLabel('Datos generales'),
              const SizedBox(height: 8),
              _DateField(value: _date, onTap: _pickDate),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _documentType,
                decoration: const InputDecoration(labelText: 'Tipo de documento'),
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
                decoration: const InputDecoration(
                  labelText: 'Número de documento',
                ),
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
                helperText:
                    'Si no existe, escríbelo y queda como sugerencia.',
              ),
              const SizedBox(height: 24),
              ..._buildItemSections(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Agregar otro material'),
              ),
              const SizedBox(height: 16),
              _TotalCard(items: _items),
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

  List<Widget> _buildItemSections() {
    final widgets = <Widget>[];
    for (var i = 0; i < _items.length; i++) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 20));
      widgets.add(
        _ItemSection(
          index: i,
          total: _items.length,
          state: _items[i],
          onRemove: _items.length > 1 ? () => _removeItem(i) : null,
          onChanged: () => setState(() {}),
        ),
      );
    }
    return widgets;
  }
}

/// Estado mutable de un item del formulario. Empaqueta los controllers y
/// las selecciones para que la lista sea fácil de agregar/quitar sin
/// dejar controllers huérfanos.
class _ItemFormState {
  _ItemFormState({
    this.material,
    this.materialVariant,
    this.unit = _defaultUnit,
    String? quantityText,
    String? unitPriceText,
  })  : quantityCtrl = TextEditingController(text: quantityText ?? ''),
        unitPriceCtrl = TextEditingController(text: unitPriceText ?? '');

  factory _ItemFormState.empty() => _ItemFormState();

  factory _ItemFormState.fromSaleItem(SaleItem i) => _ItemFormState(
        material: i.material,
        materialVariant: i.materialVariant,
        unit: i.unit,
        quantityText: i.quantity.toString(),
        unitPriceText: i.unitPrice.toString(),
      );

  String? material;
  String? materialVariant;
  String unit;
  final TextEditingController quantityCtrl;
  final TextEditingController unitPriceCtrl;

  num get quantity =>
      num.tryParse(quantityCtrl.text.replaceAll(',', '.')) ?? 0;

  num get unitPrice =>
      num.tryParse(unitPriceCtrl.text.replaceAll(',', '.')) ?? 0;

  num get totalValue => quantity * unitPrice;

  SaleItem toSaleItem() => SaleItem(
        material: material!,
        materialVariant: materialVariant,
        unit: unit,
        quantity: quantity,
        unitPrice: unitPrice,
      );

  void dispose() {
    quantityCtrl.dispose();
    unitPriceCtrl.dispose();
  }
}

/// Bloque visual de un item del formulario. Recibe el `_ItemFormState`
/// y delega los cambios al padre vía callbacks.
class _ItemSection extends ConsumerWidget {
  const _ItemSection({
    required this.index,
    required this.total,
    required this.state,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final int total;
  final _ItemFormState state;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final showHeader = total > 1;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 18, color: theme.colorScheme.primary,),
                const SizedBox(width: 6),
                Text(
                  'Material ${index + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.delete_outline),
                    color: theme.colorScheme.error,
                    onPressed: onRemove,
                  ),
              ],
            )
          else
            const SectionLabel('Material'),
          const SizedBox(height: 8),
          MasterListField(
            listId: 'materials',
            label: 'Material',
            initialValue: state.material,
            required: true,
            onChanged: (v) {
              // Al cambiar de material, reseteamos el subtipo: cada
              // material tiene sus propios subtipos y los del anterior
              // pueden no aplicar.
              state.material = v;
              state.materialVariant = null;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          // Subtipo: aparece solo si el material seleccionado tiene
          // variantes registradas. Mientras carga la lista no se renderiza
          // para evitar parpadeo.
          if (state.material != null && state.material!.isNotEmpty)
            _VariantField(
              parentMaterial: state.material!,
              value: state.materialVariant,
              onChanged: (v) {
                state.materialVariant = v;
                onChanged();
              },
            ),
          MasterListField(
            listId: 'units',
            label: 'Unidad de medida',
            initialValue: state.unit,
            required: true,
            allowSuggestions: false,
            onChanged: (v) {
              state.unit = v ?? _defaultUnit;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: state.quantityCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Cantidad',
                    helperText: state.unit,
                  ),
                  validator: _validatePositiveNumber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: state.unitPriceCtrl,
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
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Subtotal del item, reactivo a los controllers.
          ListenableBuilder(
            listenable:
                Listenable.merge([state.quantityCtrl, state.unitPriceCtrl]),
            builder: (_, __) {
              final q = num.tryParse(
                  state.quantityCtrl.text.replaceAll(',', '.'),);
              final p = num.tryParse(
                  state.unitPriceCtrl.text.replaceAll(',', '.'),);
              final subtotal = (q != null && p != null) ? q * p : null;
              return Align(
                alignment: Alignment.centerRight,
                child: Text(
                  subtotal == null
                      ? 'Subtotal: pendiente'
                      : 'Subtotal: ${formatCop(subtotal)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Widget que muestra la lista de variantes para el material padre. Se
/// extrajo para encapsular el ref.watch del provider de subtipos y que
/// el rebuild quede acotado a este sub-arbol.
class _VariantField extends ConsumerWidget {
  const _VariantField({
    required this.parentMaterial,
    required this.value,
    required this.onChanged,
  });

  final String parentMaterial;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variantsAsync = ref.watch(
      masterListItemsProvider(
        MasterListItemsQuery(listId: 'lamina_brands', parent: parentMaterial),
      ),
    );
    final variants = variantsAsync.valueOrNull;
    if (variants == null || variants.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MasterListField(
        listId: 'lamina_brands',
        parent: parentMaterial,
        label: 'Tipo de material',
        initialValue: value,
        onChanged: onChanged,
      ),
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

/// Card que muestra el total de la venta. Escucha los controllers de
/// TODOS los items vía ListenableBuilder para recomputar sin disparar
/// rebuild del Scaffold entero.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.items});

  final List<_ItemFormState> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controllers = <Listenable>[];
    for (final i in items) {
      controllers
        ..add(i.quantityCtrl)
        ..add(i.unitPriceCtrl);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(controllers),
      builder: (context, _) {
        num total = 0;
        var allFilled = true;
        for (final i in items) {
          final q = num.tryParse(i.quantityCtrl.text.replaceAll(',', '.'));
          final p = num.tryParse(i.unitPriceCtrl.text.replaceAll(',', '.'));
          if (q == null || p == null) {
            allFilled = false;
            continue;
          }
          total += q * p;
        }
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
                        !allFilled && total == 0
                            ? 'Pendiente'
                            : formatCop(total),
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

