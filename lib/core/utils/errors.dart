/// Mapper de errores de Firebase / Firestore a mensajes en español
/// amigables. Centralizado aquí para no repetir el `switch` enorme en cada
/// catch de la app.
///
/// Uso típico:
/// ```dart
/// try {
///   await ref.read(salesRepositoryProvider).createSale(...);
/// } catch (e) {
///   showSnack(friendlyError(e));
/// }
/// ```
String friendlyError(Object error) {
  final raw = error.toString();
  // FirebaseAuthException, FirebaseException, etc. exponen `code` pero al
  // hacer `toString()` aparece embebido como `[plugin/code] mensaje`.
  // Extraemos el code y mapeamos.
  final codeMatch = RegExp(r'\[([\w\-]+)\/([\w\-]+)\]').firstMatch(raw);
  final code = codeMatch?.group(2);

  if (code != null) {
    final mapped = _firebaseCodes[code];
    if (mapped != null) return mapped;
  }

  // Errores no-Firebase: descartamos la traza y devolvemos solo el mensaje.
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  if (raw.length > 160) {
    return 'Algo salió mal. Intenta de nuevo.';
  }
  return raw;
}

const _firebaseCodes = <String, String>{
  // FirebaseAuth
  'invalid-credential': 'Usuario o contraseña incorrectos.',
  'invalid-email': 'El usuario tiene caracteres inválidos.',
  'user-disabled': 'Esta cuenta está desactivada. Contacta al admin.',
  'user-not-found': 'No existe una cuenta con ese usuario.',
  'wrong-password': 'Contraseña incorrecta.',
  'too-many-requests':
      'Demasiados intentos seguidos. Espera un momento e intenta de nuevo.',
  'network-request-failed':
      'Sin conexión. Verifica tu internet e intenta de nuevo.',
  'email-already-in-use': 'Ya existe un usuario con ese username.',
  'email-already-exists': 'Ya existe un usuario con ese username.',
  'weak-password': 'La contraseña es muy débil. Usa al menos 6 caracteres.',
  'requires-recent-login':
      'Por seguridad debes volver a iniciar sesión para esta acción.',
  'operation-not-allowed': 'Esta operación no está habilitada.',
  // Firestore
  'permission-denied':
      'No tienes permisos para esta acción. Contacta al admin.',
  'unavailable':
      'No se pudo conectar al servidor. Revisa tu conexión.',
  'deadline-exceeded':
      'El servidor tardó demasiado en responder. Intenta de nuevo.',
  'cancelled': 'Operación cancelada.',
  'not-found': 'El recurso ya no existe.',
  'already-exists': 'Ya existe un registro con esos datos.',
  'failed-precondition':
      'La operación no se puede completar en el estado actual.',
  'aborted': 'La operación fue cancelada por concurrencia. Intenta de nuevo.',
  'out-of-range': 'Los datos están fuera de rango.',
  'unauthenticated': 'Tu sesión expiró. Vuelve a iniciar sesión.',
  'resource-exhausted':
      'Se alcanzó el límite del servicio. Espera un momento.',
  'data-loss': 'Se perdieron datos durante la operación.',
  'internal': 'Error interno del servidor.',
  'unknown': 'Algo salió mal. Intenta de nuevo.',
  'invalid-argument': 'Datos inválidos enviados al servidor.',
};
