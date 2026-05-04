import 'package:flutter/material.dart';

/// Widget del logo CI Quality Group. Elige automáticamente la variante
/// correcta según:
///   - `mark`: si es `true`, usa la versión solo-icono (grúa + hoja, sin
///     texto). Útil para headers compactos donde el wordmark integrado
///     en el logo completo quedaría microscópico (rail/drawer/AppBar).
///     Si es `false`, usa el logo completo con el texto "CI Quality
///     Group" integrado en la imagen — ideal para el login y splash
///     con tamaño grande.
///   - `Theme.of(context).brightness`: en dark mode usa las variantes
///     `_dark` que tienen las partes negras invertidas a blanco para
///     que el logo no se pierda contra el fondo oscuro.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96, this.mark = true});

  /// Alto en pixels. El ancho se calcula manteniendo la relación 1:1.
  final double size;

  /// `true` = solo icono (grúa + hoja). `false` = logo completo con
  /// el wordmark "CI Quality Group" integrado.
  final bool mark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = switch ((mark, isDark)) {
      (true, true) => 'assets/images/logo_mark_dark.png',
      (true, false) => 'assets/images/logo_mark.png',
      (false, true) => 'assets/images/logo_dark.png',
      (false, false) => 'assets/images/logo.png',
    };
    return Image.asset(
      asset,
      height: size,
      width: size,
      fit: BoxFit.contain,
    );
  }
}
