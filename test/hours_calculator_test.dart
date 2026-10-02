import 'package:ci_quality_group/features/hours/domain/hours_calculator.dart';
import 'package:ci_quality_group/features/hours/domain/hours_categories.dart';
import 'package:ci_quality_group/features/hours/domain/work_schedule.dart';
import 'package:ci_quality_group/features/hours/domain/work_shift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lunes 4 de mayo 2026: día laboral común.
  // Sábado 2 mayo 2026: laboral.
  // Domingo 3 mayo 2026: dominical.

  const calc = HoursCalculator();

  group('Jornada L–V', () {
    test('Mon 7am-4pm = 8h ordinaria + 1h almuerzo', () {
      final start = DateTime(2026, 5, 4, 7, 0);
      final end = DateTime(2026, 5, 4, 16, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 8));
      expect(r.get(HoursCategory.lunch), const Duration(hours: 1));
      expect(r.get(HoursCategory.extraDay), Duration.zero);
    });

    test('Mon 7am-7pm = 8h ord + 3h extra diurna + 1h almuerzo', () {
      final start = DateTime(2026, 5, 4, 7, 0);
      final end = DateTime(2026, 5, 4, 19, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 8));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 3));
      expect(r.get(HoursCategory.lunch), const Duration(hours: 1));
    });

    test('Mon 6am-7pm = 1h extra diurna previa + 8h ord + 3h extra diurna', () {
      final start = DateTime(2026, 5, 4, 6, 0);
      final end = DateTime(2026, 5, 4, 19, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 4));
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 8));
    });

    test('Mon 7am-9pm = 8h ord + 3h extra diurna + 2h extra nocturna', () {
      final start = DateTime(2026, 5, 4, 7, 0);
      final end = DateTime(2026, 5, 4, 21, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 8));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 3));
      expect(r.get(HoursCategory.extraNight), const Duration(hours: 2));
    });
  });

  group('Sábado', () {
    test('Sat 7am-11am = 4h ordinaria sin almuerzo', () {
      final start = DateTime(2026, 5, 2, 7, 0);
      final end = DateTime(2026, 5, 2, 11, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 4));
      expect(r.get(HoursCategory.lunch), Duration.zero);
    });

    test('Sat 7am-2pm = 4h ord + 3h extra diurna', () {
      final start = DateTime(2026, 5, 2, 7, 0);
      final end = DateTime(2026, 5, 2, 14, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 4));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 3));
    });

    test('Sat 7am-9pm = 4h ord + 8h extra diurna + 2h extra nocturna', () {
      final start = DateTime(2026, 5, 2, 7, 0);
      final end = DateTime(2026, 5, 2, 21, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 4));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 8));
      expect(r.get(HoursCategory.extraNight), const Duration(hours: 2));
    });
  });

  group('Domingo', () {
    test('Sun 7am-4pm = 8h dominical ordinaria + 1h almuerzo', () {
      final start = DateTime(2026, 5, 3, 7, 0);
      final end = DateTime(2026, 5, 3, 16, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.sundayOrdinary), const Duration(hours: 8));
      expect(r.get(HoursCategory.lunch), const Duration(hours: 1));
    });

    test('Sun 7am-7pm = 8h dominical ord + 3h extra dominical diurna', () {
      final start = DateTime(2026, 5, 3, 7, 0);
      final end = DateTime(2026, 5, 3, 19, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.sundayOrdinary), const Duration(hours: 8));
      expect(r.get(HoursCategory.extraSundayDay), const Duration(hours: 3));
    });

    test('Sun 7pm-10pm = 3h extra dominical nocturna', () {
      final start = DateTime(2026, 5, 3, 19, 0);
      final end = DateTime(2026, 5, 3, 22, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.extraSundayNight), const Duration(hours: 3));
    });
  });

  group('Festivo nacional', () {
    test('1 mayo 2026 (festivo) 7am-4pm = 8h dominical ordinaria', () {
      final start = DateTime(2026, 5, 1, 7, 0);
      final end = DateTime(2026, 5, 1, 16, 0);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.sundayOrdinary), const Duration(hours: 8));
      expect(r.get(HoursCategory.ordinary), Duration.zero);
    });
  });

  group('Turnos que cruzan medianoche', () {
    test('Mon 7pm → Tue 8am clasifica por fecha real', () {
      final start = DateTime(2026, 5, 4, 19, 0);
      final end = DateTime(2026, 5, 5, 8, 0);
      final r = calc.calculate(start, end);
      // Mon 7pm-12am: 5h extra nocturna
      // Tue 12am-6am: 6h extra nocturna
      // Tue 6am-7am: 1h extra diurna
      // Tue 7am-8am: 1h ordinaria
      expect(r.get(HoursCategory.extraNight), const Duration(hours: 11));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 1));
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 1));
    });

    test('Sat 8pm → Sun 3am cambia a dominical al pasar medianoche', () {
      final start = DateTime(2026, 5, 2, 20, 0);
      final end = DateTime(2026, 5, 3, 3, 0);
      final r = calc.calculate(start, end);
      // Sat 8pm-12am: 4h extra nocturna (sábado)
      // Sun 12am-3am: 3h extra dominical nocturna
      expect(r.get(HoursCategory.extraNight), const Duration(hours: 4));
      expect(r.get(HoursCategory.extraSundayNight), const Duration(hours: 3));
    });
  });

  group('Casos borde', () {
    test('Rango vacío devuelve breakdown en cero', () {
      final t = DateTime(2026, 5, 4, 12, 0);
      final r = calc.calculate(t, t);
      expect(r.totalPaid, Duration.zero);
    });

    test('Salida antes de entrada devuelve breakdown en cero', () {
      final start = DateTime(2026, 5, 4, 12, 0);
      final end = DateTime(2026, 5, 4, 11, 0);
      final r = calc.calculate(start, end);
      expect(r.totalPaid, Duration.zero);
    });

    test('Sale antes del almuerzo no descuenta almuerzo', () {
      final start = DateTime(2026, 5, 4, 7, 0);
      final end = DateTime(2026, 5, 4, 11, 30);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 4, minutes: 30));
      expect(r.get(HoursCategory.lunch), Duration.zero);
    });

    test('Sale a las 12:30 descuenta media hora de almuerzo', () {
      final start = DateTime(2026, 5, 4, 7, 0);
      final end = DateTime(2026, 5, 4, 12, 30);
      final r = calc.calculate(start, end);
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 5));
      expect(r.get(HoursCategory.lunch), const Duration(minutes: 30));
    });
  });

  group('Turnos', () {
    const base = WorkSchedule();
    const morning = WorkShift(
      id: 'm',
      name: 'Mañana',
      weekday: TimeRange(6, 0, 13, 0),
    );
    const afternoon = WorkShift(
      id: 't',
      name: 'Tarde',
      weekday: TimeRange(13, 0, 20, 0),
    );
    final morningCalc = HoursCalculator(schedule: morning.applyTo(base));
    final afternoonCalc = HoursCalculator(schedule: afternoon.applyTo(base));

    test('Mañana: Mon 6am-1pm = 7h ordinaria corrida, sin almuerzo', () {
      final r = morningCalc.calculate(
        DateTime(2026, 5, 4, 6, 0),
        DateTime(2026, 5, 4, 13, 0),
      );
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 7));
      expect(r.get(HoursCategory.lunch), Duration.zero);
      expect(r.totalPaid, const Duration(hours: 7));
    });

    test('Mañana: Mon 6am-6pm = 7h ord + 5h extra diurna', () {
      final r = morningCalc.calculate(
        DateTime(2026, 5, 4, 6, 0),
        DateTime(2026, 5, 4, 18, 0),
      );
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 7));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 5));
    });

    test('Mañana: Mon 6am-8pm = 7h ord + 6h extra diurna + 1h extra nocturna',
        () {
      final r = morningCalc.calculate(
        DateTime(2026, 5, 4, 6, 0),
        DateTime(2026, 5, 4, 20, 0),
      );
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 7));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 6));
      expect(r.get(HoursCategory.extraNight), const Duration(hours: 1));
    });

    test('Tarde: Mon 1pm-8pm = 6h ordinaria + 1h ordinaria nocturna', () {
      final r = afternoonCalc.calculate(
        DateTime(2026, 5, 4, 13, 0),
        DateTime(2026, 5, 4, 20, 0),
      );
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 6));
      expect(r.get(HoursCategory.ordinaryNight), const Duration(hours: 1));
      expect(r.get(HoursCategory.extraNight), Duration.zero);
      expect(r.totalPaid, const Duration(hours: 7));
    });

    test('Tarde: Mon 1pm-7pm = 6h ordinaria, nada nocturno', () {
      final r = afternoonCalc.calculate(
        DateTime(2026, 5, 4, 13, 0),
        DateTime(2026, 5, 4, 19, 0),
      );
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 6));
      expect(r.get(HoursCategory.ordinaryNight), Duration.zero);
    });

    test('Tarde: llegar a las 8am cuenta 5h extra diurna antes del turno', () {
      final r = afternoonCalc.calculate(
        DateTime(2026, 5, 4, 8, 0),
        DateTime(2026, 5, 4, 18, 0),
      );
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 5));
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 5));
    });

    test('Sábado y domingo heredan el rango de L–V si no tienen uno propio',
        () {
      final sat = morningCalc.calculate(
        DateTime(2026, 5, 2, 6, 0),
        DateTime(2026, 5, 2, 13, 0),
      );
      expect(sat.get(HoursCategory.ordinary), const Duration(hours: 7));

      final sun = afternoonCalc.calculate(
        DateTime(2026, 5, 3, 13, 0),
        DateTime(2026, 5, 3, 20, 0),
      );
      expect(sun.get(HoursCategory.sundayOrdinary), const Duration(hours: 6));
      expect(
        sun.get(HoursCategory.sundayOrdinaryNight),
        const Duration(hours: 1),
      );
    });

    test('Sábado con rango propio no usa el de L–V ni su almuerzo', () {
      const shift = WorkShift(
        id: 'x',
        name: 'Con almuerzo',
        weekday: TimeRange(7, 0, 16, 0),
        weekdayLunch: TimeRange(12, 0, 13, 0),
        saturday: TimeRange(7, 0, 11, 0),
      );
      final calc = HoursCalculator(schedule: shift.applyTo(base));
      final r = calc.calculate(
        DateTime(2026, 5, 2, 7, 0),
        DateTime(2026, 5, 2, 14, 0),
      );
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 4));
      expect(r.get(HoursCategory.extraDay), const Duration(hours: 3));
      expect(r.get(HoursCategory.lunch), Duration.zero);
    });

    test('El turno conserva las franjas diurna/nocturna de la jornada general',
        () {
      const custom = WorkSchedule(dayEnd: TimeOfDayMinutes(21, 0));
      final r = HoursCalculator(schedule: afternoon.applyTo(custom)).calculate(
        DateTime(2026, 5, 4, 13, 0),
        DateTime(2026, 5, 4, 20, 0),
      );
      expect(r.get(HoursCategory.ordinary), const Duration(hours: 7));
      expect(r.get(HoursCategory.ordinaryNight), Duration.zero);
    });

    test('resolveSchedule cae a la jornada general sin turno o turno ausente',
        () {
      expect(
        resolveSchedule(base, const [morning], null).weekdayOrdinary.toString(),
        '07:00–16:00',
      );
      expect(
        resolveSchedule(base, const [morning], 'borrado')
            .weekdayOrdinary
            .toString(),
        '07:00–16:00',
      );
      expect(
        resolveSchedule(base, const [morning], 'm').weekdayOrdinary.toString(),
        '06:00–13:00',
      );
    });
  });
}
