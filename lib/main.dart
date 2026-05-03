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

  await initializeDateFormatting('es_CO', null);

  // La app opera siempre en horario de Colombia (America/Bogota).
  // Inicializamos la base de datos de zonas horarias para que AppClock
  // pueda traducir entre wall-clock de Bogotá e instantes UTC.
  tzdata.initializeTimeZones();

  // En Android/iOS el plugin nativo (google-services.json /
  // GoogleService-Info.plist) ya inicializa Firebase antes de que Dart
  // pueda enterarse, por lo que `Firebase.apps.isEmpty` no es confiable.
  // Tragamos específicamente "duplicate-app" para arrancar igual.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Habilita la caché offline de Firestore (sincroniza al recuperar conexión).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: CIQualityGroupApp()));
}
