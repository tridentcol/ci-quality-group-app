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

## Form Builder dinámico

`lib/features/form_builder/` permite al admin definir qué campos
aparecen en el formulario de ventas, en qué orden, requeridos o no,
visibles a qué roles, etc. Se persiste en `form_schemas/{module}`.

- **`FormSchema`** — lista de `FieldDefinition` con `id`, `label`,
  `coreField`, `required`, `visibleToRoles`, `masterListId`, etc.
- **Core fields** — los del modelo `Sale` (date, documentType,
  providerName, material, etc.). Tienen widgets específicos en
  `sale_form_screen.dart > _buildCoreField`. No se pueden agregar/quitar
  desde el constructor; solo se puede ocultarlos por rol.
- **Custom fields** — el admin puede agregarlos. Se renderean con
  `buildDynamicField()` de `dynamic_form_renderer.dart`. Su valor se
  guarda en `Sale.customFields: Map<String, dynamic>`.

Si agregás un campo core nuevo al modelo Sale, también hay que:
1. Agregarlo al `FormSchema` default en `form_schema.dart`.
2. Agregar un `case` en `_buildCoreField` con el widget.
3. Actualizar `_renderSchemaFields` si necesita visibilidad condicional.

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
+ certificados iOS) ni Cloud Functions (la app no tiene backend custom).

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

| Evento                       | Target                       |
|------------------------------|------------------------------|
| sales crea solicitud         | roles cajero + admin         |
| cajero procesa               | uid del sales que la creó    |
| cajero cancela               | uid del sales que la creó    |
| cajero marca pérdida         | rol admin                    |

**Anti-ruido:** registerPayment, takeRequest, returnToSales, updates
menores NO disparan notif. Si en el futuro se justifica avisar un abono,
se suma un tipo nuevo (no se reutiliza `saleProcessed`).

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

## Auditor: filtro genérico

`AppUser.auditFilter: AuditFilter?` con `field` + `value`. El campo
puede ser cualquier columna indexable de `sales`: `materialVariant`,
`material`, `providerName`, `payerName`, `paymentMethod`,
`transferDestination`. El dashboard usa `salesByFieldProvider` para
filtrar.

Para agregar un nuevo campo filtrable, actualizá:
- `user_form_screen.dart` → `_fieldOptions`, `_listIdForField`, `_labelForField`.
- `app_user.dart` → `AuditFilter.fieldLabel`.
