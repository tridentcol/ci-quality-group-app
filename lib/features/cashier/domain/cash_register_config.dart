/// Configuración del cierre de caja: singleton admin-only en
/// `settings/cash_register_config`.
///
/// Hoy solo guarda la hora de cierre, que es un **recordatorio operativo**
/// — NO la frontera del dinero (esa la define la ventana contigua de cada
/// turno). Cuando esa hora pasa y la caja sigue abierta, la pantalla lo
/// sugiere; nada más.
class CashRegisterConfig {
  const CashRegisterConfig({required this.closingTime});

  /// Hora de cierre sugerida en formato 24h `'HH:mm'` (ej. `'18:00'`).
  final String closingTime;

  const CashRegisterConfig.defaults() : closingTime = '18:00';

  /// Hora/minuto parseados del [closingTime]. Cae a 18:00 si el string
  /// guardado quedó malformado (defensivo — el setter siempre escribe bien).
  ({int hour, int minute}) get parsed {
    final parts = closingTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return (hour: 18, minute: 0);
    }
    return (hour: hour, minute: minute);
  }

  Map<String, dynamic> toMap() => {'closingTime': closingTime};

  factory CashRegisterConfig.fromMap(Map<String, dynamic> data) {
    final raw = data['closingTime'] as String?;
    if (raw == null || raw.isEmpty) return const CashRegisterConfig.defaults();
    return CashRegisterConfig(closingTime: raw);
  }
}
