import 'package:timezone/timezone.dart' as tz;

/// Reloj central de la app.
///
/// Toda la lógica de fechas y horas debe pasar por aquí para garantizar que
/// la app siempre opere en horario de Colombia (`America/Bogota`, UTC-5,
/// sin horario de verano), independiente del huso horario del dispositivo
/// del usuario.
///
/// Convenciones:
///  - "Wall-clock de Bogotá" = `DateTime` cuyos campos `year/month/day/hour/...`
///    representan la hora local en Bogotá. Es lo que viaja por toda la lógica
///    de la app (cálculo de horas, rangos de fechas, displays).
///  - "Instante" = momento absoluto en el tiempo. Es lo que se guarda en
///    Firestore como `Timestamp`.
class AppClock {
  AppClock._();

  static final tz.Location bogota = tz.getLocation('America/Bogota');

  /// Wall-clock actual en Bogotá.
  static DateTime now() => _strip(tz.TZDateTime.now(bogota));

  /// Convierte un instante absoluto (típicamente lo que sale de un
  /// `Timestamp.toDate()`) a wall-clock de Bogotá.
  static DateTime fromInstant(DateTime instant) =>
      _strip(tz.TZDateTime.from(instant, bogota));

  /// Convierte un wall-clock de Bogotá al instante absoluto correspondiente.
  /// Es lo que se manda a Firestore: `Timestamp.fromDate(AppClock.toInstant(...))`.
  static DateTime toInstant(DateTime bogotaWallClock) {
    return tz.TZDateTime(
      bogota,
      bogotaWallClock.year,
      bogotaWallClock.month,
      bogotaWallClock.day,
      bogotaWallClock.hour,
      bogotaWallClock.minute,
      bogotaWallClock.second,
      bogotaWallClock.millisecond,
      bogotaWallClock.microsecond,
    ).toUtc();
  }

  /// Quita el tag de TZDateTime y devuelve un `DateTime` "naive" cuyos
  /// campos representan el wall-clock dado.
  static DateTime _strip(tz.TZDateTime t) => DateTime(
        t.year,
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
        t.millisecond,
        t.microsecond,
      );
}
