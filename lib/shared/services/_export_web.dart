// ignore_for_file: avoid_web_libraries_in_flutter
// Solo se compila cuando `dart.library.html` está disponible (web).
import 'dart:html' as html;

import 'package:flutter/material.dart' show Rect;

class ExportFile {
  const ExportFile({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
  final List<int> bytes;
  final String filename;
  final String mimeType;
}

/// Implementación web: dispara un download por cada archivo (el navegador
/// no permite "compartir" múltiples archivos como sí lo hace iOS/Android,
/// así que cada uno se baja a la carpeta de descargas del usuario).
/// Ignora `subject`/`message`/`sharePositionOrigin`.
Future<void> deliverFiles({
  required List<ExportFile> files,
  required String subject,
  required String message,
  required Rect sharePositionOrigin,
}) async {
  for (final f in files) {
    final blob = html.Blob([f.bytes], f.mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', f.filename)
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    // Pequeño delay para que el navegador procese descargas en serie.
    await Future.delayed(const Duration(milliseconds: 200));
    html.Url.revokeObjectUrl(url);
  }
}
