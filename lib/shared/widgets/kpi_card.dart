import 'package:flutter/material.dart';

/// Card de un KPI. Tiene dos layouts:
///   - **Expanded** (default): label arriba con icono, valor grande
///     debajo, subtítulo abajo. Usado en pantallas anchas donde varios
///     KPIs viven en una `Row` lado a lado.
///   - **Compact**: tile horizontal — icono a la izquierda, label +
///     subtítulo en columna en el medio, valor a la derecha. Usado en
///     mobile, donde cada KPI ocupa una fila propia. Como el tile tiene
///     todo el ancho del scroll para colocar el valor, el `FittedBox`
///     rara vez tiene que escalarlo abajo, así que los valores entre
///     tiles se ven uniformes (sin el problema de ver "$1.234.567" más
///     chico que "3 ventas" en el card de al lado).
///
/// El modo se elige automáticamente vía `_CompactKpiScope` que el
/// `KpiRow` inyecta cuando detecta ancho de mobile. Los call-sites no
/// tienen que decidir el modo.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    if (_CompactKpiScope.of(context)) {
      return _buildCompact(theme, c);
    }
    return _buildExpanded(theme, c);
  }

  Widget _buildExpanded(ThemeData theme, Color c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: c),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(ThemeData theme, Color c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: c),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila responsiva de KPIs.
///
/// - **Mobile (< 600 dp)**: stack vertical de tiles compactos (cada KPI
///   en una fila propia, full width). Inyecta `_CompactKpiScope` para
///   que cada `KpiCard` adentro renderee en modo compact.
/// - **Tablet / Desktop (≥ 600 dp)**: row con `Expanded` + alturas
///   iguales vía `IntrinsicHeight` (grid de N columnas estiradas).
///
/// El umbral 600 dp es el breakpoint "compact → medium" de Material
/// Design 3. Cualquier teléfono en vertical cae en mobile; tablets en
/// vertical/horizontal y desktop caen en tablet/desktop.
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        if (narrow) {
          return _CompactKpiScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  cards[i],
                ],
              ],
            ),
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Marca de que estamos dentro de un `KpiRow` en modo compacto. Lo lee
/// `KpiCard` para decidir qué layout dibujar.
class _CompactKpiScope extends InheritedWidget {
  const _CompactKpiScope({required super.child});

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_CompactKpiScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(_CompactKpiScope oldWidget) => false;
}
