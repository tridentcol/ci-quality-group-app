import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app.dart';
import 'core/theme/theme_mode_controller.dart';
import 'firebase_options.dart';

/// App Check es opt-in por plataforma vía `--dart-define`. Si no se pasa,
/// la activación se omite y la app arranca normal. Esto evita el bloqueo
/// que ocurre cuando la consola de App Check no tiene registrado el
/// SHA-256 (Android), el bundle id (iOS) o el site key (web): la lib
/// reintenta indefinidamente y deja al login colgado.
///
/// Para encender:
///   - Web: `--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=6Lc...`
///   - Móvil: `--dart-define=APP_CHECK_MOBILE=true`
/// Ver `docs/production_checklist.md` para el setup en consola.
const _kRecaptchaSiteKey = String.fromEnvironment(
  'APP_CHECK_RECAPTCHA_SITE_KEY',
  defaultValue: '',
);
const _kEnableMobileAppCheck = bool.fromEnvironment(
  'APP_CHECK_MOBILE',
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializaciones independientes en paralelo. La de zonas horarias es
  // síncrona; las otras tres son async y antes corrían en serie.
  // SharedPreferences se carga aquí para tenerlo síncrono en los providers
  // y poder leer el theme mode antes del primer frame (evita flash).
  tzdata.initializeTimeZones();
  final prefsFuture = SharedPreferences.getInstance();
  await Future.wait<void>([
    initializeDateFormatting('es_CO', null),
    _initFirebase(),
  ]);
  final prefs = await prefsFuture;

  // App Check va después de initializeApp pero antes de cualquier llamada a
  // Firestore/Auth para que los requests salgan ya con el token.
  await _initAppCheck();

  // Habilita la caché offline de Firestore (sincroniza al recuperar conexión).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CIQualityGroupApp(),
    ),
  );
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
/// (un atacante que copie las API keys de `firebase_options` no puede
/// hablarle a Firestore sin un token válido). Es opt-in por plataforma:
///
/// - Web: requiere `--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=...` y el
///   site key registrado en consola de App Check.
/// - Móvil: requiere `--dart-define=APP_CHECK_MOBILE=true`. En debug usa
///   el provider Debug (token fijo a pegar en consola); en release usa
///   Play Integrity / Device Check (requieren SHA-256 / bundle id en
///   consola).
///
/// Si está apagado o la activación falla, la app arranca normal — solo se
/// pierde la protección anti-abuso. La activación tiene un timeout de 3 s
/// para que aunque la red de Google esté lenta no bloquee el splash.
Future<void> _initAppCheck() async {
  if (kIsWeb) {
    if (_kRecaptchaSiteKey.isEmpty) return;
  } else {
    if (!_kEnableMobileAppCheck) return;
  }
  try {
    await FirebaseAppCheck.instance
        .activate(
          webProvider:
              kIsWeb ? ReCaptchaV3Provider(_kRecaptchaSiteKey) : null,
          androidProvider:
              kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
          appleProvider:
              kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
        )
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    // Silencioso: ver docstring. Timeout o cualquier otro error no
    // bloquea el arranque.
  }
}
