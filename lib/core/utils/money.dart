import 'package:intl/intl.dart';

/// Formato COP con punto de miles, sin decimales.
final NumberFormat _copFormatter = NumberFormat.currency(
  locale: 'es_CO',
  symbol: r'$',
  decimalDigits: 0,
);

String formatCop(num value) => _copFormatter.format(value);

/// Formato numérico simple con punto de miles (para cantidades en kg).
final NumberFormat _quantityFormatter = NumberFormat('#,##0.##', 'es_CO');

String formatQuantity(num value) => _quantityFormatter.format(value);
