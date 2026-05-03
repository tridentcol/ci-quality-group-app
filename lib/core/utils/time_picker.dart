import 'package:flutter/material.dart';

/// Versión de `showTimePicker` que siempre rinde en formato 12h con AM/PM,
/// independiente del locale del SO o de la app.
///
/// Para lograrlo cambiamos temporalmente el locale del picker a `en_US`
/// (el único que en Flutter default-ea a `h_colon_mm_space_a`) y pasamos
/// las etiquetas en español a mano para que el usuario no vea inglés.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String helpText = 'Selecciona la hora',
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    cancelText: 'CANCELAR',
    confirmText: 'ACEPTAR',
    helpText: helpText,
    hourLabelText: 'Hora',
    minuteLabelText: 'Minuto',
    builder: (context, child) {
      return Localizations.override(
        context: context,
        locale: const Locale('en', 'US'),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        ),
      );
    },
  );
}
