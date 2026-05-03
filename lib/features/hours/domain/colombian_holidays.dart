/// Calendario de festivos de Colombia.
///
/// Implementa todas las reglas vigentes:
///  - Festivos de fecha fija (Año Nuevo, Trabajo, Independencia, etc.).
///  - Festivos religiosos relativos a la Pascua (Jueves Santo, Viernes Santo,
///    Ascensión, Corpus Christi, Sagrado Corazón).
///  - Festivos movibles por Ley Emiliani (Ley 51 de 1983 y Ley 35 de 1939):
///    si caen en día distinto a lunes, se trasladan al lunes siguiente.
///
/// El cálculo es totalmente determinístico y local, sin depender de internet.
library;

class Holiday {
  const Holiday({
    required this.date,
    required this.name,
    required this.movedToMonday,
  });

  /// Día observado del festivo (puede no coincidir con la fecha nominal).
  final DateTime date;

  /// Nombre legal del festivo.
  final String name;

  /// `true` si fue movido a lunes por Ley Emiliani.
  final bool movedToMonday;
}

class ColombianHolidays {
  ColombianHolidays._();

  /// Calcula el domingo de Pascua de un año (algoritmo Anonymous Gregorian).
  static DateTime easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// Devuelve el lunes igual o posterior a la fecha dada.
  static DateTime _nextOrSameMonday(DateTime d) {
    // DateTime.weekday: lunes=1 ... domingo=7.
    final delta = (DateTime.monday - d.weekday + 7) % 7;
    return DateTime(d.year, d.month, d.day + delta);
  }

  /// Lista de festivos del año, en orden cronológico.
  static List<Holiday> forYear(int year) {
    final easter = easterSunday(year);

    final holidays = <Holiday>[
      // Fijos (no se trasladan).
      Holiday(
          date: DateTime(year, 1, 1), name: 'Año Nuevo', movedToMonday: false),
      Holiday(
          date: DateTime(year, 5, 1),
          name: 'Día del Trabajo',
          movedToMonday: false),
      Holiday(
          date: DateTime(year, 7, 20),
          name: 'Día de la Independencia',
          movedToMonday: false),
      Holiday(
          date: DateTime(year, 8, 7),
          name: 'Batalla de Boyacá',
          movedToMonday: false),
      Holiday(
          date: DateTime(year, 12, 8),
          name: 'Inmaculada Concepción',
          movedToMonday: false),
      Holiday(
          date: DateTime(year, 12, 25), name: 'Navidad', movedToMonday: false),

      // Pascua (no se trasladan).
      Holiday(
        date: easter.subtract(const Duration(days: 3)),
        name: 'Jueves Santo',
        movedToMonday: false,
      ),
      Holiday(
        date: easter.subtract(const Duration(days: 2)),
        name: 'Viernes Santo',
        movedToMonday: false,
      ),

      // Ley Emiliani (siempre se observan en lunes).
      _emiliani(year, 1, 6, 'Día de los Reyes Magos'),
      _emiliani(year, 3, 19, 'Día de San José'),
      _emiliani(year, 6, 29, 'San Pedro y San Pablo'),
      _emiliani(year, 8, 15, 'Asunción de la Virgen'),
      _emiliani(year, 10, 12, 'Día de la Diversidad Étnica y Cultural'),
      _emiliani(year, 11, 1, 'Día de Todos los Santos'),
      _emiliani(year, 11, 11, 'Independencia de Cartagena'),

      // Pascua + traslado a lunes.
      Holiday(
        date: _nextOrSameMonday(easter.add(const Duration(days: 40))),
        name: 'Ascensión del Señor',
        movedToMonday: true,
      ),
      Holiday(
        date: _nextOrSameMonday(easter.add(const Duration(days: 61))),
        name: 'Corpus Christi',
        movedToMonday: true,
      ),
      Holiday(
        date: _nextOrSameMonday(easter.add(const Duration(days: 68))),
        name: 'Sagrado Corazón',
        movedToMonday: true,
      ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    return holidays;
  }

  static Holiday _emiliani(int year, int month, int day, String name) {
    final nominal = DateTime(year, month, day);
    final observed = _nextOrSameMonday(nominal);
    return Holiday(
      date: observed,
      name: name,
      movedToMonday: nominal.weekday != DateTime.monday,
    );
  }

  /// Cache de festivos por año para evitar recalcular en chequeos repetidos.
  static final Map<int, Map<int, Holiday>> _cache = {};

  static Map<int, Holiday> _byOrdinal(int year) {
    return _cache.putIfAbsent(year, () {
      final map = <int, Holiday>{};
      for (final h in forYear(year)) {
        map[_ordinal(h.date)] = h;
      }
      return map;
    });
  }

  static int _ordinal(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// `true` si la fecha cae en un festivo nacional.
  static bool isHoliday(DateTime date) {
    return _byOrdinal(date.year).containsKey(_ordinal(date));
  }

  /// Nombre del festivo, o `null` si no es festivo.
  static String? holidayName(DateTime date) {
    return _byOrdinal(date.year)[_ordinal(date)]?.name;
  }

  /// `true` si la fecha es domingo o festivo (jornada con recargo dominical).
  static bool isSundayOrHoliday(DateTime date) {
    return date.weekday == DateTime.sunday || isHoliday(date);
  }
}
