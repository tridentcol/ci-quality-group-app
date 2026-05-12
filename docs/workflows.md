# Playbooks — Cómo hacer cambios comunes

Recetas paso a paso. Si vas a hacer algo de esta lista, seguila al pie
de la letra. Si tu cambio no está acá pero lo querés agregar al canon,
sumalo después de hacerlo.

---

## 1. Agregar un campo nuevo al modelo `Sale`

Caso: el admin quiere capturar un dato adicional en cada venta (ej.
"orden de compra del cliente").

**Si es solo opcional para algunas ventas:** considerá usar custom
fields del form builder en lugar de agregarlo al modelo core. El admin
los agrega/quita desde `/admin/form-builder` sin tocar código.

**Si es un campo core (siempre presente):**

1. **`lib/features/sales/domain/sale.dart`**:
   - Agregalo al constructor con `required` o como nullable.
   - Agregá el final field con su tipo.
   - Sumalo a `toMap()`.
   - Sumalo a `fromSnapshot()` con el cast correcto. Para ventas viejas
     que no lo tienen, definí default sensato (`?? defaultValue`).
2. **`lib/features/sales/data/sales_repository.dart`**:
   - Agregalo a la signatura de `createSale(...)`.
   - Agregalo a `updateSale(...)`. Si es nullable y querés permitir
     "limpiar", sumá un flag `clearXxx: bool = false` (patrón de
     `clearCashAmount` etc.).
   - Pasalo al `Sale(...)` que se construye en `createSale`.
3. **`lib/features/form_builder/domain/form_schema.dart`**:
   - Sumalo al default schema con un `FieldDefinition(id: 'xxx', label: 'Xxx', coreField: true, ...)`.
4. **`lib/features/sales/presentation/sale_form_screen.dart`**:
   - Sumá state field (`String? _xxx`).
   - Init desde `editingSale` en `initState`.
   - Recoge en `_submit` y pasalo al `createSale`/`updateSale`.
   - Agregá un `case 'xxx':` en `_buildCoreField` que devuelva el widget
     correspondiente (`TextFormField`, `DropdownButtonFormField`,
     `MasterListField` si es de una lista maestra, etc.).
5. **`lib/features/sales/presentation/sale_detail_screen.dart`**:
   - Sumá un `_Row(label: ..., value: ...)` en el card principal donde
     corresponda.
6. **`lib/shared/services/xlsx_export_service.dart`**:
   - Sumá la columna al header + width + valor en la fila.
7. **`docs/data-model.md`**:
   - Documentá el campo en la tabla de `sales/{id}`.
8. **Validar:**
   - `flutter analyze`
   - Correr en emulador / chrome
   - Crear una venta nueva y editarla.
   - Verificar que ventas viejas siguen funcionando (backwards-compat).

---

## 2. Agregar una lista maestra nueva

