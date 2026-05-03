import 'package:flutter/material.dart';

/// Encabezado de sección compacto en mayúsculas con color primario.
/// Uniforma el patrón usado en formularios y dashboards.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
        letterSpacing: 1.2,
      ),
    );
  }
}
