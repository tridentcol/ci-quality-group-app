import 'colombian_holidays.dart';
import 'hours_categories.dart';
import 'work_schedule.dart';

/// Motor de cálculo de horas trabajadas.
///
/// Recibe un par `(entrada, salida)` con instantes absolutos y devuelve la
/// distribución por categoría legal aplicando:
///  - Festivos colombianos (algoritmo de Pascua + Ley Emiliani).
///  - Recargo dominical para domingos y festivos.
///  - Descuento de almuerzo cuando la jornada interseca la franja configurada.
///  - Clasificación diurno/nocturno según `WorkSchedule.dayStart` / `dayEnd`.
///  - Turnos que cruzan medianoche (clasifica cada minuto por su fecha real).
class HoursCalculator {
  const HoursCalculator({this.schedule = WorkSchedule.defaultSchedule});

  final WorkSchedule schedule;

  /// Calcula la distribución por categoría entre `start` (inclusivo) y `end`
  /// (exclusivo). Si `end <= start` retorna un breakdown vacío.
  HoursBreakdown calculate(DateTime start, DateTime end) {
    final breakdown = HoursBreakdown();
    if (!end.isAfter(start)) return breakdown;

    var cursor = start;
    while (cursor.isBefore(end)) {
      final next = _nextBreakpointOrEnd(cursor, end);
      final duration = next.difference(cursor);
      final category = _classify(cursor);
      breakdown.add(category, duration);
      cursor = next;
    }
    return breakdown;
  }

  DateTime _nextBreakpointOrEnd(DateTime cursor, DateTime end) {
    final minuteOfDay = cursor.hour * 60 + cursor.minute;
    final candidates = _breakpointMinutes(cursor);
    final nextMinute = candidates
        .firstWhere((m) => m > minuteOfDay, orElse: () => 24 * 60);

    final next = DateTime(cursor.year, cursor.month, cursor.day)
        .add(Duration(minutes: nextMinute));

    return end.isBefore(next) ? end : next;
  }

  List<int> _breakpointMinutes(DateTime moment) {
    final ord = _ordinaryFor(moment);
    final lunch = _lunchFor(moment);

    final set = <int>{
      0,
      24 * 60,
      schedule.dayStart.totalMinutes,
      schedule.dayEnd.totalMinutes,
      ord.startMinutes,
      ord.endMinutes,
      if (lunch != null) lunch.startMinutes,
      if (lunch != null) lunch.endMinutes,
    };
    final sorted = set.toList()..sort();
    return sorted;
  }

  HoursCategory _classify(DateTime moment) {
    final isDominical = ColombianHolidays.isSundayOrHoliday(moment);
    final ord = _ordinaryFor(moment);
    final lunch = _lunchFor(moment);
    final minute = moment.hour * 60 + moment.minute;

    final inOrdinary = ord.contains(minute);
    final inLunch = lunch != null && lunch.contains(minute);

    if (inOrdinary && inLunch) {
      return HoursCategory.lunch;
    }

    if (inOrdinary) {
      return isDominical ? HoursCategory.sundayOrdinary : HoursCategory.ordinary;
    }

    final isDayTime = minute >= schedule.dayStart.totalMinutes &&
        minute < schedule.dayEnd.totalMinutes;

    if (isDayTime) {
      return isDominical ? HoursCategory.extraSundayDay : HoursCategory.extraDay;
    }
    return isDominical ? HoursCategory.extraSundayNight : HoursCategory.extraNight;
  }

  TimeRange _ordinaryFor(DateTime moment) {
    if (ColombianHolidays.isSundayOrHoliday(moment)) {
      return schedule.sundayOrdinary;
    }
    if (moment.weekday == DateTime.saturday) {
      return schedule.saturdayOrdinary;
    }
    return schedule.weekdayOrdinary;
  }

  TimeRange? _lunchFor(DateTime moment) {
    if (ColombianHolidays.isSundayOrHoliday(moment)) {
      return schedule.sundayLunch;
    }
    if (moment.weekday == DateTime.saturday) {
      return schedule.saturdayLunch;
    }
    return schedule.weekdayLunch;
  }
}
