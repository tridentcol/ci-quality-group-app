import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import '../../core/theme/app_colors.dart';

/// Pill chip semántico para representar un rol con color consistente.
/// Reemplaza los `Colors.blueAccent / deepOrangeAccent` sueltos en
/// users_screen y otros lados.
class RolePill extends StatelessWidget {
  const RolePill({super.key, required this.role, this.compact = false});

  final AppRole role;

  /// Si `true`, solo muestra el avatar/circle con la inicial. Para
  /// trailings de cards.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorFor(role, theme.brightness);
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          role.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        role.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// `treeGreen` (#1F5128) es muy oscuro contra fondos oscuros y se pierde,
  /// así que en dark mode el admin usa `leafGreen`. Los otros dos roles
  /// (info azul, warning amarillo) tienen contraste decente en ambos modos.
  static Color _colorFor(AppRole role, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (role) {
      AppRole.admin => isDark ? AppColors.leafGreen : AppColors.treeGreen,
      AppRole.sales => AppColors.info,
      AppRole.hours => AppColors.warning,
      AppRole.cajero => const Color(0xFFE6A100),
      AppRole.auditor => const Color(0xFF7C3AED), // morado profundo
    };
  }

  /// Color asociado al rol, expuesto para CircleAvatar y similares.
  /// Requiere el brightness del tema actual para contrastar correctamente.
  static Color colorOf(AppRole role, Brightness brightness) =>
      _colorFor(role, brightness);
}
