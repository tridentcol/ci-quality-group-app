import 'package:cloud_firestore/cloud_firestore.dart';

/// Configuración de la jornada laboral. El admin puede ajustarla desde la app
/// y queda persistida en Firestore (`settings/work_schedule`).
///
/// Por defecto refleja lo conversado con CI Quality Group:
///  - Lunes a viernes: 07:00 – 16:00 con almuerzo 12:00 – 13:00 (8 h efectivas).
///  - Sábado:          07:00 – 11:00 sin almuerzo (4 h efectivas).
///  - Domingo/festivo: 07:00 – 16:00 con almuerzo 12:00 – 13:00 (8 h efectivas
///    pero con recargo dominical → "Hora dominical diurna ordinaria").
///
/// Los rangos diurno/nocturno también son ajustables para futuras reformas.
class WorkSchedule {
  const WorkSchedule({
    this.weekdayOrdinary = const TimeRange(7, 0, 16, 0),
    this.weekdayLunch = const TimeRange(12, 0, 13, 0),
    this.saturdayOrdinary = const TimeRange(7, 0, 11, 0),
    this.saturdayLunch,
    this.sundayOrdinary = const TimeRange(7, 0, 16, 0),
    this.sundayLunch = const TimeRange(12, 0, 13, 0),
    this.dayStart = const TimeOfDayMinutes(6, 0),
    this.dayEnd = const TimeOfDayMinutes(19, 0),
  });

  /// Rango de jornada ordinaria L–V.
  final TimeRange weekdayOrdinary;

  /// Almuerzo L–V (descontado si la jornada del trabajador interseca el rango).
  final TimeRange? weekdayLunch;

  /// Rango de jornada ordinaria sábado.
  final TimeRange saturdayOrdinary;
  final TimeRange? saturdayLunch;

  /// Rango ordinario para domingos/festivos. Aplica el recargo dominical.
  final TimeRange sundayOrdinary;
  final TimeRange? sundayLunch;

  /// Cuándo empieza la franja diurna (extras y recargos diurnos van hasta `dayEnd`).
  final TimeOfDayMinutes dayStart;

  /// Cuándo empieza la franja nocturna.
  final TimeOfDayMinutes dayEnd;

  static const defaultSchedule = WorkSchedule();

  Map<String, dynamic> toMap() => {
        'weekdayOrdinary': weekdayOrdinary.toMap(),
        'weekdayLunch': weekdayLunch?.toMap(),
        'saturdayOrdinary': saturdayOrdinary.toMap(),
        'saturdayLunch': saturdayLunch?.toMap(),
        'sundayOrdinary': sundayOrdinary.toMap(),
        'sundayLunch': sundayLunch?.toMap(),
        'dayStart': dayStart.toMap(),
        'dayEnd': dayEnd.toMap(),
      };

  factory WorkSchedule.fromMap(Map<String, dynamic> map) => WorkSchedule(
        weekdayOrdinary:
            TimeRange.fromMap(map['weekdayOrdinary'] as Map<String, dynamic>),
        weekdayLunch: TimeRange.maybeFromMap(map['weekdayLunch']),
        saturdayOrdinary:
            TimeRange.fromMap(map['saturdayOrdinary'] as Map<String, dynamic>),
        saturdayLunch: TimeRange.maybeFromMap(map['saturdayLunch']),
        sundayOrdinary:
            TimeRange.fromMap(map['sundayOrdinary'] as Map<String, dynamic>),
        sundayLunch: TimeRange.maybeFromMap(map['sundayLunch']),
        dayStart:
            TimeOfDayMinutes.fromMap(map['dayStart'] as Map<String, dynamic>),
        dayEnd: TimeOfDayMinutes.fromMap(map['dayEnd'] as Map<String, dynamic>),
      );

  factory WorkSchedule.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap,) {
    final data = snap.data();
    if (data == null) return defaultSchedule;
    return WorkSchedule.fromMap(data);
  }
}

/// Hora del día expresada en minutos desde medianoche (0..1440).
class TimeOfDayMinutes {
  const TimeOfDayMinutes(this.hour, this.minute);

  final int hour;
  final int minute;

  int get totalMinutes => hour * 60 + minute;

  Map<String, dynamic> toMap() => {'hour': hour, 'minute': minute};

  factory TimeOfDayMinutes.fromMap(Map<String, dynamic> map) =>
      TimeOfDayMinutes(map['hour'] as int, map['minute'] as int);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Intervalo `[start, end)` dentro de un día.
class TimeRange {
  const TimeRange(
      this.startHour, this.startMinute, this.endHour, this.endMinute,);

  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  int get startMinutes => startHour * 60 + startMinute;
  int get endMinutes => endHour * 60 + endMinute;

  bool contains(int minuteOfDay) =>
      minuteOfDay >= startMinutes && minuteOfDay < endMinutes;

  Map<String, dynamic> toMap() => {
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
      };

  factory TimeRange.fromMap(Map<String, dynamic> map) => TimeRange(
        map['startHour'] as int,
        map['startMinute'] as int,
        map['endHour'] as int,
        map['endMinute'] as int,
      );

  static TimeRange? maybeFromMap(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return TimeRange.fromMap(raw);
  }

  @override
  String toString() =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}'
      '–'
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
}
