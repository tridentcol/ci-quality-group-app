/// Los tres roles fijos de la app.
enum AppRole {
  admin,
  sales,
  hours;

  String get label => switch (this) {
        AppRole.admin => 'Administrador',
        AppRole.sales => 'Control de ventas',
        AppRole.hours => 'Control de horas',
      };

  String get id => name;

  static AppRole fromId(String id) => AppRole.values.firstWhere(
        (r) => r.id == id,
        orElse: () => throw ArgumentError('Rol desconocido: $id'),
      );
}
