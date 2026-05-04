/// Categorías legales de horas reportadas a nómina.
enum HoursCategory {
  /// Jornada ordinaria L–V o sábado, sin recargo.
  ordinary,

  /// Hora extra diurna (06:00 – 19:00, fuera de jornada ordinaria, día hábil).
  extraDay,

  /// Hora extra nocturna (19:00 – 06:00, día hábil).
  extraNight,

  /// Hora dominical diurna ordinaria (jornada laboral en domingo/festivo).
  sundayOrdinary,

  /// Hora extra dominical diurna (fuera de jornada ordinaria, en domingo/festivo,
  /// dentro de la franja diurna).
  extraSundayDay,

  /// Hora extra dominical nocturna (fuera de jornada ordinaria, en domingo/festivo,
  /// dentro de la franja nocturna).
  extraSundayNight,

  /// Tiempo descontado por almuerzo. No se paga; se reporta solo para diagnóstico.
  lunch;

  String get label => switch (this) {
        HoursCategory.ordinary => 'Hora ordinaria',
        HoursCategory.extraDay => 'Hora extra diurna',
        HoursCategory.extraNight => 'Hora extra nocturna',
        HoursCategory.sundayOrdinary => 'Hora dominical diurna ordinaria',
        HoursCategory.extraSundayDay => 'Hora extra dominical diurna',
        HoursCategory.extraSundayNight => 'Hora extra dominical nocturna',
        HoursCategory.lunch => 'Almuerzo (no contabiliza)',
      };

  String get id => name;
}

/// Acumulado de duraciones por categoría.
class HoursBreakdown {
  HoursBreakdown({Map<HoursCategory, Duration>? totals})
      : totals = {
          for (final c in HoursCategory.values) c: Duration.zero,
          ...?totals,
        };

  final Map<HoursCategory, Duration> totals;

  void add(HoursCategory category, Duration duration) {
    totals[category] = (totals[category] ?? Duration.zero) + duration;
  }

  HoursBreakdown operator +(HoursBreakdown other) {
    final result = HoursBreakdown();
    for (final c in HoursCategory.values) {
      result.totals[c] =
          (totals[c] ?? Duration.zero) + (other.totals[c] ?? Duration.zero);
    }
    return result;
  }

  Duration get totalPaid => HoursCategory.values
      .where((c) => c != HoursCategory.lunch)
      .map((c) => totals[c] ?? Duration.zero)
      .fold(Duration.zero, (a, b) => a + b);

  Duration get(HoursCategory c) => totals[c] ?? Duration.zero;

  Map<String, int> toMinutesMap() => {
        for (final c in HoursCategory.values)
          c.id: (totals[c] ?? Duration.zero).inMinutes,
      };

  factory HoursBreakdown.fromMinutesMap(Map<String, dynamic> map) {
    final result = HoursBreakdown();
    for (final c in HoursCategory.values) {
      final minutes = (map[c.id] as num?)?.toInt() ?? 0;
      result.totals[c] = Duration(minutes: minutes);
    }
    return result;
  }
}

String formatHours(Duration d) {
  final h = d.inMinutes ~/ 60;
  final m = d.inMinutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}
