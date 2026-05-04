import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app.dart';
import 'firebase_options.dart';

/// Site key de reCAPTCHA v3 para App Check en web. Se inyecta al build con:
///   flutter build web --release --dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=...
/// Si está vacío en web, App Check se omite y la app arranca normal (útil
/// en local). Ver `docs/production_checklist.md` para conseguir el key.
const _kRecaptchaSiteKey = String.fromEnvironment(
  'APP_CHECK_RECAPTCHA_SITE_KEY',
  defaultValue: '',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializaciones independientes en paralelo. La de zonas horarias es
  // síncrona; las otras dos son async y antes corrían en serie.
  tzdata.initializeTimeZones();
  await Future.wait<void>([
    initializeDateFormatting('es_CO', null),
    _initFirebase(),
  ]);

  // App Check va después de initializeApp pero antes de cualquier llamada a
  // Firestore/Auth para que los requests salgan ya con el token.
  await _initAppCheck();

  // Habilita la caché offline de Firestore (sincroniza al recuperar conexión).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: CIQualityGroupApp()));
}

/// En Android/iOS el plugin nativo (google-services.json /
/// GoogleService-Info.plist) puede inicializar Firebase antes de que
/// Dart se entere, por lo que `Firebase.apps.isEmpty` no es confiable.
/// Tragamos específicamente "duplicate-app" para arrancar igual.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

/// Activa Firebase App Check para frenar abuso desde clientes no oficiales
/// (un atacante que copie las API keys del firebase_options no puede
/// hablarle a Firestore sin un token válido).
///
/// - Web: reCAPTCHA v3 (requiere site key registrado en consola).
/// - Android: Play Integrity (requiere SHA-256 en consola).
/// - iOS: Device Check.
///
/// Si la activación falla (ej. site key sin registrar todavía), seguimos
/// arrancando sin App Check; mientras la enforcement esté en "monitor"
/// la app funciona igual.
Future<void> _initAppCheck() async {
  if (kIsWeb && _kRecaptchaSiteKey.isEmpty) return;
  try {
    await FirebaseAppCheck.instance.activate(
      webProvider:
          kIsWeb ? ReCaptchaV3Provider(_kRecaptchaSiteKey) : null,
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  } catch (_) {
    // Silencioso: ver docstring.
  }
}
