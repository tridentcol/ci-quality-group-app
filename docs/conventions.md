# Convenciones de código

Reglas que el proyecto sigue de forma consistente. Si rompés una sin
razón, el agente revisor te lo va a marcar.

## Lint y formato

- **`flutter analyze` debe pasar sin errores antes de cualquier commit.**
  Warnings tolerables si son falsos positivos justificados.
- **`analysis_options.yaml`** define el set de lints. Trailing commas
  obligatorias en cualquier bloque multi-línea.
- **No usar `dart format` global** sin pensarlo — el repo tiene
  decisiones de estilo manual (ej. closing brackets bien identados con
  trailing commas explícitas). Si formateás, hacelo archivo por archivo.

## Naming

- **Archivos**: `snake_case.dart`.
- **Clases**: `PascalCase`.
- **Providers**: `xxxProvider` (camelCase final con sufijo `Provider`).
- **Privados a un archivo**: prefijo `_`. Usalo sin culpa para widgets
  internos (`_TotalCard`, `_DropdownField`, etc.).
- **Const string `_defaultXxx`**: para defaults sentinela locales.

## Estructura de archivos

- Una clase pública por archivo (la principal). Clases privadas y
  widgets internos pueden compartir archivo si están acoplados.
- Imports ordenados por bloques con línea en blanco entre:
  1. `dart:` (si usás)
  2. `package:flutter/`
  3. Otros `package:`
  4. Imports relativos (`../../../core/...`)

## Comentarios — política clara

**Default: NO escribas comentarios.** Solo agregá uno cuando:

1. **El WHY no es obvio** del código. Ejemplo:
   ```dart
   // Reuso watchByDateRange con un rango "amplio" para no tener que
   // agregar otro método al repository — desde 2020 hasta mañana.
   return repo.watchByDateRange(DateTime(2020), ...);
   ```
2. **Un workaround para un bug específico**:
   ```dart
   // fl_chart respeta `interval` solo en line charts. En bar chart
   // los labels se solapan independiente del intervalo.
   ```
3. **Una invariante o constraint oculto**:
   ```dart
   // 'lamina_brands' es el listId histórico; el display name cambió
   // a "Tipos de materiales" pero no podemos renombrar el id sin
   // migrar producción.
   ```
4. **Una decisión que un futuro lector podría querer revertir**:
   ```dart
   // Persistence offline desactivada en web: IndexedDB falla en
   // incógnito y deja la app trabada en el splash.
   ```

**No escribas:**

- Descripciones de lo que el código hace (`// Set the username` antes
  de `_username = v;`). Eso es ruido.
- Referencias al issue o PR que motivó el cambio (`// fix #42`). Eso
  rota fuera del PR.
- Comentarios "TODO" salvo que sean accionables ya (ideal: ticket
  externo).

**Sí escribí docstrings `///`** para:

- Clases públicas (lo que hacen, no cómo).
- Métodos no triviales en repositorios y servicios.
- Providers complejos.

Ejemplo bueno:

```dart
/// Renombra el `value` de un item del catálogo Y propaga el cambio a
/// todas las ventas que referencian el value viejo.
///
/// Diferencia con `updateItem`:
///   - `updateItem` solo toca el documento del catálogo.
///   - `renameItem` también reescribe sales históricas para mantener
///     consistencia entre catálogo y ventas.
///
/// Devuelve cuántas ventas se actualizaron.
Future<int> renameItem({ ... }) async { ... }
```

## Riverpod

- **No mezcles `ref.read` y `ref.watch` al voleo.** `watch` en build,
  `read` en callbacks/funciones imperativas (`onPressed`, etc.).
- **`ref.watch(authStateProvider)`** en todo StreamProvider que toca
  Firestore — fuerza rebind del listener al cambiar sesión.
- **`autoDispose`** por default. Solo no-autoDispose cuando explícitamente
  querés que sobreviva navegación.
- **`Provider.family`** para queries parametrizadas — siempre tipá el
  argumento con una clase `==`/`hashCode` (ej. `SalesDateRange`,
  `MasterListItemsQuery`). No uses tuples ni records — Riverpod requiere
  identidad de valor estable.

## Errores

- **`AsyncValue.when(loading:, error:, data:)`** en la UI — usá
  `AppErrorView` para el caso `error` y `SkeletonList` o
  `CircularProgressIndicator` para `loading`.
- **`friendlyError(e)`** en `core/utils/errors.dart` convierte excepciones
  de Firebase/Firestore a strings legibles en español. Usá siempre que
  vayas a mostrarle el error a un usuario.

## Validación

- En formularios, `Form` + `GlobalKey<FormState>` + `validator` de cada
  field. Patrón estándar en `sale_form_screen.dart`, `worker_form_screen.dart`.
- `AutovalidateMode.onUserInteraction` — feedback en vivo después del
  primer intento de submit.

## Estilo de UI

