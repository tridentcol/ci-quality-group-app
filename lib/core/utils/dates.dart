import 'package:flutter/material.dart' show TimeOfDay;
import 'package:intl/intl.dart';

// Formatos locales en español de Colombia. La hora se imprime con AM/PM
// (`h:mm a` → "7:30 a. m.") porque es la convención esperada por los usuarios.
final DateFormat _dmy = DateFormat('dd/MM/yyyy', 'es_CO');
final DateFormat _dmyHm = DateFormat('dd/MM/yyyy h:mm a', 'es_CO');
final DateFormat _hm = DateFormat('h:mm a', 'es_CO');
final DateFormat _monthYear = DateFormat('MMMM yyyy', 'es_CO');

String formatDate(DateTime d) => _dmy.format(d);
String formatDateTime(DateTime d) => _dmyHm.format(d);
String formatTime(DateTime d) => _hm.format(d);
String formatMonth(DateTime d) => _monthYear.format(d);

/// Formato 12h consistente para un `TimeOfDay`. El default
/// `TimeOfDay.format(context)` respeta el locale (24h en `es_CO`), así que
/// no podemos depender de él si queremos AM/PM forzado.
String formatTimeOfDay(TimeOfDay t) {
  final dt = DateTime(2000, 1, 1, t.hour, t.minute);
  return _hm.format(dt);
}

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
