import 'package:ci_quality_group/features/hours/domain/colombian_holidays.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Algoritmo de Pascua', () {
    test('Pascua 2024 = 31 marzo', () {
      expect(ColombianHolidays.easterSunday(2024), DateTime(2024, 3, 31));
    });

    test('Pascua 2025 = 20 abril', () {
      expect(ColombianHolidays.easterSunday(2025), DateTime(2025, 4, 20));
    });

    test('Pascua 2026 = 5 abril', () {
      expect(ColombianHolidays.easterSunday(2026), DateTime(2026, 4, 5));
    });
  });

  group('Festivos colombianos 2026', () {
    test('Año Nuevo cae en jueves y no se mueve', () {
      expect(ColombianHolidays.isHoliday(DateTime(2026, 1, 1)), isTrue);
      expect(ColombianHolidays.holidayName(DateTime(2026, 1, 1)), 'Año Nuevo');
    });

    test('Reyes Magos se traslada al lunes 12 de enero (cae en martes 6)', () {
      expect(ColombianHolidays.isHoliday(DateTime(2026, 1, 6)), isFalse);
      expect(ColombianHolidays.isHoliday(DateTime(2026, 1, 12)), isTrue);
      expect(
        ColombianHolidays.holidayName(DateTime(2026, 1, 12)),
        'Día de los Reyes Magos',
      );
    });

    test('Jueves y Viernes Santo no se trasladan', () {
      expect(
        ColombianHolidays.holidayName(DateTime(2026, 4, 2)),
        'Jueves Santo',
      );
      expect(
        ColombianHolidays.holidayName(DateTime(2026, 4, 3)),
        'Viernes Santo',
      );
    });

    test('Día del Trabajo (1 mayo) viernes, no se mueve', () {
      expect(ColombianHolidays.isHoliday(DateTime(2026, 5, 1)), isTrue);
    });

    test('Navidad 2026 cae en viernes y no se mueve', () {
      expect(ColombianHolidays.isHoliday(DateTime(2026, 12, 25)), isTrue);
    });
  });

  group('isSundayOrHoliday', () {
    test('Domingo común', () {
      expect(
        ColombianHolidays.isSundayOrHoliday(DateTime(2026, 5, 3)),
        isTrue,
      );
    });

    test('Lunes laboral común', () {
      expect(
        ColombianHolidays.isSundayOrHoliday(DateTime(2026, 5, 4)),
        isFalse,
      );
    });

    test('Lunes festivo (corrido por Ley Emiliani)', () {
      // El 1 noviembre 2026 cae domingo → Todos los Santos se mueve al 2 nov.
      expect(
        ColombianHolidays.isSundayOrHoliday(DateTime(2026, 11, 2)),
        isTrue,
      );
    });
  });
}