Caso: el admin necesita un nuevo dropdown gestionable (ej. "tipos de
empaque").

1. **`lib/features/admin/data/master_lists_repository.dart`**:
   - Sumá al array de `_defaultListsSeed()`:
     ```dart
     {
       'id': 'package_types',
       'name': 'Tipos de empaque',
       'allowFreeText': true,
       'description': 'Cómo viene empaquetado el material recibido.',
       'items': <String>['Granel', 'Caja', 'Bolsa', 'Paleta'],
     },
     ```
   - Si la lista se referencia desde `sales`, sumala a `_saleFieldByListId`:
     ```dart
     'package_types': 'packageType',
     ```
2. **`docs/data-model.md`**: agregala a la tabla de listas maestras existentes.
3. **El field en sale form**: ver receta 1 paso 4 (case en `_buildCoreField`
   con `MasterListField(listId: 'package_types', ...)`).
4. **Validar:**
   - Login como admin → abrir "Listas maestras". Eso dispara `seedDefaults`
     y crea la lista nueva.
   - Si el admin ya había abierto el panel antes (en la misma sesión),
     el `_didSeed` flag salta. Hacé logout/login.
5. **Reglas de Firestore**: no requiere cambios — `master_lists/{listId}`
   y `items/{itemId}` ya cubren cualquier lista nueva.

---

## 3. Agregar un rol nuevo

Caso: necesitás un rol intermedio (ej. "supervisor" que ve sales pero no las edita).

1. **`lib/core/constants/roles.dart`**:
   - Sumá al enum `AppRole`: `supervisor`.
   - Sumá al `label`, `id`, `fromString`.
2. **`firestore.rules`**:
   - Sumá helper `isSupervisor()`.
   - Actualizá cada `match` con la nueva regla de acceso.
   - **Deployalo: `firebase deploy --only firestore:rules`** antes de
     probar nada.
3. **`lib/core/routing/app_router.dart`**:
   - Sumá al `switch (user.role)` para definir su home.
   - Sumá al check de acceso por ruta.
4. **`lib/shared/widgets/role_pill.dart`**:
   - Sumá un color al `_colorFor` switch.
5. **`lib/features/admin/presentation/user_form_screen.dart`**:
   - El dropdown de rol lo genera automáticamente con `AppRole.values`,
     así que aparece sin código extra.
6. **Pantalla home**: creá `lib/features/<feature>/presentation/<role>_home_screen.dart`
   y agregá el `GoRoute` correspondiente.
7. **Validar:**
   - Crear un usuario con ese rol → login → verifica redirect, acceso,
     UI correcta.

---

## 4. Agregar un campo filtrable para el rol auditor

Caso: querés que un auditor pueda filtrar por algo nuevo (ej. por unidad).

1. **`lib/features/admin/presentation/user_form_screen.dart`**:
   - Sumá el campo a `_AuditorFilterCard._fieldOptions`.
   - Sumá al switch de `_listIdForField` y `_labelForField`.
2. **`lib/features/auth/domain/app_user.dart`**:
   - Sumá al switch de `AuditFilter.fieldLabel`.
3. **`lib/features/sales/data/sales_repository.dart`**:
   - `watchByField` ya es genérico, no requiere cambios.
4. **Firestore**: si el campo no estaba indexado, Firestore te va a
   pedir un índice compuesto la primera vez. El log de la consola te
   da link directo para crearlo.

---

## 5. Agregar una métrica nueva al dashboard del admin

Caso: querés mostrar "ventas con pago mixto" como KPI separado.

1. **`lib/features/admin/data/metrics.dart`**:
   - Sumá un campo al class `SalesMetrics` (`final int mixedPaymentCount`).
   - Calculalo en `SalesMetrics.compute`.
   - Sumalo a `SalesMetrics.empty()`.
2. **`lib/features/admin/presentation/admin_metrics_screen.dart`**:
   - Sumá el KPI a la `KpiRow` correspondiente:
     ```dart
     KpiCard(
       label: 'Ventas con pago mixto',
       value: '${metrics.mixedPaymentCount}',
       icon: Icons.call_split_outlined,
     ),
     ```
3. **Si querés tap-to-expand a un breakdown**:
   - Creá `mixed_payments_breakdown_screen.dart` en `features/admin/presentation/`.
   - Agregá el `GoRoute` debajo del `ShellRoute` de admin.
   - Envolvé el KPI en un `InkWell` con `onTap: () => context.push('/admin/metrics/...')`.

---

## 6. Agregar un export xlsx nuevo

Caso: querés un reporte distinto (ej. ventas por cliente con totales).

Opción A — agregar columnas al export existente: editá
`xlsx_export_service.dart > exportSales`.

Opción B — export nuevo:

1. Sumá `static Future<void> exportXxxx(...)` en `XlsxExportService`.
2. Reusá `_stylizeHeader`, `_applyColumnWidths` para consistencia visual.
3. Llamá a `deliver.deliverFiles(...)` con el bytes resultante.
4. Conectalo desde donde corresponda en la UI (típicamente desde
   `admin_metrics_screen.dart` con un `IconButton` o `PopupMenuButton`).

---

## 7. Cambiar la jornada laboral default

Caso: la empresa cambia los horarios.

- **Si es un cambio del default que aplica a instalaciones nuevas:**
  - Editá `lib/features/hours/data/work_schedule_repository.dart` →
    `_defaultSchedule()`.
- **Si es un cambio para esta empresa específica:**
  - Login como admin → `/admin/settings/schedule` → cambiá los valores ahí.
  - Esto persiste en `settings/work_schedule` y el motor de horas lo lee.

---

## 8. Migrar el schema de una colección

Caso: cambiás cómo se guarda un campo y necesitás actualizar docs existentes.

**Riesgo**: este tipo de cambio es destructivo si se hace mal.
**Confirmá con el usuario antes** de correr cualquier migración.

Patrón seguro:

1. **Backwards-compat primero**: hacé que el modelo lea AMBAS formas
   (campo viejo y nuevo) con un getter de derivación. Deploy. Verificá.
2. **Migrar en cliente o con Cloud Function**: para volúmenes pequeños
   (<10K docs), un script que corre desde admin panel:
   ```dart
   // Pseudo
   final snap = await firestore.collection('sales').get();
   for (final doc in snap.docs) {
     final data = doc.data();
     if (data['campo_nuevo'] == null && data['campo_viejo'] != null) {
       await doc.reference.update({'campo_nuevo': transform(data['campo_viejo'])});
     }
   }
   ```
   Hacé batches de 400. Probá primero en una colección de staging.
3. **Eliminar el campo viejo**: solo después de verificar que toda la
   data está migrada. **No** lo borres del modelo Dart en el mismo
   deploy que la migración — esperá uno más para tener fallback.

---

## 9. Agregar un test (solo motores)

Solo para `core/utils/*` puro o motores como `hours_calculator.dart` y
`colombian_holidays.dart`.

```dart
// test/mi_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ci_quality_group/features/hours/domain/hours_calculator.dart';

void main() {
  test('Un caso descriptivo', () {
    final result = HoursCalculator.compute(...);
    expect(result.ordinary, equals(Duration(hours: 8)));
  });
}
```

Correr con `flutter test`.

---

## 10. Workflow de release

Receta para liberar una versión nueva (APK + web):

1. **Cambios en código** → commit + push.
2. **Bumpear `pubspec.yaml`**: `version: X.Y.Z+N` (subí ambos).
3. **Actualizar `CHANGELOG.md`** agregando arriba un nuevo bloque
   `## [X.Y.Z+N] — YYYY-MM-DD` con secciones Agregado / Cambiado /
   Corregido / Eliminado según corresponda.
4. **Commit:**
   ```
   git add pubspec.yaml CHANGELOG.md
   git commit -m "Bump versión X.Y.Z+N + changelog"
   git push origin claude/check-system-status-FP9g9
   ```
5. **Tag opcional:**
   ```
   git tag -a vX.Y.Z -m "Release X.Y.Z+N — descripción corta"
   git push origin vX.Y.Z
   ```
6. **Build APK:**
   ```
   flutter build apk --release --split-per-abi
   ```
   El APK queda en `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
7. **Distribuir APK** por WhatsApp/Drive al equipo. **Avisarles que no
   tienen que desinstalar** (mismo keystore).
8. **Deploy web** (si aplica):
   ```
   flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
   firebase deploy --only hosting
   ```
9. **Verificar** en `https://quality-group-app.web.app` que el deploy
   levantó (hard refresh).

---

## 11. Eliminar un feature

Caso: hay que sacar algo (ej. el in-app updater que sacamos en 1.0.2).

1. **Identificar todos los archivos** del feature:
   ```bash
   find lib -path 'lib/features/<feature_name>*'
   ```
2. **Identificar referencias externas** al feature:
   ```bash
   grep -rn "FeatureName\|feature_provider\|FeatureScreen" lib/
   ```
3. **Remover referencias UNA POR UNA**:
   - Imports en otros archivos.
   - Rutas en `app_router.dart`.
   - Llamados en otras pantallas.
4. **Borrar el directorio del feature**.
5. **Quitar dependencias del `pubspec.yaml`** que solo usaba el feature.
6. **Quitar reglas de Firestore** específicas si las tenía
   (`firestore.rules`).
7. **`flutter clean && flutter pub get`** — limpia caché de plugins.
8. **`flutter analyze`** — debe pasar limpio.
9. **CHANGELOG.md**: documentalo en "Eliminado".

---

## 12. Debugging cuando algo se queda cargando

Ver `docs/debugging.md` → "App se queda en splash".
