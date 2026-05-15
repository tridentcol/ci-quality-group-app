# Plan Fase 9 — Observabilidad + Cierre de caja + Audit log

Estado: **pendiente, no iniciado** (escrito 2026-05-14).
Rama de trabajo sugerida: `claude/check-system-status-FP9g9` (la misma de
fases 1-8) o una nueva `claude/fase-9` si se quiere aislar.

Este plan agrupa tres mejoras independientes pero complementarias que el
producto necesita para escalar con confianza. **Cada fase se puede
ejecutar y desplegar por separado** — no hay que terminar las tres antes
de mandar APK / web.

---

## Por qué estas tres y por qué en este orden

| Fase | Qué resuelve | Depende de |
|------|--------------|------------|
| **A. Crashlytics** | Hoy no te enterás si la app crashea en producción salvo que alguien te avise. Visibilidad cero. | Nada. Va primero porque si las fases B/C rompen algo en deploy, te enterás al instante. |
| **B. Audit log inmutable** | Acciones sensibles (`voidPayment`, `markAsLoss`, merges, role changes) dejan un rastro borrable. Si hay disputa legal o auditoría externa, no hay manera de reconstruir "quién hizo qué cuándo". | Va antes de C porque C lo usa para registrar reaperturas de cierre. |
| **C. Cierre de caja diario** | El workflow de cajero no tiene cierre formal. Las ediciones retroactivas son posibles sin trazabilidad. | Audit log para registrar reaperturas. |

---

## Fase A — Firebase Crashlytics

### Objetivo

Captura automática de errores no manejados en Android e iOS, con stack
traces visibles en Firebase Console. Web queda fuera de scope porque
`firebase_crashlytics` aún no soporta web (al 2026-05); se documenta el
gap y se deja un TODO para Sentry-flutter si se necesita más adelante.

### Pasos

#### A.1 Setup en Firebase Console (acción humana, no se puede automatizar)

1. Entrar a Firebase Console → proyecto `quality-group-app` → Crashlytics
   en el menú izquierdo.
2. Click "Enable Crashlytics". Aceptar términos.
3. Confirmar que el proyecto Android (`co.ciqualitygroup.ci_quality_group`)
   aparece registrado.

#### A.2 Dependencias

Agregar a `pubspec.yaml`:

```yaml
firebase_crashlytics: ^4.x.x  # versión más reciente compatible con firebase_core 3.x
```

Correr `flutter pub get`.

#### A.3 Inicialización en `lib/main.dart`

```dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Crashlytics solo en native — en web el plugin no funciona.
  if (!kIsWeb) {
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    // En debug builds NO mandar reportes — ensucia el panel con bugs
    // que el dev ya está viendo en su consola.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
  }

  // ... resto del setup actual (Firestore settings, etc.)
  runApp(const ProviderScope(child: CqgApp()));
}
```

#### A.4 Asociar usuario al crash

Cuando se resuelve el perfil del usuario logueado, asociarlo:

```dart
// En el AuthRepository, cuando hay un currentProfile:
if (!kIsWeb && profile != null) {
  await FirebaseCrashlytics.instance.setUserIdentifier(profile.uid);
  await FirebaseCrashlytics.instance.setCustomKey('role', profile.role.id);
}
```

#### A.5 Verificar que funciona

1. Agregar temporalmente un botón "Test crash" en algún screen de admin
   en debug:
   ```dart
   ElevatedButton(
     onPressed: () => throw Exception('Crashlytics smoke test'),
     child: const Text('Crash test'),
   );
   ```
2. Buildear release APK, instalarlo, tocar el botón.
3. Esperar ~5 min, verificar que aparece en Firebase Console.
4. Sacar el botón antes del deploy final.

#### A.6 Configurar dSYM (iOS, si aplica)

Si en algún momento se distribuye iOS, hay que subir los símbolos para
que las stack traces sean legibles. Por ahora no aplica.

### Acceptance criteria fase A