- **Material 3** (`useMaterial3: true` en `AppTheme`).
- **`FilledButton` / `FilledButton.icon`** para acción primaria.
- **`OutlinedButton.icon`** para acciones secundarias destructivas
  (anular, eliminar).
- **`TextButton`** para acciones de baja prioridad.
- **`Card`** para agrupar contenido relacionado.
- **`HeroBanner`** para el encabezado de cada home screen / detalle.
- **`KpiCard` + `KpiRow`** para métricas.
- **`RangeFilterBar`** para filtros de fecha en dashboards.
- **`SkeletonList`** para loading states de listas.
- **`EmptyState`** cuando no hay data.

## Iconografía

- **Material Icons outlined** por default (`Icons.x_outlined`). Algunos
  pocos están como filled cuando hace sentido visual (ej. `Icons.tag`,
  `Icons.warning`).
- **NUNCA `Icons.merge_type` ni `Icons.merge`** — tree-shake los come en
  web. Usá `Icons.call_merge`.
- Antes de agregar un icono nuevo, verificá que renderice en web
  release haciendo `flutter build web --release` y probando.

## Theming

- Usar siempre `Theme.of(context).colorScheme.primary` etc, no
  `AppColors.X` directo en widgets. La paleta solo se referencia
  directamente en `app_theme.dart` y en paletas de gráficos
  (`AppColors.chartPaletteFor(brightness)`).

## Formato de moneda y fechas

- **`formatCop(num)`** de `core/utils/money.dart` — siempre. Devuelve
  `$ 1.234.567` con punto como miles, sin decimales (es la convención COP).
- **`formatDate(DateTime)`** y **`formatDateTime`** de `core/utils/dates.dart`
  para fechas legibles.
- **`DateFormat('d MMM', 'es_CO')`** para fechas cortas en charts.

## Trabajo con Firestore

- **Lectura**: a través del repositorio de la feature. Devolvé streams
  o futures de modelos, no `QuerySnapshot` crudos.
- **Escritura**:
  - Documentos individuales: `doc.set(map)` / `doc.update(patch)`.
  - Lotes (renombre, fusión): `_firestore.batch()` con chunks de **≤400**
    (límite Firestore es 500, dejamos margen).
  - Contadores: `_firestore.runTransaction` — único caso donde una
    operación necesita atomicidad estricta. Ver `SalesRepository.createSale`.
- **Timestamps**: siempre usá `AppClock.now()` y
  `Timestamp.fromDate(AppClock.toInstant(date))`. Centraliza el clock
  para que tests puedan fakearlo (no lo hacen aún, pero la API existe).

## Reglas de Firestore

- Cualquier cambio que afecte permisos requiere actualizar
  `firestore.rules` Y deployarlo:
  ```
  firebase deploy --only firestore:rules
  ```
- **Patrón**: helpers `isSignedIn()`, `isAdmin()`, `isSales()`,
  `isHours()`, `isAuditor()`, `userDoc()`, `role()`, `isActive()`.
- Si agregás un rol nuevo, sumá el helper + actualizá cada `match`
  relevante. Ver `docs/workflows.md` → "Agregar un rol nuevo".

## Tests

- **Solo para motores puros** sin dependencias de Firebase/Flutter:
  - `test/colombian_holidays_test.dart`
  - `test/hours_calculator_test.dart`
- **No agregues tests de widgets ni de integración** salvo pedido
  explícito — el costo/beneficio no compensa para una app interna de
  este tamaño. Validación es manual.

## Performance

- **ListenableBuilder** para subscribirte a controllers sin re-buildear
  toda la pantalla. Patrón en `sale_form_screen.dart > _TotalCard` y
  `_MixedAmountsRow`.
- **`select`** en Riverpod cuando solo te importa una parte del state:
  ```dart
  ref.watch(currentProfileProvider.select((a) => a.valueOrNull?.role));
  ```
- **Evitá `setState` global** cuando podés escuchar un controller
  específico.

## Web-specific gotchas

- **No imports directos de `dart:io`** desde código compartido.
- **No paquetes que no tengan soporte web** (`open_filex`, `dio` con
  features nativas, etc.) sin gatear con conditional imports.
- **`persistenceEnabled: true` de Firestore solo en `!kIsWeb`**.
- **Tree-shake de iconos** en release rompe iconos referenciados
  indirectamente. Si usás un icono nuevo y no aparece en web, probá
  `--no-tree-shake-icons` o cambiá a un icono más común.

## Commits

- Mensaje en imperativo, una línea de título corta (~60 chars), cuerpo
  opcional explicando el WHY:
  ```
  Pago dividido: efectivo + transferencia con destino configurable

  Una venta ahora puede pagarse 100% efectivo, 100% transferencia, o
  parte de cada uno. Tres campos nuevos en el modelo Sale...
  ```
- Un commit = un cambio coherente. Si tocaste 3 cosas no relacionadas,
  3 commits.
- **No incluyas `Co-authored-by: Claude` ni mensajes de tooling** salvo
  pedido explícito.
