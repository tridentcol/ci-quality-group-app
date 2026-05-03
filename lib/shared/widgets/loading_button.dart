import 'package:flutter/material.dart';

/// Botón principal con estado de carga interno. Reemplaza el patrón
/// `FilledButton(onPressed: _busy ? null : _submit, child: _busy ? Spinner :
/// Text)` repetido en 5+ formularios.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.loading = false,
    this.icon,
  });

  /// Callback al presionar. Si `null` o `loading == true`, el botón
  /// queda deshabilitado.
  final VoidCallback? onPressed;
  final String label;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = loading || onPressed == null;
    final spinner = SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        color: theme.colorScheme.onPrimary,
        strokeWidth: 2.4,
      ),
    );

    if (icon != null && !loading) {
      return FilledButton.icon(
        onPressed: disabled ? null : onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return FilledButton(
      onPressed: disabled ? null : onPressed,
      child: loading ? spinner : Text(label),
    );
  }
}