- [ ] `firebase_crashlytics` instalado y `Firebase.initializeApp()` lo registra.
- [ ] Crashes en Android se ven en Console < 5 min después.
- [ ] El usuario logueado aparece asociado al crash.
- [ ] Debug builds NO contaminan el panel.
- [ ] Web sigue funcionando exactamente igual (sin cambios visibles).

---

## Fase B — Audit log inmutable

### Objetivo

Registrar acciones sensibles en una colección append-only que nadie puede
editar ni borrar. Sirve para auditoría externa, disputas con clientes y
debugging post-mortem.

### Acciones a registrar (al inicio)

1. `void_payment` — admin anula un abono.
2. `mark_as_loss` — cajero/admin marca una venta como pérdida.
3. `sale_canceled` — cajero cancela una solicitud.
4. `master_list_merge` — admin fusiona items duplicados.
5. `user_role_changed` — admin cambia rol de un usuario.
6. `cash_closure_reopened` — admin reabre un día cerrado (depende de Fase C).

**No registrar**: lecturas, creates triviales (nueva venta), marcado de
notif como leída. Sería ruido.

### B.1 Modelo

Nueva colección `audit_log/{id}`:

```
{
  actorUid: String           // quién ejecutó
  actorName: String          // cacheado para reportes
  actorRole: String          // 'admin' | 'cajero' | ...
  action: String             // 'void_payment' | 'mark_as_loss' | ...
  entityPath: String         // 'sales/{id}/payments/{pid}'
  entityType: String         // 'payment' | 'sale' | 'master_list_item' | 'user'
  before: Map<String, dynamic>?  // snapshot antes (null si es create)
  after: Map<String, dynamic>?   // snapshot después (null si es delete)
  reason: String?            // razón si la acción la pide (ej. voidPayment)
  timestamp: Timestamp
  metadata: Map<String, dynamic>  // free-form: device, ip, etc — opcional
}
```

### B.2 Firestore rules

Agregar a `firestore.rules`:

```
match /audit_log/{id} {
  allow create: if isAuthenticated()
                  && request.resource.data.actorUid == request.auth.uid;
  allow read: if isAdmin();
  allow update, delete: if false;  // truly immutable
}
```

### B.3 Servicio

Nuevo archivo `lib/shared/services/audit_log_repository.dart`:

```dart
class AuditLogRepository {
  AuditLogRepository(this._firestore);
  final FirebaseFirestore _firestore;

  /// Versión transaccional — para callers ya adentro de runTransaction.
  /// Solo hace txn.set (no reads), respetando la regla de ordering.
  void emitInTxn(
    Transaction txn, {
    required AppUser actor,
    required String action,
    required String entityPath,
    required String entityType,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? reason,
    Map<String, dynamic> metadata = const {},
  }) {
    final ref = _firestore.collection('audit_log').doc();
    txn.set(ref, {
      'actorUid': actor.uid,
      'actorName': actor.fullName,
      'actorRole': actor.role.id,
      'action': action,
      'entityPath': entityPath,
      'entityType': entityType,
      'before': before,
      'after': after,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
      'metadata': metadata,
    });
  }

  /// Standalone (sin transacción).
  Future<void> emit({ ... }) { ... }

  Stream<List<AuditLogEntry>> watchRecent({int limit = 100}) { ... }
}

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository(FirebaseFirestore.instance);
});
```

### B.4 Hooks

En `cashier_repository.dart`, llamar `auditLog.emitInTxn(...)` adentro de
cada `runTransaction` para:
- `voidPayment` después del `txn.delete`.
- `markAsLoss` después del `txn.update`.
- `cancelRequest` después del `txn.update`.

En `duplicate_service.dart` (donde está `applyMerges`):
- Por cada merge ejecutado, un audit log con before/after de los items.

En `users_repository.dart`:
- Cuando se cambia un rol, un audit log con before/after.

**Importante**: Las inyecciones del repository van vía Riverpod, no
hardcodeadas. Los repos toman `AuditLogRepository` por constructor.

### B.5 Pantalla admin

