# Debugging — Síntomas conocidos

Cosas que pasaron y cómo se diagnosticaron. Si encontrás un bug nuevo
y lo arreglás, sumalo acá para que la próxima vez sea más rápido.

---

## Síntoma: app web se queda cargando, nunca llega a login

**Diagnóstico paso a paso:**

1. Abrí DevTools (`F12`) → tab Console. Buscá errores en rojo.
2. **Si ves `Uncaught Error at main.dart.js:NNNN`** y nada legible:
   El bundle es minificado. Para ver el error real, ejecutá local:
   ```
   flutter run -d chrome
   ```
   Ahí verás `errors.dart:NN Uncaught Error: <mensaje legible>`.
3. **Errores comunes y sus causas:**

   - `Unsupported operation: DefaultFirebaseOptions have not been
     configured for web` → falta el bloque `web` en `firebase_options.dart`.
     Fix: `flutterfire configure --project=quality-group-app` y marcá web.
   - `firebase_persistence` / IndexedDB errors → `persistenceEnabled: true`
     está activo en web. Verificá `main.dart` que esté gateado con `!kIsWeb`.
   - `cannot find module 'package:xxx'` → algún plugin no soporta web
     o no se compiló su versión web. Probablemente lo importaste sin
     conditional import.

4. **Si Console está limpia pero el splash no se va:** problema de
   service worker / cache:
   - `Ctrl+Shift+R` para hard refresh.
   - Si no, DevTools → Application → Service Workers → Unregister.
   - Si no, Application → Storage → Clear site data.

5. **Si tampoco eso funciona y es en incógnito:** bug real del bundle.
   Build local con source maps y mandá el stack:
   ```
   flutter run -d chrome
   ```

---

## Síntoma: ícono no aparece en web release

Tree-shaking de iconos en `flutter build web --release` se come iconos
referenciados indirectamente (vía `IconData icon` parámetro, etc.).

**Fix rápido:** cambiá el icono a uno más universal. Probados que
siempre renderean: `Icons.edit_outlined`, `Icons.delete_outline`,
`Icons.add`, `Icons.check`, `Icons.call_merge`, `Icons.close`,
`Icons.menu`, `Icons.arrow_back`.

**Fix definitivo** si necesitás iconos específicos:
```
flutter build web --release --no-tree-shake-icons
```

Penalty: ~150 KB extra para empaquetar todo el font.

---

## Síntoma: cambio de master list no se refleja en sales viejas

Caso: admin renombró un cliente en la lista maestra pero las ventas
viejas siguen mostrando el nombre viejo.

**Causa:** se usó `updateItem` en lugar de `renameItem`.

`updateItem` solo toca el catálogo. `renameItem` también hace batch
update de todas las sales con el value viejo.

**Fix:** desde la UI del admin, abrir el item con el lápiz ✏️ y editar
ahí (el botón usa `renameItem`). Si la UI no llama el correcto, revisar
`master_list_detail_screen.dart`.

---

## Síntoma: dropdown vacío, no deja escribir ni seleccionar

Causa: la metadata del list (`master_lists/{listId}`) no existe en
Firestore todavía. El admin no abrió "Listas maestras" para disparar
`seedDefaults` después de un cambio que agregó listas nuevas.

**Fix temporal:** ya implementamos un fallback — el `MasterListField`
ahora defaultea a `allowFreeText: true` cuando la meta no existe. El
usuario puede tipear y queda como sugerencia.

**Fix definitivo:** login como admin → abrir "Listas maestras". Eso
seedea las listas nuevas.

Si el admin **ya** abrió las listas en esta sesión (`_didSeed=true`
flag), hay que cerrar sesión / recargar para que vuelva a intentar.

---

## Síntoma: `permission-denied` al hacer login o cambiar de usuario

Posibles causas:

1. **El usuario no existe en Firestore `users/{uid}`** aunque sí esté
   en Firebase Auth. La app necesita el doc para resolver el rol.
   Fix: crear el doc manualmente o desde admin panel.
2. **`active: false`** en el users doc. Cambialo.
3. **Token stale** después de un signOut + signIn rápido. Solo afecta
   por unos ms. Si persiste, hard refresh.
4. **Rules deploy pendiente**: si acabás de modificar `firestore.rules`,
   esperá ~30s a 1min antes de probar.
