/// Rutas centralizadas a las colecciones de Firestore.
///
/// Cualquier cambio de estructura se hace acá y se propaga al resto de la app.
class FirestorePaths {
  FirestorePaths._();

  // Usuarios de la app (admin / sales / hours).
  static const users = 'users';

  // Trabajadores (registros maestros, no usuarios).
  static const workers = 'workers';

  // Ventas.
  static const sales = 'sales';

  // Registros de horas (uno por trabajador-día).
  static const hoursEntries = 'hours_entries';

  // Listas maestras gestionadas por el admin: proveedores, pagadores,
  // materiales, métodos de pago, unidades, etc.
  // Cada documento es una lista; los items son una subcolección.
  static const masterLists = 'master_lists';
  static String masterListItems(String listId) => '$masterLists/$listId/items';

  // Esquema dinámico del formulario de ventas (versión actual + historial).
  static const formSchemas = 'form_schemas';

  // Contadores atómicos (consecutivo de ventas).
  static const counters = 'counters';
  static const salesCounter = 'sales_consecutive';

  // Configuración global (jornadas, hora de almuerzo, etc.).
  static const settings = 'settings';
  static const workScheduleSettings = 'work_schedule';

  // Notificaciones in-app (campana del AppBar). Colección plana con
  // targets por uid y/o rol — ver `AppNotification`.
  static const notifications = 'notifications';
}