Nueva screen `lib/features/admin/presentation/audit_log_screen.dart`
accesible desde el drawer del admin como "Auditoría":
- Lista cronológica desc (más reciente arriba).
- Filtros: action (chip multiselect), actor (dropdown), rango de fechas.
- Cada item muestra: ícono + actor + acción + entity + timestamp.
- Tap → modal con detalle (before/after side-by-side o diff visual).
- Export a Excel (reusar el `xlsx_export_service` existente).

Ruta: `/admin/audit-log`. Visible solo para admin.

### Acceptance criteria fase B

- [ ] `audit_log` collection con rules immutables desplegadas.
- [ ] 6 acciones disparan logs verificables manualmente.
- [ ] Pantalla `/admin/audit-log` lista, filtra y exporta.
- [ ] Tests unitarios para `AuditLogRepository.emit` y `emitInTxn`.
- [ ] Doc actualizado en `docs/data-model.md` con el schema nuevo.

---

## Fase C — Cierre de caja diario

### Objetivo

Workflow formal de "fin de jornada" para el rol cajero. Genera snapshot
inmutable de los totales del día y bloquea edits retroactivos sobre los
abonos de ese día.

### C.1 Modelo

Nueva colección `cash_closures/{date}` donde `date` es `'YYYY-MM-DD'`
(documento por día):

```
{
  date: '2026-05-14'                    // string ISO yyyy-MM-dd
  closedAt: Timestamp
  closedBy: String                       // uid
  closedByName: String
  totalCollected: Number                 // sum de payments del día
  totalSales: Number                     // count de ventas con estado 'procesada' ese día
  byMethod: { 'Efectivo': N, 'Transferencia': N }
  byPayer: { 'Juan': N, 'María': N }
  losses: Number                         // pérdidas marcadas ese día
  metadata: { paymentsCount: N }
  reopenedAt: Timestamp?                 // si admin reabre, se setea
  reopenedBy: String?
  reopenedReason: String?
}
```

**Nota:** la clave del doc es el `date` (string) para que sea
idempotente — cerrar dos veces el mismo día es no-op (o requiere reabrir
primero).

### C.2 Firestore rules

```
match /cash_closures/{date} {
  allow read: if isCajero() || isAdmin();
  allow create: if (isCajero() || isAdmin())
                   && request.resource.data.closedBy == request.auth.uid;
  allow update: if isAdmin()
                   && request.resource.data.diff(resource.data)
                        .affectedKeys()
                        .hasOnly(['reopenedAt', 'reopenedBy', 'reopenedReason']);
  allow delete: if false;
}
```

Además, las rules de `sales/{id}/payments/{pid}` necesitan check de cierre:

```
// Bloquear write si el día del payment ya está cerrado
function isDayClosed(date) {
  return exists(/databases/$(database)/documents/cash_closures/$(date));
}

match /sales/{sid}/payments/{pid} {
  allow create: if isCajero() || isAdmin()
                   && !isDayClosed(dateOf(request.resource.data.registeredAt));
  // delete sigue siendo admin-only
  allow delete: if isAdmin()
                   && !isDayClosed(dateOf(resource.data.registeredAt));
}
```

⚠️ Limitación Firestore rules: no hay `dateOf(Timestamp)` builtin. Hay
que persistir el `dateKey` (`'YYYY-MM-DD'`) en el doc payment para que
la rule lo lea directamente.

### C.3 Servicio

Nuevo `lib/features/cashier/data/cash_closure_repository.dart`:

```dart
class CashClosureRepository {
  Future<CashClosure> closeDay({
    required DateTime date,
    required AppUser actor,
  }) async {
    // 1. Computar totales agregando payments de ese día.
    // 2. Verificar que no exista ya un closure para ese día.
    // 3. Crear el doc con runTransaction (atómico).
    // 4. Emitir audit log opcional (no es crítico — el doc en sí es el log).
  }

  Future<void> reopenDay({
    required DateTime date,
    required AppUser actor,
    required String reason,
  }) async {
    // Solo admin. Actualiza el doc con reopenedAt/By/Reason.
    // Emite audit log con action='cash_closure_reopened'.
  }

  Stream<CashClosure?> watchClosure(DateTime date) { ... }
  Stream<List<CashClosure>> watchRecent({int limit = 30}) { ... }
}
```

