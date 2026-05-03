import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializaciones independientes en paralelo. La de zonas horarias es
  // síncrona; las otras dos son async y antes corrían en serie.
  tzdata.initializeTimeZones();
  await Future.wait<void>([
    initializeDateFormatting('es_CO', null),
    _initFirebase(),
  ]);

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
