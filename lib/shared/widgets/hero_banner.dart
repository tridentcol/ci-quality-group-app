import 'package:flutter/material.dart';

/// Banner verde con KPI principal. Reemplaza las 5+ copias del patrón
/// (rounded green card con título + valor grande + sub-stats) que estaban
/// regadas en sales_list, sales_home, hours_admin, hours_home, worker_day.
class HeroBanner extends StatelessWidget {
  const HeroBanner({
    super.key,
    required this.title,
    required this.primaryValue,
    this.secondary,
    this.children = const [],
    this.icon,
  });

  /// Texto pequeño superior (ej. "Total del rango").
  final String title;

  /// Valor principal grande (ej. monto, contador).
  final String primaryValue;

  /// Sub-texto opcional debajo del primaryValue.
  final String? secondary;

  /// Widgets adicionales (chips, etc.) debajo de toda la cabecera.
  final List<Widget> children;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: onPrimary.withValues(alpha: 0.85), size: 18),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: onPrimary.withValues(alpha: 0.75)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              primaryValue,
              maxLines: 1,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(color: onPrimary, fontWeight: FontWeight.w700),
            ),
          ),
          if (secondary != null) ...[
            const SizedBox(height: 4),
            Text(
              secondary!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: onPrimary.withValues(alpha: 0.75)),
            ),
          ],
          if (children.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...children,
          ],
        ],
      ),
    );
  }
}
