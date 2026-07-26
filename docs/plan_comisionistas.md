# Plan — Comisionistas (campo en la venta + lista maestra + tracking)

Estado: **pendiente, no iniciado** (escrito 2026-07-26).
Rama de trabajo: `claude/check-system-status-FP9g9`.

---

## 0. Qué se pidió (en palabras del solicitante)

> "Quiero saber quién vende más. Si se vende más en la bodega, se vende
> más por comisionistas, qué comisionista vende más. Porque así puedo
> manejarle precios diferentes a cada comisionista."

Tres entregables concretos:
1. **Campo opcional** de comisionista en la venta.
2. **Lista maestra** de comisionistas con **control total del admin**.
3. **Sección de tracking**: cuánto vende cada comisionista, ordenado.

**NO se pidió (out of scope, no implementar):** login/rol de
comisionista, % de comisión, cálculo de comisión, datos bancarios del
agente. Si algún día se necesitan, son fases futuras independientes.

---

## 1. Principios rectores

- **Puramente aditivo.** No se modifica ni se elimina ningún campo,
  método, query o comportamiento existente. Todo lo nuevo es opcional y
  nullable. Ventas históricas quedan intactas (campo ausente → "Bodega").
- **Cero cambios de reglas Firestore.** Agregar un campo a `sales` y una
  lista maestra ya están cubiertos por `match /sales` y
  `match /master_lists`. **No se toca `firestore.rules`.**
- **Lista estricta (`allowFreeText: false`).** El comisionista se **elige**
  de una lista que solo el admin gestiona. Sin captura libre → sin
  "Juan"/"juan"/"Juan P." como agentes distintos → tracking limpio. Esto
  ES "control total del admin".
- **Vacío = Bodega.** Una venta sin comisionista se considera venta
  directa/de bodega. En el tracking se agrupa bajo un bucket **"Bodega"**.
- **Espejar patrones existentes.** El campo replica `payerName`
  ("Quién recibe"); el tracking replica `PayersBreakdownScreen`. No se
  inventan patrones nuevos.

---

## 2. Modelo de datos

### 2.1 Campo nuevo en `sales/{id}`

| Campo             | Tipo    | Notas                                             |
|-------------------|---------|---------------------------------------------------|
| `commissionAgent` | String? | Comisionista que trajo la venta. Null/ausente = venta de bodega (directa). De la lista maestra `commission_agents`. |

- Backwards-compat: ventas sin el campo → `null` en el modelo → "Bodega"
  en el tracking. **Sin migración.**
- No es mirror de nada, no entra en `items[]`, no afecta agregados
  financieros.

### 2.2 Lista maestra nueva `commission_agents`

| listId              | Display name    | Free text | Items seed |
|---------------------|-----------------|-----------|------------|
| `commission_agents` | Comisionistas   | **no**    | `[]` (vacía; el admin la llena) |

- `allowFreeText: false` → dropdown estricto vía `MasterListField`.
- Referenciada por valor desde `sales.commissionAgent` → entra al mapa de
  propagación para que renombrar un comisionista actualice sus ventas
  históricas (igual que `payers`/`providers`).

---

## 3. Plan por fases

Dos fases, cada una con commit propio + `flutter analyze` 0 errores.
**STOP tras cada fase para feedback.**

---

### Fase 1 — Campo en la venta + lista maestra

**Objetivo:** el vendedor puede elegir (opcionalmente) un comisionista al
crear/editar una venta; el admin gestiona la lista. Sin tracking todavía.

Sigue la receta `docs/workflows.md` §1 ("Agregar un campo a Sale") +
§2 ("Agregar una lista maestra").

#### Archivos a tocar

1. **`lib/features/sales/domain/sale.dart`**
   - Constructor: `this.commissionAgent` (nullable, opcional).
   - Field: `final String? commissionAgent;`
   - `toMap()`: `'commissionAgent': commissionAgent,`
   - `fromSnapshot()`: `commissionAgent: data['commissionAgent'] as String?,`
   - **No** tocar mirrors, items, ni agregados.

2. **`lib/features/sales/data/sales_repository.dart`**
   - `createSale(...)`: sumar `String? commissionAgent,` a la firma y
     pasarlo al `Sale(...)`.
   - `updateSale(...)`: sumar `String? commissionAgent,` +
     `bool clearCommissionAgent = false,` (patrón `clearCashAmount`), y al
     `basePatch`:
     ```dart
     if (clearCommissionAgent) 'commissionAgent': null
     else if (commissionAgent != null) 'commissionAgent': commissionAgent,
     ```

