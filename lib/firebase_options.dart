// PLACEHOLDER — reemplaza este archivo ejecutando `flutterfire configure`
// desde la raíz del proyecto. Esa herramienta genera el archivo real con las
// credenciales del proyecto Firebase.
//
// Mientras no exista el archivo real, la app fallará al inicializar Firebase.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web no es plataforma objetivo. Ejecuta flutterfire configure --platforms=android,ios.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'firebase_options.dart todavía no está configurado. '
          'Ejecuta `flutterfire configure --project=<tu-proyecto-firebase> '
          '--platforms=android,ios` en la raíz del repo.',
        );
      default:
        throw UnsupportedError('Plataforma no soportada.');
    }
  }
}
