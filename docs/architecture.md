# Arquitectura

Capas, providers, routing y patrones que rigen el código. Si tocás
arquitectura, actualizá este doc.

## Capas

Cada feature en `lib/features/<name>/` sigue **clean architecture light**:

```
presentation/   ← widgets, screens, ConsumerWidget. NO accede a Firebase directo.
    ↓ consume
data/           ← Repository (Firebase Firestore/Auth) + providers de Riverpod.
    ↓ usa
domain/         ← Modelos puros + lógica de negocio. Sin imports de Firebase ni Flutter.
```

**Regla**: `presentation/` nunca importa `cloud_firestore` ni `firebase_auth`.
Si necesita data, usa un provider expuesto desde `data/`.

## Estado: Riverpod

Convenciones:

- **Providers globales** se declaran al final del archivo donde vive el
  repositorio o modelo. No hay un `providers.dart` centralizado.
- **Naming:**
  - `xxxRepositoryProvider` — singleton del repo (`Provider<XxxRepository>`).
  - `xxxProvider` — stream/future del data leído del repo. Casi siempre `autoDispose`.
  - `xxxByIdProvider`, `xxxByRangeProvider` — `family` con argumento tipado.
- **`ref.watch(authStateProvider)`** dentro de un StreamProvider es la
  forma de **rebindear listeners cuando cambia la sesión**. Hacelo en
  todos los providers que tocan Firestore. Si no, los listeners viejos
  se quedan con tokens stale post-login y devuelven `permission-denied`.
- **`autoDispose`** por default — solo prescindir cuando explícitamente
  querés que el stream sobreviva navegación (caso raro).

### Patrón estándar de provider de stream

```dart
final salesByRangeProvider =
    StreamProvider.family.autoDispose<List<Sale>, SalesDateRange>((ref, range) {
  ref.watch(authStateProvider);   // ← rebind on auth change
  return ref
      .watch(salesRepositoryProvider)
      .watchByDateRange(range.start, range.end);
});
```

### Métricas: separar "data crudo" de "métrica computada"

`metrics.dart` expone:

- `salesByRangeProvider` → lista cruda de `Sale`.
- `salesMetricsProvider(range)` → un `Provider.family` que mapea
  `salesByRangeProvider.whenData(SalesMetrics.compute)`. Esto memoiza:
  Riverpod recompute solo si cambia la lista de ventas, no en cada `build()`.

Mismo patrón para `clientMetricsProvider`, `hoursMetricsProvider`.

## Routing: go_router

Una sola instancia en `lib/core/routing/app_router.dart`:

- **`routerProvider`** — único `Provider<GoRouter>`.
- **`_routerRefreshProvider`** — `ValueNotifier<int>` que listenea
  `authStateProvider` + `currentProfileProvider` para que el router
  reaccione a cambios de sesión sin recrearse.
- **`redirect`** — única fuente de verdad sobre acceso por rol:
  - No logueado → `/login`
  - Logueado sin perfil cargado → `/` (splash con spinner)
  - Logueado con perfil → home del rol (`/admin`, `/sales`, `/hours`, `/audit`)
  - Acceso a ruta de rol que no le corresponde → home del rol
- **ShellRoute para admin** — el admin tiene NavigationRail/drawer
  persistente vía `AdminShell`. Las rutas `/admin/*` viven adentro.
- **Patrón dual operativo/gerencia** — `/hours` (fuera del shell,
  pantalla operativa del rol) + `/admin/hours` (dentro del shell,
  vista de gerencia) es el precedente que siguió `/material` +
  `/admin/material`: la persona que hace el trabajo entra por la
  ruta top-level, el admin ve el agregado desde el shell. Ambos
  apuntan al mismo detalle (`/material/:id`) para no duplicar pantalla.
- **Detalle/edit** — patrón `(_, state) => _EditXRoute(id: state.pathParameters['id']!)`
  donde `_EditXRoute` envuelve el screen con un `_asyncEntityScreen` helper
  que maneja loading/error/null antes de pasarle el modelo al screen real.

## Firebase init

En `main.dart`:

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. Init en paralelo: timezones, locale `es_CO`, Firebase.
3. `SharedPreferences` para tema (sincrono después de cargar).
4. `Firestore.persistenceEnabled = true` **solo en native** (`!kIsWeb`),
   en try/catch (IndexedDB puede fallar en incógnito web).
5. `runApp(ProviderScope(...))`.

El `_initFirebase` traga el error `duplicate-app` que aparece en mobile
cuando el plugin nativo inicializa antes que Dart.

## Auth: pseudo-emails

Firebase Auth exige emails. La app usa **username + password** internamente.
`AppUser.emailFor(username) => '$username@cqg.app'`. Los usuarios nunca
ven correos. Cuando admin crea un usuario, le pasa solo el username.

