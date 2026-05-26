import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/money.dart';
import '../../../../shared/widgets/master_list_field.dart';

/// Datos crudos de pago capturados en el form de venta bajo el modo
/// "delegación caja". Inmutable; la sección lo arma a demanda y el
/// parent lo entrega al repo si valida.
class DelegationPaymentDraft {
  const DelegationPaymentDraft({
    required this.paymentMethod,
    this.cashAmount,
    this.transferAmount,
    this.transferDestination,
    this.payerName,
  });

  final String paymentMethod;
  final num? cashAmount;
  final num? transferAmount;
  final String? transferDestination;
  final String? payerName;

  /// `true` cuando ningún monto fue ingresado. Permite al parent
  /// distinguir "sales dejó la sección vacía" (válido, no se crea
  /// payment) vs "sales puso plata pero falta destino/quién recibe"
  /// (inválido).
  bool get isEmpty =>
      ((cashAmount ?? 0) == 0) && ((transferAmount ?? 0) == 0);

  num get total => (cashAmount ?? 0) + (transferAmount ?? 0);

  /// Devuelve un mensaje listo para mostrar si el draft no está
  /// completo. `null` significa "OK para enviar" o "vacío, omitir
  /// payment". El parent decide qué hacer con null + isEmpty.
  String? validate() {
    if (isEmpty) return null;
    final needsTransfer =
        paymentMethod == _methodTransfer || paymentMethod == _methodMixed;
    if (needsTransfer &&
        (transferDestination == null || transferDestination!.isEmpty)) {
      return 'Selecciona el destino de la transferencia.';
    }
    if (payerName == null || payerName!.isEmpty) {
      return 'Selecciona quién recibe.';
    }
    return null;
  }
}

enum _PayMode { cash, transfer, mixed }

const _methodCash = 'Efectivo';
const _methodTransfer = 'Transferencia';
const _methodMixed = 'Mixto';

/// Sección embebible en `SaleFormScreen` que permite al rol sales
/// capturar un pago bajo delegación caja. Opcional: si sales no llena
/// nada, el parent crea la venta sin payment.
///
/// Maneja su propio estado interno. El parent accede a los datos vía
/// [GlobalKey<SalePaymentSectionState>].
class SalePaymentSection extends StatefulWidget {
  const SalePaymentSection({
    super.key,
    this.enabled = true,
    this.onChanged,
  });

  /// Cuando `false`, los inputs quedan deshabilitados y el draft
  /// reportado es vacío. Se usa para el caso "delegación se desactivó
  /// con el form abierto".
  final bool enabled;

  /// Notifica al parent que el usuario tocó algún campo. Se llama
  /// también al limpiar (`_didFillPayment` debe reflejar el estado
  /// actual, no si tocó alguna vez).
  final VoidCallback? onChanged;

  @override
  State<SalePaymentSection> createState() => SalePaymentSectionState();
}

class SalePaymentSectionState extends State<SalePaymentSection> {
  final _amountCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  final _transferCtrl = TextEditingController();
  _PayMode _mode = _PayMode.cash;
  String? _transferDestination;
  String? _payerName;