3. **`lib/features/sales/presentation/sale_form_screen.dart`**
   - State: `String? _commissionAgent;`
   - `initState`: `_commissionAgent = s?.commissionAgent;`
   - Widget (después del bloque de cliente, antes de items): un
     `MasterListField(listId: 'commission_agents', label: 'Comisionista
     (opcional)', initialValue: _commissionAgent, required: false,
     onChanged: (v) => setState(() => _commissionAgent = v))`.
   - `_submit`: pasar `commissionAgent: _commissionAgent` a
     `createSale`; en `updateSale` pasar `commissionAgent` +
     `clearCommissionAgent: _commissionAgent == null` para permitir
     quitarlo. (Verificar que en la venta creada por sales el campo viaje
     junto a los demás — no depende de delegación.)

4. **`lib/features/admin/data/master_lists_repository.dart`**
   - `_defaultListsSeed()`: nueva entrada
     ```dart
     {
       'id': 'commission_agents',
       'name': 'Comisionistas',
       'allowFreeText': false,
       'description':
           'Personas que traen ventas por comisión. Solo el admin '
           'gestiona esta lista; el vendedor elige de aquí.',
       'items': <String>[],
     },
     ```
   - `_propagationByListId`: nueva entrada
     ```dart
     'commission_agents': ListPropagation(
       primary: ListTarget(collection: 'sales', field: 'commissionAgent'),
     ),
     ```

5. **`lib/features/sales/presentation/sale_detail_screen.dart`**
   - En el card principal, tras "Quién recibe":
     ```dart
     if (sale.commissionAgent != null &&
         sale.commissionAgent!.isNotEmpty)
       _Row(label: 'Comisionista', value: sale.commissionAgent!),
     ```

6. **`lib/shared/services/xlsx_export_service.dart`**
   - `exportSales`: sumar `'Comisionista'` a `headers`, su ancho a la
     lista de anchos, y `TextCellValue(s.commissionAgent ?? 'Bodega')`
     a la fila. **Cuidar que header, ancho y celda queden alineados en
     índice** (es la fuente de bugs más común de este archivo).

7. **`docs/data-model.md`**
   - Tabla `sales/{id}`: fila `commissionAgent`.
   - Tabla de listas maestras: fila `commission_agents`.
   - Sección "Mapping listId → campo": fila `commission_agents → commissionAgent`.
   - Bloque de relaciones: `sales.commissionAgent (listId = commission_agents)`.

#### Validación Fase 1
- [ ] `flutter analyze` 0 errores.
- [ ] `flutter test` (motores puros) sigue verde.
- [ ] Smoke web (`flutter run -d chrome` o build+deploy si hace falta login):
  - Admin abre "Listas maestras" → aparece "Comisionistas" (seed disparado).
    Agrega 2-3 agentes.
  - Crear venta SIN comisionista → guarda ok, detalle no muestra la fila.
  - Crear venta CON comisionista (elegido del dropdown) → detalle muestra
    "Comisionista: X". En Firestore el doc tiene `commissionAgent: "X"`.
  - Editar una venta: cambiar y quitar el comisionista → persiste.
  - Ventas viejas (sin el campo) → abren sin romper, sin fila comisionista.
  - Export xlsx → columna "Comisionista" con el valor o "Bodega".
  - **Regresión:** crear/editar venta normal, flujo de caja, delegación,
    autocompletado de cédula — todo igual que antes.

#### Commit
```
git add lib/features/sales/ lib/features/admin/data/master_lists_repository.dart lib/shared/services/xlsx_export_service.dart docs/data-model.md
git commit -m "Comisionistas — Fase 1: campo opcional en venta + lista maestra estricta"
```
**STOP.**

---

### Fase 2 — Tracking (breakdown por comisionista en el admin)

**Objetivo:** el admin ve cuánto vende cada comisionista (y la bodega),
ordenado. Espeja `PayersBreakdownScreen`.

#### Decisión de métrica
- **Base del ranking:** `paidAmount` (dinero cobrado), consistente con el
  resto de `SalesMetrics` (total, byPayer, etc. ya usan paidAmount). Así
  "quién vende más" = quién generó más plata cobrada. Mismos criterios que
  el breakdown de payers → cero sorpresas.
- **Bucket "Bodega":** ventas con `commissionAgent` null/vacío suman a una
  clave fija `'Bodega'`. Se muestra en el ranking como una fila más
  (típicamente la más grande), que es justo lo que el solicitante quiere
  ver ("si se vende más en la bodega o por comisionistas").

#### Archivos a tocar

