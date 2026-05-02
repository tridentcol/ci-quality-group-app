import 'package:intl/intl.dart';

final DateFormat _dmy = DateFormat('dd/MM/yyyy', 'es_CO');
final DateFormat _dmyHm = DateFormat('dd/MM/yyyy HH:mm', 'es_CO');
final DateFormat _hm = DateFormat('HH:mm', 'es_CO');
final DateFormat _monthYear = DateFormat('MMMM yyyy', 'es_CO');

String formatDate(DateTime d) => _dmy.format(d);
String formatDateTime(DateTime d) => _dmyHm.format(d);
String formatTime(DateTime d) => _hm.format(d);
String formatMonth(DateTime d) => _monthYear.format(d);

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
