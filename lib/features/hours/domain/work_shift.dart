import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';
import 'work_schedule.dart';

/// Turno de trabajo. Reemplaza la jornada ordinaria (y el almuerzo) de la
/// configuración global para los trabajadores que lo tienen asignado.
///
/// Lo administran `admin` y `hours` desde la app (`work_shifts/{id}`). Nunca
/// se borra: los registros de horas guardan el `shiftId` con el que se
/// calcularon, así que solo se desactiva.
class WorkShift {
  const WorkShift({
    required this.id,
    required this.name,
    required this.weekday,
    this.weekdayLunch,
    this.saturday,
    this.saturdayLunch,
    this.sunday,
    this.sundayLunch,
    this.active = true,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
    this.updatedByName,
  });

  final String id;
  final String name;

  /// Jornada ordinaria L–V. También aplica a sábado y domingo/festivo
  /// cuando esos días no tienen un rango propio.
  final TimeRange weekday;
  final TimeRange? weekdayLunch;

  /// `null` = el sábado usa el mismo rango y almuerzo que L–V.
  final TimeRange? saturday;
  final TimeRange? saturdayLunch;

  /// `null` = domingos y festivos usan el mismo rango y almuerzo que L–V
  /// (se siguen pagando con recargo dominical).
  final TimeRange? sunday;
  final TimeRange? sundayLunch;

  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? updatedByName;

  /// Jornada efectiva del turno: sus rangos ordinarios y almuerzos sobre
  /// las franjas diurna/nocturna de [base], que son legales y no dependen
  /// del turno.
  WorkSchedule applyTo(WorkSchedule base) => WorkSchedule(
        weekdayOrdinary: weekday,
        weekdayLunch: weekdayLunch,
        saturdayOrdinary: saturday ?? weekday,
        saturdayLunch: saturday == null ? weekdayLunch : saturdayLunch,
        sundayOrdinary: sunday ?? weekday,
        sundayLunch: sunday == null ? weekdayLunch : sundayLunch,
        dayStart: base.dayStart,
        dayEnd: base.dayEnd,
      );

  /// Rango ordinario que aplica en [date] (sin considerar festivos: sirve
  /// solo para sugerir horas de entrada/salida en los formularios).
  TimeRange rangeFor(DateTime date) {
    if (date.weekday == DateTime.sunday) return sunday ?? weekday;
    if (date.weekday == DateTime.saturday) return saturday ?? weekday;
    return weekday;
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'weekday': weekday.toMap(),
        'weekdayLunch': weekdayLunch?.toMap(),
        'saturday': saturday?.toMap(),
        'saturdayLunch': saturdayLunch?.toMap(),
        'sunday': sunday?.toMap(),
        'sundayLunch': sundayLunch?.toMap(),
        'active': active,
      };

  factory WorkShift.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    DateTime? date(String key) => data[key] == null
        ? null
        : AppClock.fromInstant((data[key] as Timestamp).toDate());
    return WorkShift(
      id: snap.id,
      name: data['name'] as String,
      weekday: TimeRange.fromMap(data['weekday'] as Map<String, dynamic>),
      weekdayLunch: TimeRange.maybeFromMap(data['weekdayLunch']),
      saturday: TimeRange.maybeFromMap(data['saturday']),
      saturdayLunch: TimeRange.maybeFromMap(data['saturdayLunch']),
      sunday: TimeRange.maybeFromMap(data['sunday']),
      sundayLunch: TimeRange.maybeFromMap(data['sundayLunch']),
      active: (data['active'] as bool?) ?? true,
      createdAt: date('createdAt'),
      updatedAt: date('updatedAt'),
      updatedBy: data['updatedBy'] as String?,
      updatedByName: data['updatedByName'] as String?,
    );
  }

  /// Igualdad por id, para que los dropdowns reconozcan el `value` cuando
  /// la lista se reconstruye con instancias nuevas (mismo motivo que `Worker`).
  @override
  bool operator ==(Object other) => other is WorkShift && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Turno activo con ese id, o `null` si no hay (sin turno, desactivado o
/// inexistente). Es el que se usa al abrir un día nuevo.
WorkShift? activeShiftById(List<WorkShift> shifts, String? shiftId) {
  if (shiftId == null) return null;
  for (final s in shifts) {
    if (s.id == shiftId && s.active) return s;
  }
  return null;
}

/// Jornada con la que se calcula un registro: la del turno [shiftId] si
/// existe, o [base] (la jornada general) si el registro no tiene turno.
WorkSchedule resolveSchedule(
  WorkSchedule base,
  List<WorkShift> shifts,
  String? shiftId,
) {
  if (shiftId == null) return base;
  for (final s in shifts) {
    if (s.id == shiftId) return s.applyTo(base);
  }
  return base;
}