## Multi-platform: conditional imports

Para código que diverge entre web y native usamos imports condicionales:

```dart
import '_export_io.dart' if (dart.library.html) '_export_web.dart' as deliver;
```

- `_export_io.dart` — usa `dart:io`, `path_provider`, `share_plus`.
- `_export_web.dart` — usa `dart:html` para Blob + AnchorElement download.

Ambos archivos exportan la **misma API pública** (`ExportFile` class,
`deliverFiles(...)` function). El consumidor (`xlsx_export_service.dart`)
no sabe en qué plataforma corre.

**Nunca** importes directo `dart:io` desde un archivo compartido —
romperá el bundle web aunque uses `kIsWeb` para gatear.

## Formulario de ventas

`sale_form_screen.dart` lleva la creación/edición de una venta con la
estructura canónica de la app (fecha, documento, cliente, uno o más
items de material, totales). Es un layout estático — no hay un
constructor dinámico que pueda romperlo.

**Items de material** — el formulario soporta uno o varios items por
venta. El primer item es obligatorio; los adicionales se agregan con
el botón "Agregar otro material" y se pueden quitar uno a uno.
Internamente, cada item es un `_ItemFormState` con sus propios
controllers (cantidad, precio) más las selecciones reactivas de
material/variante/unidad. Al submit, se mapean a `SaleItem` y se pasan
al repo via `items: [...]`.

**Mirror del primer item** — `SalesRepository.createSale` / `updateSale`
escribe `items[0]` también a los campos top-level (`material`,
`materialVariant`, `unit`, `quantity`, `unitPrice`) para que las
queries indexadas (auditor filtrado por material/variant) sigan
funcionando. El `totalValue` siempre se recalcula como suma de los
subtotales de items.

Si agregás un campo core nuevo al modelo Sale:
1. Sumalo al constructor de `Sale` y a `toMap` / `fromSnapshot`.
2. Sumá el widget al layout de `sale_form_screen.dart` y a la
   pantalla de detalle (`sale_detail_screen.dart`).
3. Si el campo va a la card o al export xlsx, actualizalos también.

Ver `docs/workflows.md` → "Agregar un campo core a Sale".

## Listas maestras

`master_lists/{listId}` + subcolección `items/{itemId}`. El admin las
edita desde un panel. Cada lista tiene:

- `allowFreeText` — si `true`, el `MasterListField` permite captura
  libre (cualquier valor que el usuario escriba queda como sugerencia
  `userSuggested: true`). Si `false`, dropdown estricto.
- Items con `parent` opcional — permite jerarquías (ej. tipos de
  material por material principal).

El mapeo **listId → campo de Sale que referencia** vive en
`master_lists_repository.dart` (`_saleFieldByListId`). Es lo que
permite que **renombrar un item propague a sales históricas**.
Si agregás una lista nueva que aparece en sales, sumala a ese mapa.

## Anti-duplicados

Tres capas en `MasterListField` y `confirmFreeTextValues`:

1. **Autocomplete en vivo** mientras tipean.
2. **Snap on blur** — al perder foco, si lo escrito normaliza a un
   canónico existente (incl. fonética), se ajusta silenciosamente.
3. **Modal de confirmación al guardar** — `confirmFreeTextValues` en
   `duplicate_check.dart` corre antes del submit y abre un modal si
   detecta similitud Levenshtein sospechosa.

Normalización en `core/utils/text_match.dart` (h muda, b/v, z=s, etc.).

## Theme

`AppTheme.light()` y `AppTheme.dark()` en `core/theme/app_theme.dart`.
Paleta en `app_colors.dart` (verdes corporativos + grises 100 % neutros).

El modo se persiste en SharedPreferences (`themeModeProvider`).

## Notificaciones in-app

El bell del AppBar + bottom sheet con la lista de notifs. **No** usamos
FCM/APNs por ahora (push del SO requiere setup de Mac + service workers
+ certificados iOS) ni Cloud Functions custom (la app no tiene backend
propio — la única excepción es la extensión oficial de correo del
control de material, ver más abajo, que es un paquete manejado por
Google, no código nuestro).

**Arquitectura:**

- Colección plana `notifications/{id}` (ver `docs/data-model.md`).
- Cliente escribe la notif **en la misma `runTransaction`** que produce
  el evento. Lo hace `NotificationsRepository.emitInTxn`, que solo hace
  `txn.set` (sin reads) para no romper la regla de Firestore "todos los
  reads antes que los writes".
- Cliente lee via dos queries paralelas (`targetUids` / `targetRoles`)
  porque Firestore no permite OR. El merge + dedup + recorte a 30 días
  vive en `_merge` del repo.

