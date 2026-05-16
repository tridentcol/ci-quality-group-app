import 'package:flutter/material.dart';

import '../../../../core/utils/dates.dart';
import '../../../../core/utils/money.dart';
import '../../../../shared/widgets/state_pill.dart';
import '../../domain/sale.dart';

/// Tarjeta compacta para listar una venta.
class SaleCard extends StatelessWidget {
  const SaleCard({super.key, required this.sale, this.onTap});

  final Sale sale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final material = sale.hasMultipleItems
        ? '${sale.items.length} materiales · ${sale.items.first.displayLabel}'
            ' + ${sale.items.length - 1} más'
        : sale.items.first.displayLabel;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      sale.consecutive,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatePill(state: sale.state, compact: true),
                  const Spacer(),
                  Text(
                    formatDate(sale.date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                sale.providerName,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                material,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cantidad',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        Text(
                          _quantityLabel(sale),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        Text(
                          formatCop(sale.totalValue),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sale.paymentMethod.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        sale.paymentMethod,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _unitShort(String unit) => switch (unit.toLowerCase()) {
      'kilogramos' => 'kg',
      _ => unit,
    };

/// Etiqueta de cantidad para la card. Con un solo material muestra
/// "100 kg"; con varios suma por unidad → "100 kg + 5 un".
String _quantityLabel(Sale sale) {
  if (!sale.hasMultipleItems) {
    return '${sale.quantity} ${_unitShort(sale.unit)}';
  }
  final byUnit = <String, num>{};
  for (final i in sale.items) {
    byUnit.update(i.unit, (v) => v + i.quantity, ifAbsent: () => i.quantity);
  }
  return byUnit.entries
      .map((e) => '${e.value} ${_unitShort(e.key)}')
      .join(' + ');
}
