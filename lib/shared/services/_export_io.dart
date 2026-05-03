import 'dart:io';

import 'package:flutter/material.dart' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

/// Implementación native (Android/iOS/desktop): guarda los archivos en el
/// directorio temporal y dispara un share sheet único con todos.
Future<void> deliverFiles({
  required List<ExportFile> files,
  required String subject,
  required String message,
  required Rect sharePositionOrigin,
}) async {
  if (files.isEmpty) return;
  final dir = await getTemporaryDirectory();
  final xfiles = <XFile>[];
  for (final f in files) {
    final out = File('${dir.path}/${f.filename}');
    await out.writeAsBytes(f.bytes, flush: true);
    xfiles.add(XFile(out.path, mimeType: f.mimeType));
  }
  await Share.shareXFiles(
    xfiles,
    subject: subject,
    text: message,
    sharePositionOrigin: sharePositionOrigin,
  );
}
