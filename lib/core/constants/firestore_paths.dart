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

  // Contadores atómicos (consecutivo de ventas).
  static const counters = 'counters';
  static const salesCounter = 'sales_consecutive';

  // Configuración global (jornadas, hora de almuerzo, etc.).
  static const settings = 'settings';
  static const workScheduleSettings = 'work_schedule';

  // Estado runtime de la caja (turno abierto/cerrado). Doc singleton
  // dentro de `settings`. Ver `CashRegister`.
  static const cashRegisterSettings = 'cash_register';

  // Configuración del cierre de caja (hora de cierre recordatorio). Doc
  // singleton admin-only dentro de `settings`. Ver `CashRegisterConfig`.
  static const cashRegisterConfigSettings = 'cash_register_config';

  // Ledger append-only de turnos de caja (un doc por turno). Ver `CashShift`.
  static const cashShifts = 'cash_shifts';

  // Notificaciones in-app (campana del AppBar). Colección plana con
  // targets por uid y/o rol — ver `AppNotification`.
  static const notifications = 'notifications';

  // Control de ingreso/salida de material (fotos, proveedor o cliente,
  // cantidad). Ambos tipos viven en la misma colección `material_entries`
  // (campo `type`), pero cada uno tiene su propio contador atómico para
  // que el consecutivo ING-XXX/SAL-XXX no se mezcle.
  static const materialEntries = 'material_entries';
  static const materialEntriesCounter = 'material_entries_consecutive';
  static const materialExitsCounter = 'material_exits_consecutive';

  // Colección que consume la extensión de Firebase `firestore-send-email`.
  // Un doc acá = un correo en cola para gerencia.
  static const mail = 'mail';

  // Config admin-only con los destinatarios del correo de material. Doc
  // singleton dentro de `settings`.
  static const materialNotificationSettings = 'material_notifications';
}
