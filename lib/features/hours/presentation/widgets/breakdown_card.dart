import 'package:flutter/material.dart';

import '../../domain/hours_categories.dart';

/// Tarjeta que muestra el desglose por categoría legal de un registro
/// (o de un acumulado en un rango de fechas).
class BreakdownCard extends StatelessWidget {
  const BreakdownCard({
    super.key,
    required this.breakdown,
    this.title = 'Desglose',
    this.compact = false,
  });

  final HoursBreakdown breakdown;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = [
      HoursCategory.ordinary,
      HoursCategory.extraDay,
      HoursCategory.extraNight,
      HoursCategory.sundayOrdinary,
      HoursCategory.extraSundayDay,
      HoursCategory.extraSundayNight,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(title, style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  formatHours(breakdown.totalPaid),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...categories.map((c) {
              final value = breakdown.get(c);
              if (compact && value == Duration.zero) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: value == Duration.zero
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4)
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      formatHours(value),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: value == Duration.zero
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                            : theme.colorScheme.onSurface,
                        fontWeight: value == Duration.zero
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (breakdown.get(HoursCategory.lunch) > Duration.zero) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(
                    Icons.restaurant_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Almuerzo descontado',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Text(
                    formatHours(breakdown.get(HoursCategory.lunch)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
