import 'package:flutter/material.dart';

/// Paleta corporativa CI Quality Group.
///
/// Verde árbol como color principal, negro profundo como neutro,
/// y un verde hoja (tomado del logo) para acentos y estados positivos.
class AppColors {
  AppColors._();

  // Marca
  static const Color treeGreen = Color(0xFF1F5128);
  static const Color treeGreenDark = Color(0xFF143618);
  static const Color leafGreen = Color(0xFF4FBA47);
  static const Color leafGreenSoft = Color(0xFFE6F4E1);

  // Neutros — grises 100 % neutros (R = G = B) sin tinte azul ni verde.
  // Antes tenían +2/+5 en el canal azul (estilo "neutral cool" típico de
  // Material) pero se percibía un velo azulado en dark mode. Esta paleta
  // se ve siempre como negro/gris puros sobre cualquier monitor.
  static const Color ink = Color(0xFF0E0E0E);
  static const Color graphite = Color(0xFF1B1B1B);
  static const Color slate = Color(0xFF2A2A2A);
  static const Color steel = Color(0xFF6B6B6B);
  static const Color mist = Color(0xFFB8B8B8);
  static const Color cloud = Color(0xFFF4F4F4);
  static const Color paper = Color(0xFFFAFAFA);
  static const Color white = Color(0xFFFFFFFF);

  // Estado
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFE6A100);
  static const Color danger = Color(0xFFD64545);
  static const Color info = Color(0xFF2563EB);

  /// Paleta cíclica para series de gráficos (donut, líneas múltiples) en
  /// tema claro. Comienza con colores corporativos y desemboca en neutros
  /// que combinan con el verde árbol.
  static const List<Color> chartPalette = <Color>[
    treeGreen,
    leafGreen,
    info,
    warning,
    Color(0xFF7C3AED), // morado profundo
    Color(0xFF0891B2), // teal
    Color(0xFFDC2626), // rojo apagado
    steel,
  ];

  /// Paleta para tema oscuro: el `treeGreen` es muy oscuro contra fondo
  /// `ink/graphite` y se pierde, así que el primario pasa a `leafGreen`
  /// y los demás se aclaran un par de tonos para mantener contraste.
  static const List<Color> chartPaletteDark = <Color>[
    leafGreen,
    Color(0xFF8FE57F), // verde más claro
    Color(0xFF60A5FA), // azul claro (info clarito)
    Color(0xFFFFC857), // amarillo cálido
    Color(0xFFC4A1FF), // morado pastel
    Color(0xFF22D3EE), // teal claro
    Color(0xFFFB7185), // rosa coral
    mist,
  ];

  /// Devuelve la paleta correcta según el brillo del tema.
  static List<Color> chartPaletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? chartPaletteDark : chartPalette;
}