1. **`lib/features/admin/data/metrics.dart`**
   - `SalesMetrics`: nuevo campo `final Map<String, num> byCommissionAgent;`
     (+ en constructor y en `empty()`).
   - En `SalesMetrics.compute`, dentro del loop `for (final s in sales)`
     que ya existe (mismo lugar donde vive el filtro `procesada`), sumar:
     ```dart
     // Ranking por comisionista sobre dinero cobrado. Vacío = Bodega
     // (venta directa). Solo procesadas, igual que byMaterial/count.
     if (s.state == SaleState.procesada) {
       final agent = (s.commissionAgent?.trim().isNotEmpty ?? false)
           ? s.commissionAgent!.trim()
           : 'Bodega';
       byCommissionAgent.update(agent, (v) => v + s.paidAmount,
           ifAbsent: () => s.paidAmount);
     }
     ```
     (Declarar `final byCommissionAgent = <String, num>{};` arriba con los
     otros acumuladores, y pasarlo al `return SalesMetrics(...)`.)
   - **No** tocar los cálculos existentes — solo se agrega uno nuevo.

2. **Crear** `lib/features/admin/presentation/commission_agents_breakdown_screen.dart`
   - Copia estructural de `payers_breakdown_screen.dart`:
     - `RangeFilterBar`, KPIs (# comisionistas, top comisionista, total),
       lista con barras y % del total.
     - Lee `metrics.byCommissionAgent`.
     - Título: "Análisis por comisionista".
     - EmptyState adaptado.
   - Detalle UX: separar visualmente la fila "Bodega" (es un bucket, no un
     agente) — ej. contar "# comisionistas" excluyendo "Bodega", y en el
     KPI "top comisionista" tomar el mayor que **no** sea Bodega. La barra
     de Bodega igual se muestra en la distribución para comparar.

3. **`lib/features/admin/presentation/admin_metrics_screen.dart`**
   - Nueva `KpiCard`/tile "Por comisionista" (espejo del de "Por quién
     recibe", líneas ~307-317) con
     `onTap: () => context.push('/admin/metrics/commission-agents')`.

4. **`lib/core/routing/app_router.dart`**
   - Bajo el `ShellRoute` admin, junto a `metrics/payers`:
     ```dart
     GoRoute(
       path: 'metrics/commission-agents',
       builder: (_, __) => const CommissionAgentsBreakdownScreen(),
     ),
     ```
   - Importar la pantalla.

5. **`docs/workflows.md`** (opcional pero recomendado)
   - Nota en §5 ("Agregar una métrica nueva al dashboard") de que el
     breakdown por comisionista sigue este patrón, o dejar el CHANGELOG.

#### Validación Fase 2
- [ ] `flutter analyze` 0 errores.
- [ ] Con las ventas de prueba de Fase 1 (algunas con agente, algunas sin):
  - Dashboard admin muestra la card "Por comisionista".
  - Tap → breakdown lista cada agente + "Bodega", ordenado desc por monto.
  - KPIs coherentes (# agentes sin contar Bodega, top real, total).
  - Cambiar el rango recalcula.
  - **Regresión:** los KPIs y breakdowns existentes (payers, materials,
    clients, total) siguen dando exactamente lo mismo que antes.

#### Commit
```
git add lib/features/admin/ lib/core/routing/app_router.dart docs/
git commit -m "Comisionistas — Fase 2: breakdown de ventas por comisionista (con bucket Bodega)"
```

---

## 4. Verificación de reproducción (end-to-end)

Como el login local está bloqueado por el referer de Firebase (memoria
conocida), la reproducción real la hace el usuario en web desplegada o en
device. Guion de smoke mínimo tras Fase 2:
1. Admin crea 3 comisionistas en la lista maestra.
2. Vendedor crea 4 ventas: 2 con agente A, 1 con agente B, 1 sin agente.
3. Admin → dashboard → "Por comisionista": A primero, luego B, luego
   Bodega (según montos). Números cuadran con las ventas.
4. Renombrar el agente A en la lista maestra → sus 2 ventas y el
   breakdown reflejan el nombre nuevo (propagación).
5. Export xlsx: columna Comisionista correcta, "Bodega" donde va vacío.

---

## 5. Release
- Bump `pubspec.yaml` a `1.5.0+17` (feature nueva user-facing → minor).
- `CHANGELOG.md`: entrada "Agregado — comisionistas: campo opcional en la
  venta, lista maestra gestionada por el admin y análisis de ventas por
  comisionista (con bodega como venta directa)".
- Build web + deploy hosting (con OK del usuario) + APK split-per-abi.

---

## 6. Riesgos y mitigación
| Riesgo | Mitigación |
|---|---|
| Romper el alineado header/celda del xlsx | Revisar índice por índice; probar el export tras el cambio. |
| Olvidar la propagación al renombrar | Entrada en `_propagationByListId` + test manual de rename. |
| El campo no viaja en la venta creada por sales bajo delegación | `commissionAgent` es independiente del bloque de pago; se pasa siempre a `createSale`. Verificar en smoke. |
| Doble conteo o cambio en métricas existentes | El nuevo cálculo es un acumulador aparte; no se toca ningún cálculo previo. Regresión explícita en validación. |
| Lista libre ensucia el tracking | `allowFreeText: false` (decisión tomada). |