**Triggers actuales** (ver tabla en `docs/workflows.md` → "Agregar un
tipo nuevo de notificación"):

| Evento                       | Target                            |
|------------------------------|-----------------------------------|
| sales/admin crea solicitud   | roles cajero + admin              |
| cajero procesa               | uid del sales que la creó         |
| cajero cancela               | uid del sales que la creó         |
| cajero devuelve a sales      | uid del sales que la creó         |
| cajero marca pérdida         | rol admin                         |
| admin anula abono            | uid del cajero que lo registró    |

**Anti-ruido:** registerPayment, takeRequest, updates menores NO disparan
notif. Si en el futuro se justifica avisar un abono individual, se suma
un tipo nuevo (no se reutiliza `saleProcessed`).

**UI:**

- `NotificationsBell` (en `lib/shared/widgets/`) vive en
  `AppBar.actions` de cada home por rol, y dentro del rail/drawer del
  AdminShell.
- `NotificationsSheet` se abre como `showModalBottomSheet` con
  `isScrollControlled: true` (DraggableScrollableSheet adentro). Filtro
  "Todas / No leídas" y botón "Marcar todas" arriba.
- **Agrupación visual:** consecutivas del mismo `type` dentro de 1h se
  unen en un grupo expandible (cada notif persiste por separado en
  backend). Esto se computa en `_groupNotifications` del sheet.
- Tap en item → `markAsRead` + navegación al recurso (path según rol:
  cajero/admin van a `/cashier/:id`, el resto a `/sales/:id`).

**Cuándo evaluar mover a push del SO:** si el usuario necesita avisos
con la app cerrada o en background. Hoy no es el caso — los avisos son
útiles solo durante la sesión activa de trabajo, y el bell con badge
cubre el 100% de ese flujo.

## Cloud Storage: fotos del control de material

Primera vez que la app sube archivos binarios (hasta ahora solo
generaba/compartía `.xlsx`). Patrón en
`lib/features/material/data/material_entries_repository.dart`:

- **Sin conditional import** — a diferencia de `xlsx_export_service`
  (que sí diverge web/native), `image_picker` y `firebase_storage`
  exponen la misma API en las 3 plataformas: `XFile.readAsBytes()` +
  `Reference.putData(Uint8List)`. Un solo archivo de código sirve para
  Android, iOS y Web.
- **Id generado en cliente antes de subir**: `_col.doc()` da un id sin
  escribir todavía. Se usa ese id para el path en Storage
  (`material_entries/{id}/...`) y luego para el doc de Firestore — así
  las fotos ya tienen URL antes de que el doc exista.
- **Download URLs sin sesión**: `getDownloadURL()` de Firebase Storage
  devuelve una URL con un token embebido que **no requiere Firebase
  Auth** para verse — es justo lo que permite incrustar la foto como
  `<img>` en el correo a gerencia sin que el destinatario tenga que
  loguearse. La lectura autenticada (`storage.rules`) es una capa
  aparte que protege quién puede listar/enumerar objetos desde la app.
- **`storage.rules`** (raíz del repo, análogo a `firestore.rules`)
  usa `firestore.get()` — una función cross-service de Storage Rules
  v2 — para leer `users/{uid}` y decidir el rol, mismo criterio que
  Firestore. Deploy: `firebase deploy --only storage`.

## Extensión de correo: `firestore-send-email`

El control de material manda un correo a gerencia por cada ingreso
nuevo. Como la app no tiene backend custom, esto usa la extensión
oficial de Firebase **`firestore-send-email`**: el cliente escribe un
doc en `mail/{id}` (`to` + `message.subject/html`) y la extensión —
instalada y configurada por el usuario, con sus propias credenciales
SMTP — lo envía. Es la única pieza de la app que corre como Cloud
Function, pero es un paquete pre-armado y mantenido por Google, no
código que mantengamos nosotros.

Si `settings/material_notifications.recipientEmails` está vacío, el
repo no escribe nada en `mail/` — el resto del flujo (dashboard,
notificación in-app) sigue funcionando igual. Sin la extensión
instalada, los docs en `mail/` simplemente quedan sin procesar; no
rompen nada.

## Auditor: filtro genérico

`AppUser.auditFilter: AuditFilter?` con `field` + `value`. El campo
puede ser cualquier columna indexable de `sales`: `materialVariant`,
`material`, `providerName`, `payerName`, `paymentMethod`,
`transferDestination`. El dashboard usa `salesByFieldProvider` para
filtrar.

Para agregar un nuevo campo filtrable, actualizá:
- `user_form_screen.dart` → `_fieldOptions`, `_listIdForField`, `_labelForField`.
- `app_user.dart` → `AuditFilter.fieldLabel`.
