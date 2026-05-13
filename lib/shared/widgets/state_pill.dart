import 'package:flutter/material.dart';

import '../../features/sales/domain/sale.dart';

/// Pill compacto que muestra el estado workflow de una venta con su color
/// asociado. Reutilizable en cards, headers y detalle.
///
/// Colores:
///   generada    → ámbar (esperando que cajero la tome)
///   en_proceso  → azul info (cajero la está revisando)
///   procesada   → verde (material entregable)
///   cancelada   → gris neutro (terminal sin acción)
class StatePill extends StatelessWidget {
  const StatePill({
    super.key,
    required this.state,
    this.compact = false,
  });

  final SaleState state;

  /// Si `true`, usa fontSize / padding más chicos para meterse en
  /// listings densos. Si `false`, tamaño "regular" para detalle.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = _styleFor(state, theme);
    final padH = compact ? 6.0 : 10.0;
    final padV = compact ? 2.0 : 4.0;
    final fontSize = compact ? 10.5 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: fontSize,
        ),
      ),
    );
  }

  static (Color, String) _styleFor(SaleState s, ThemeData theme) =>
      switch (s) {
        SaleState.generada => (const Color(0xFFE6A100), 'Generada'),
        SaleState.enProceso => (theme.colorScheme.primary, 'En proceso'),
        SaleState.procesada => (const Color(0xFF2E7D32), 'Procesada'),
        SaleState.cancelada => (
            theme.colorScheme.onSurface.withValues(alpha: 0.55),
            'Cancelada',
          ),
      };
}
