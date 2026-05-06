import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app.dart';
import 'core/theme/theme_mode_controller.dart';
import 'firebase_options.dart';

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

  // Caché offline de Firestore. En native (Android/iOS) la habilitamos
  // siempre. En web depende de IndexedDB y puede tirar excepción en
  // incógnito / otras pestañas abiertas / browsers con cookies de
  // terceros bloqueadas — por eso la dejamos desactivada en web (el
  // SDK web ya tiene su propio caché en memoria por sesión).
  if (!kIsWeb) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (_) {
      // Si por alguna razón falla, preferimos arrancar sin caché que
      // dejar la app trabada en pantalla de carga.
    }
  }

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
