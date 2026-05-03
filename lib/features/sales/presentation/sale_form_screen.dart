import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../auth/data/auth_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';

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

  DateTime _date = DateTime.now();
  String _documentType = 'Cédula';
  String? _provider;
  String? _material;
  String? _materialVariant;
  String _unit = 'Kilogramos';
  String _paymentMethod = 'Efectivo';
  String? _payer;

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
      _material = s.material;
      _materialVariant = s.materialVariant;
      _unit = s.unit;
      _quantityCtrl.text = s.quantity.toString();
      _unitPriceCtrl.text = s.unitPrice.toString();
      _paymentMethod = s.paymentMethod;
      _payer = s.payerName;
    }
    _quantityCtrl.addListener(_recompute);
    _unitPriceCtrl.addListener(_recompute);
  }

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    _quantityCtrl.dispose();
    _unitPriceCtrl.dispose();
    super.dispose();
  }

  void _recompute() => setState(() {});

  num? get _computedTotal {
    final q = num.tryParse(_quantityCtrl.text.replaceAll(',', '.'));
    final p = num.tryParse(_unitPriceCtrl.text.replaceAll(',', '.'));
    if (q == null || p == null) return null;
    return q * p;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Venta ${sale.consecutive} registrada.')),
          );
          context.pop();
        }
      }
    } catch (e) {
      setState(() => _formError = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar venta' : 'Nueva venta'),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_isEdit) _ConsecutiveBadge(consecutive: widget.editingSale!.consecutive),
              if (_isEdit) const SizedBox(height: 16),
              _SectionLabel('Información de la venta'),
              const SizedBox(height: 8),
              _DateField(value: _date, onTap: _pickDate),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _documentType,
                decoration: const InputDecoration(labelText: 'Tipo de documento'),
                items: const [
                  DropdownMenuItem(value: 'Cédula', child: Text('Cédula')),
                  DropdownMenuItem(value: 'NIT', child: Text('NIT')),
                ],
                onChanged: (v) => setState(() => _documentType = v ?? 'Cédula'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _docNumberCtrl,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(labelText: 'Número de documento'),
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
              _SectionLabel('Material y cantidad'),
              const SizedBox(height: 8),
              MasterListField(
                listId: 'materials',
                label: 'Material',
                initialValue: _material,
                required: true,
                onChanged: (v) => setState(() {
                  _material = v;
                  if (v != 'LAMINA') _materialVariant = null;
                }),
              ),
              if (_material == 'LAMINA') ...[
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
                  final profile = ref.watch(currentProfileProvider).valueOrNull;
                  final isAdmin = profile?.role.id == 'admin';
                  if (!isAdmin) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MasterListField(
                      listId: 'units',
                      label: 'Unidad de medida',
                      initialValue: _unit,
                      required: true,
                      allowSuggestions: false,
                      onChanged: (v) => setState(() => _unit = v ?? 'Kilogramos'),
                    ),
                  );
                },
              ),
              TextFormField(
                controller: _quantityCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  helperText: _unit,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresa la cantidad.';
                  final n = num.tryParse(v.replaceAll(',', '.'));
                  if (n == null || n <= 0) return 'Cantidad inválida.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitPriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Valor unitario',
                  prefixText: r'$ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresa el valor unitario.';
                  final n = num.tryParse(v.replaceAll(',', '.'));
                  if (n == null || n <= 0) return 'Valor inválido.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _TotalCard(total: _computedTotal),
              const SizedBox(height: 24),
              _SectionLabel('Pago'),
              const SizedBox(height: 8),
              MasterListField(
                listId: 'payment_methods',
                label: 'Método de pago',
                initialValue: _paymentMethod,
                required: true,
                allowSuggestions: false,
                onChanged: (v) => setState(() => _paymentMethod = v ?? 'Efectivo'),
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
              if (_formError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.4),
                      )
                    : Text(_isEdit ? 'Guardar cambios' : 'Registrar venta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          ),
    );
  }
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

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total});
  final num? total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Text('Valor total',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    )),
                const SizedBox(height: 2),
                Text(
                  total == null ? 'Pendiente' : formatCop(total!),
                  style: theme.textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsecutiveBadge extends StatelessWidget {
  const _ConsecutiveBadge({required this.consecutive});
  final String consecutive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tag, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            consecutive,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
