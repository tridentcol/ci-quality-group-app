import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider que mantiene la instancia de SharedPreferences cargada al
/// arrancar. En `main.dart` se hace `prefs = await SharedPreferences.getInstance()`
/// y se inyecta vía `overrides`. Tener esto sincrónicamente disponible
/// permite leer la preferencia del tema sin un FutureProvider intermedio,
/// evitando el flash entre el theme por defecto y el guardado.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider debe ser sobrescrito en main() con la '
    'instancia ya cargada.',
  );
});

/// StateNotifier que persiste la elección del usuario entre `system`,
/// `light` y `dark`. Por defecto sigue al sistema operativo.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static const _prefsKey = 'cqg.theme_mode';

  static ThemeMode _load(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _prefs.setString(_prefsKey, mode.name);
  }

  /// Cicla System → Light → Dark → System. Lo usa el toggle compacto.
  Future<void> cycle() async {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await set(next);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(sharedPreferencesProvider));
});