  @override
  void initState() {
    super.initState();
    for (final c in [_amountCtrl, _cashCtrl, _transferCtrl]) {
      c.addListener(_notifyChanged);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    super.dispose();
  }

  void _notifyChanged() => widget.onChanged?.call();

  /// `true` cuando hay al menos un valor ingresado por el usuario.
  /// Útil para que el parent muestre el warning "se desactivó la
  /// delegación y vas a perder estos datos".
  bool get hasInput {
    return _amountCtrl.text.trim().isNotEmpty ||
        _cashCtrl.text.trim().isNotEmpty ||
        _transferCtrl.text.trim().isNotEmpty ||
        (_transferDestination != null && _transferDestination!.isNotEmpty) ||
        (_payerName != null && _payerName!.isNotEmpty);
  }

  num? _parseNum(TextEditingController c) =>
      num.tryParse(c.text.replaceAll(',', '.').trim());

  /// Snapshot del estado actual del form, listo para validar y enviar
  /// al repo.
  DelegationPaymentDraft currentDraft() {
    if (!widget.enabled) {
      return const DelegationPaymentDraft(paymentMethod: _methodCash);
    }
    switch (_mode) {
      case _PayMode.cash:
        final cash = _parseNum(_amountCtrl);
        return DelegationPaymentDraft(
          paymentMethod: _methodCash,
          cashAmount: cash,
          payerName: _payerName,
        );
      case _PayMode.transfer:
        final transfer = _parseNum(_amountCtrl);
        return DelegationPaymentDraft(
          paymentMethod: _methodTransfer,
          transferAmount: transfer,
          transferDestination: _transferDestination,
          payerName: _payerName,
        );
      case _PayMode.mixed:
        return DelegationPaymentDraft(
          paymentMethod: _methodMixed,
          cashAmount: _parseNum(_cashCtrl),
          transferAmount: _parseNum(_transferCtrl),
          transferDestination: _transferDestination,
          payerName: _payerName,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = const Color(0xFFE6A100); // mismo naranja del banner global

    return AbsorbPointer(
      absorbing: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.payments_outlined, color: accent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Pago en caja (opcional)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Modo delegación caja activo: puedes registrar el pago aquí '
                'mismo. Si no, deja vacío y caja lo cobra después.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_PayMode>(
                  segments: const [
                    ButtonSegment(value: _PayMode.cash, label: Text('Efectivo')),
                    ButtonSegment(
                      value: _PayMode.transfer,
                      label: Text('Transferencia'),
                    ),
                    ButtonSegment(value: _PayMode.mixed, label: Text('Mixto')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) {
                    setState(() {
                      _mode = s.first;
                      // Reset que evita arrastrar datos cuando el user
                      // cambia de método (el cashier sheet hace lo mismo).
                      if (_mode == _PayMode.cash) {
                        _cashCtrl.clear();
                        _transferCtrl.clear();
                        _transferDestination = null;
                      } else if (_mode == _PayMode.transfer) {
                        _cashCtrl.clear();
                        _transferCtrl.clear();
                      } else {
                        _amountCtrl.clear();
                      }
                    });
                    _notifyChanged();
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (_mode != _PayMode.mixed)
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    prefixText: r'$ ',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cashCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Efectivo',
                          prefixText: r'$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _transferCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Transferencia',
                          prefixText: r'$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_mode == _PayMode.transfer || _mode == _PayMode.mixed) ...[
                const SizedBox(height: 12),
                MasterListField(
                  listId: 'transfer_destinations',
                  label: 'Destino de transferencia',
                  initialValue: _transferDestination,
                  onChanged: (v) {
                    setState(() => _transferDestination = v);
                    _notifyChanged();
                  },
                ),
              ],
              const SizedBox(height: 12),
              MasterListField(
                listId: 'payers',
                label: 'Quién recibe',
                initialValue: _payerName,
                onChanged: (v) {
                  setState(() => _payerName = v);
                  _notifyChanged();
                },
                helperText: 'Persona en caja que recibe el pago.',
              ),
              const SizedBox(height: 8),
              // Total reactivo solo visible en Mixto para validar la suma
              // de un vistazo. Para Efectivo/Transferencia el `Monto` ya
              // es el total.
              if (_mode == _PayMode.mixed)
                _MixedTotalIndicator(
                  cashCtrl: _cashCtrl,
                  transferCtrl: _transferCtrl,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MixedTotalIndicator extends StatelessWidget {
  const _MixedTotalIndicator({
    required this.cashCtrl,
    required this.transferCtrl,
  });

  final TextEditingController cashCtrl;
  final TextEditingController transferCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([cashCtrl, transferCtrl]),
      builder: (_, __) {
        final cash = num.tryParse(cashCtrl.text.replaceAll(',', '.')) ?? 0;
        final transfer =
            num.tryParse(transferCtrl.text.replaceAll(',', '.')) ?? 0;
        final total = cash + transfer;
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            total == 0 ? 'Total: pendiente' : 'Total: ${formatCop(total)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
