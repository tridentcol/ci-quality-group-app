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

  // Neutros
  static const Color ink = Color(0xFF0E0E10);
  static const Color graphite = Color(0xFF1B1B1F);
  static const Color slate = Color(0xFF2A2A2F);
  static const Color steel = Color(0xFF6B6B73);
  static const Color mist = Color(0xFFB8B8BF);
  static const Color cloud = Color(0xFFF4F4F6);
  static const Color paper = Color(0xFFFAFAFA);
  static const Color white = Color(0xFFFFFFFF);

  // Estado
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFE6A100);
  static const Color danger = Color(0xFFD64545);
  static const Color info = Color(0xFF2563EB);

  /// Paleta cíclica para series de gráficos (donut, líneas múltiples).
  /// Comienza con colores corporativos y desemboca en neutros que
  /// combinan con el verde árbol.
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
}
