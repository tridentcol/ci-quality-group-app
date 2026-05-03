import 'package:flutter/material.dart';

import '../../../../core/utils/dates.dart';
import '../../../../core/utils/money.dart';
import '../../domain/sale.dart';

/// Tarjeta compacta para listar una venta.
class SaleCard extends StatelessWidget {
  const SaleCard({super.key, required this.sale, this.onTap});

  final Sale sale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final material = sale.materialVariant != null
        ? '${sale.material} · ${sale.materialVariant}'
        : sale.material;
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
                          '${sale.quantity} ${_unitShort(sale.unit)}',
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
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