5. **Rebind de providers**: si un `StreamProvider` no llama a
   `ref.watch(authStateProvider)`, el listener queda con el token
   anterior. Fix: agregalo (ver `docs/architecture.md`).

---

## Síntoma: `Listen for Query(...) failed: PERMISSION_DENIED` en logs

Si pasa **brevemente al arrancar** y luego se autocura: es la ventana
entre que FirebaseAuth restaura la sesión cacheada. Cosmético.

Si pasa **persistentemente**: el usuario logueado no tiene permiso para
esa query según `firestore.rules`. Revisar el rol del user vs lo que
permite la regla.

---

## Síntoma: chart con eje X todo solapado

Causa: estás usando `BarChart` con muchas barras. Fl_chart no respeta
el `interval` de `SideTitles` en bar charts — invoca el callback para
cada bar group y los labels se pisan.

**Fix:** usar `LineChart` (respeta interval). Ver
`admin_metrics_screen.dart > _SalesLineChart` y
`auditor_dashboard_screen.dart > _DailyTrendCard` para el patrón.

Si necesitás bar chart por requisito de diseño:
- En `getTitlesWidget`, retorná `SizedBox.shrink()` cuando `i %
  intervalInt != 0`.
- O reduce el número de bars (ej. agregando por semana en lugar de día).

---

## Síntoma: APK no instala — "App not installed"

Casos:

1. **Conflicto de firma**: el APK está firmado con un keystore
   distinto al instalado. Solución: desinstalar la versión vieja
   primero (solo aplica si cambió el keystore — pasa una sola vez).
2. **versionCode menor o igual**: bumpeá el `+N` en `pubspec.yaml`.
3. **APK corrupto / parcial**: re-descargar.
4. **ARM mismatch**: el usuario tiene un emulador x86 y le pasaste
   `app-arm64-v8a-release.apk`. Mandale el universal o el x86 correspondiente.

---

## Síntoma: cambios en firestore.rules no aplican

Después de `firebase deploy --only firestore:rules`:

1. Esperar 30s–1min para propagación.
2. La consola muestra "+ rules released" si el deploy funcionó.
3. Si los users ya tenían la app abierta, sus tokens siguen viejos
   hasta el siguiente token refresh (~1h). Para forzar: signOut + signIn.

---

## Síntoma: `flutter pub get` se queda colgado o falla

1. `flutter clean` para limpiar `.dart_tool/`.
2. `flutter pub get` otra vez.
3. Si persiste: revisar `pubspec.yaml` por dependencias incompatibles
   (versiones que no resuelven).
4. Si es problema de red: `dart pub cache clean` y reintentar.

---

## Síntoma: `flutter build web --release` falla con `Couldn't resolve package 'xxx'`

Causa: hay un `web_plugin_registrant.dart` stale (autogenerado) que
referencia un paquete que ya no está en `pubspec.yaml`.

**Fix:**
```
flutter clean
flutter pub get
flutter build web --release
```

`flutter clean` regenera el registrant desde el pubspec actual.

---

## Síntoma: `wasm dry run failure` durante `flutter build web`

Solo es un warning (no bloquea). Para silenciarlo:

```
flutter build web --release --no-wasm-dry-run
```

---

## Síntoma: emulador Android escupe miles de `GoogleApiManager DEVELOPER_ERROR`

Ruido del emulador (Play Services no termina de configurar
`ProviderInstaller` / `Phenotype`). No afecta la app, no aparece en
celulares reales. Ignorar.

---

## Síntoma: SegmentedButton corta el texto en pantallas estrechas

Texto largo + ícono = overflow en mobile angosto. Solución:

- Quitar `icon:` del `ButtonSegment`.
- O acortar el label.
- O usar 2 segments en lugar de 3.

Ver el ejemplo en `sale_form_screen.dart > _PaymentSection`.

---

## Si el síntoma no está acá

1. Reproducí en debug (`flutter run`), no en release.
2. Mirá DevTools → Console y Network.
3. Buscá el primer error real, ignorá el ruido.
4. Identificá el archivo y línea (con source maps en debug, son legibles).
5. Si es persistente y reproducible, **sumalo a este doc** después de
   arreglarlo.
