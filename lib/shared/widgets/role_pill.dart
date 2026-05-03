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
    final color = _colorFor(role);
    final theme = Theme.of(context);
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

  static Color _colorFor(AppRole role) => switch (role) {
        AppRole.admin => AppColors.treeGreen,
        AppRole.sales => AppColors.info,
        AppRole.hours => AppColors.warning,
      };

  /// Color asociado al rol, expuesto para CircleAvatar y similares.
  static Color colorOf(AppRole role) => _colorFor(role);
}
