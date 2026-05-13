/// Los roles fijos de la app.
///
/// - `admin`: control total + métricas + listas maestras + usuarios.
/// - `sales`: registra solicitudes de venta y consulta históricos propios.
/// - `hours`: marca entrada/salida de los trabajadores.
/// - `cajero`: toma las solicitudes de sales, las procesa, registra
///   abonos parciales y marca pérdidas. Es la única vía para mover el
///   workflow más allá de `generada`.
/// - `auditor`: lectura solamente, dashboard filtrado por un campo
///   configurable. Pensado para socios/inversores que quieren ver
///   solo las ventas de su material/variante (ej. Pedro ve solo
///   ventas con `materialVariant == "PEDRO"`).
enum AppRole {
  admin,
  sales,
  hours,
  cajero,
  auditor;

  String get label => switch (this) {
        AppRole.admin => 'Administrador',
        AppRole.sales => 'Control de ventas',
        AppRole.hours => 'Control de horas',
        AppRole.cajero => 'Caja',
        AppRole.auditor => 'Auditor / Inversor',
      };

  String get id => name;

  static AppRole fromId(String id) => AppRole.values.firstWhere(
        (r) => r.id == id,
        orElse: () => throw ArgumentError('Rol desconocido: $id'),
      );
}
