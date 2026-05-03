import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Diálogo de confirmación reusable. Devuelve `true` solo si el usuario
/// confirma la acción. Usar en lugar de `showDialog` con AlertDialog
/// hand-built para mantener consistencia (textos, layout, haptic).
///
/// ```dart
/// final ok = await showConfirmDialog(
///   context,
///   title: 'Anular venta',
///   message: '¿Seguro que deseas anular CQG-042? No se puede deshacer.',
///   confirmLabel: 'Anular',
///   destructive: true,
/// );
/// if (ok) await ref.read(salesRepo).deleteSale(id);
/// ```
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Aceptar',
  String cancelLabel = 'Cancelar',
  bool destructive = false,
  IconData? icon,
}) async {
  if (destructive) {
    HapticFeedback.mediumImpact();
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final accent =
          destructive ? theme.colorScheme.error : theme.colorScheme.primary;
      return AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: accent),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