### C.4 UI

#### En `cashier_home_screen.dart`:

Tab nuevo o botón en AppBar **"Cerrar día"**:
- Pre-shows modal con los totales calculados del día (refresh en vivo).
- Confirma → llama `closeDay()` → snackbar éxito → tab "Cerradas" se
  actualiza con un banner verde "Día cerrado a las HH:mm".
- Si ya está cerrado: muestra el banner y deshabilita acciones que
  registren payments retroactivos para ese día.

#### En `sale_payments_screen.dart`:

Si la venta tiene `outstandingBalance > 0` pero el día actual está
cerrado → el FAB "Registrar abono" queda deshabilitado con tooltip
"El día está cerrado. Reabrí desde admin para registrar abonos."

#### Nueva screen `/admin/cash-closures`:

Lista histórica de cierres con stats:
- Día, total cobrado, # ventas, cerrado por, hora de cierre.
- Tap → detalle con desglose por método/payer.
- Botón "Reabrir día" (solo admin) que pide razón y dispara
  `reopenDay()` + audit log.

### C.5 Migración para data histórica

Las ventas y payments existentes NO tienen `dateKey`. Hay dos opciones:

1. **Backfill via script**: correr una vez un script que itere sobre
   `sales/{*}/payments/{*}` y agregue `dateKey` derivado de `registeredAt`.
2. **Fallback en cliente**: el modelo SalePayment computa `dateKey` on
   read si no viene del backend.

Recomiendo (2) para no requerir un script de migración. Backend nuevo
escribe `dateKey`, cliente legacy lo deriva.

### Acceptance criteria fase C

- [ ] `cash_closures` collection con rules deployadas.
- [ ] Botón "Cerrar día" en home de cajero funcional.
- [ ] Bloqueo de edits retroactivos en payments del día cerrado.
- [ ] Pantalla admin para listar/reabrir cierres.
- [ ] Reapertura emite audit log entry.
- [ ] Backfill de `dateKey` en payments existentes (fallback en cliente).
- [ ] Doc actualizado en `docs/data-model.md`.

---

## Gotchas conocidos

1. **firebase_crashlytics y web**: el plugin no soporta web (al 2026-05).
   Cualquier uso de la API tiene que ir bajo `if (!kIsWeb)`. No agregar
   Sentry-flutter sin pensarlo bien — duplica el setup.

2. **Reglas Firestore con `exists()`**: cada llamada cuenta como una
   lectura facturable. Verificar que la rule de payments con
   `isDayClosed(...)` no se dispara en bucle.

3. **Audit log se puede llenar rápido**: 6 acciones × N usuarios × N
   días. Considerar un TTL via Firebase Extensions o una cleanup
   manual cada año. Por ahora no es problema (volumen bajo).

4. **Cierre de caja y zonas horarias**: el "día" tiene que ser en la
   zona horaria de Colombia (UTC-5), no UTC. Reusar `core/utils/dates.dart`
   y `AppClock` para consistencia con el resto del proyecto.

5. **No romper el flujo actual**: las 8 fases previas funcionan. Al
   implementar esto, NO refactorizar `cashier_repository.dart` más allá
   de lo necesario. Adicional, no sustitutivo.

---

## Estimación

- Fase A: 0.5 día (todo en lib/main.dart + pubspec).
- Fase B: 2 días (repo + screen + 6 hooks + tests).
- Fase C: 3 días (modelo + rules + UI + bloqueo + screen admin + backfill).

Total: **~5.5 días** para las tres. Se pueden mergear y desplegar
independientes.

---

## Después de cada fase

1. `flutter analyze` con 0 issues.
2. `flutter test` con todos los suites pasando.
3. Build APK + web release.
4. Actualizar `CHANGELOG.md`, `docs/data-model.md`, `docs/architecture.md`,
   memoria (`memory/project_state.md`).
5. Commit + push a la rama de trabajo.
6. **No deployar sin OK del user.**
