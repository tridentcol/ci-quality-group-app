# Plan — Cierre de caja (ventana contigua + hora de cierre configurable)

Estado: **pendiente, no iniciado** (escrito 2026-05-31).
Rama de trabajo: `claude/check-system-status-FP9g9`.
Doc objetivo de un agente ejecutor. **Self-contained**: no necesita más
contexto que `CLAUDE.md` + este archivo + (como referencia de estilo)
`docs/plan_delegacion_caja.md`.

---

## 0. Cómo usar este plan

Cada fase es **independientemente reversible**: si rollbackeás solo esa
fase, todo lo anterior sigue funcionando. NO mergear fases. NO deployar
dos fases en el mismo push. Después de cada fase: validar → commit →
push → **STOP** y esperar feedback antes de seguir.

Si una validación falla, **parar y reportar** antes de seguir.

Si al ejecutar descubrís que algún archivo/método/widget referenciado no
existe con ese nombre exacto: `grep` primero, usar el equivalente y
notarlo en el commit; si no existe nada, parar y reportar. **Verificá
primero, ejecutá segundo.**

---

## 1. Contexto y problema

### 1.1 Situación actual (1.4.0+14)

- El dinero real vive en `sales/{id}/payments/{pid}` (`SalePayment`),
  denormalizado al padre como `paidAmount`/`outstandingBalance`/
  `financialStatus`. Cada payment tiene `cashAmount`/`transferAmount`/
  `transferDestination`/`payerName` y el flag `createdViaDelegation`.
- El cajero registra abonos (`CashierRepository.registerPayment`) y mueve
  el workflow de la venta. El admin agrega por método/payer con un
  `collectionGroup('payments')` filtrado por `registeredAt`
  (`paymentsByRangeProvider`, índice `COLLECTION_GROUP` ya existente).
- **No existe ningún concepto de "caja abierta", arqueo ni cierre.** Al
  final de la jornada el cajero no tiene forma de reconciliar lo que el
  sistema dice que entró contra lo que hay físicamente en el cajón.

### 1.2 Decisión tomada

Implementar **cierre de caja con ventana contigua y hora de cierre
configurable**:

- El cajero (o admin) **abre caja** declarando una base inicial (que viene
  precargada con el remanente del último cierre, editable).
- Durante el turno el sistema acumula el dinero esperado en vivo.
- Al **cerrar**, el cajero cuenta el efectivo físico y confirma las
  transferencias; el sistema calcula la discrepancia por método. Razón
  obligatoria si hay descuadre. Opcionalmente registra un retiro/
  consignación, y lo que queda en caja pasa como base sugerida del
  siguiente turno.
- El admin configura una **hora de cierre** (recordatorio operativo).
- Cada cierre queda persistido como documento append-only e inmutable
  para auditoría, consulta y export del admin.

### 1.3 La idea central (leer antes que nada)

Hay **dos relojes** y no hay que confundirlos:

1. **La ventana del dinero** (corrección, automática): cada cierre
   reconcilia exactamente lo que entró **desde el cierre anterior hasta
   este cierre** → `(cierreAnterior, esteCierre]`. Es **contigua**: el fin
   de una ventana es el inicio de la siguiente. **Garantía: ningún
   movimiento se pierde jamás**, sin importar a qué hora se cierre, si se
   cierra temprano, tarde, o si la jornada cruza la medianoche. Si entra
   plata después de cerrar, simplemente arranca la ventana del próximo
   cierre.

2. **La hora de cierre** (operativa, configurable): es solo un
   **recordatorio** para que el cajero sepa cuándo hacer el arqueo. NO es
   la frontera del dinero. La configura el admin. Cuando esa hora pasa y
   la caja sigue abierta, la app lo sugiere amablemente. Nada más.

Esta separación es lo que mantiene el feature simple y a prueba de errores:
la plata la cuida la ventana contigua (matemática, sin intervención); la
hora de cierre solo mejora la experiencia.

### 1.4 Decisiones de diseño explícitas (NO revisitar sin justificación)

| Decisión | Razón |
|---|---|
| **Ventana del dinero = `(cierreAnterior, esteCierre]`** (contigua, por timestamp) | Ningún movimiento se pierde. Resuelve cierre temprano, cierre tardío y jornada que cruza medianoche, sin reglas frágiles. |
| **Hora de cierre configurable = recordatorio**, no frontera | Da la ayuda operativa que el usuario pidió sin acoplar la corrección del dinero a una hora. |
| **Caja singleton global** (una abierta a la vez) | Hoy opera una sola caja física. Espeja el patrón del singleton de delegación. Sin ownership por uid. |
| **Base inicial precargada con el remanente del último cierre** (editable) | Refleja lo que quedó en el cajón. Si el cajero la corrige, esa corrección ya es señal. Primer cierre histórico: default 0. |
| **Reconcilia efectivo Y transferencias** | Ambos esperado vs contado/confirmado, cada uno con su discrepancia y razón obligatoria si descuadra. |
| **Delegación consolidada sin distinción** | Los pagos `createdViaDelegation` entran al esperado como cualquier otro. El flag queda intacto en el payment para un futuro desglose; este feature no lo usa. |
| **`businessDate` = fecha de la apertura** (etiqueta legible, editable al cerrar) | Si abrís lunes 8am y cerrás martes 1am, el cierre se rotula "lunes". La jornada que cruza medianoche queda con una etiqueta natural. La ventana del dinero NO depende de esta etiqueta. |
| **Cierre = snapshot inmutable, append-only** | Una vez cerrado, el doc no se edita ni recomputa. Si después se anula un payment de esa ventana, el cierre histórico no cambia (correcto para auditoría); el ajuste se ve en reportes en vivo. |
| **Reconcilia dinero recibido (payments), no estado de venta** | Una venta sin pago no aporta; si tiene pago (ej. delegación prepaga) ese pago cuenta. El `state` de la venta es irrelevante para el arqueo. |
| **Abrir/cerrar: cajero + admin** | El admin opera la caja igual que el cajero. |
| **Notificación solo al CERRAR, target admin** | Anti-ruido. Abrir no notifica. El admin se entera de cada cierre, con el descuadre si lo hubo. |
| **Hora de cierre: solo admin la edita** | Vive en un doc de config admin-only, separado del estado runtime de la caja. |

---

## 2. Principio de UX (este feature se juzga por la fluidez del cierre)

El cajero que dirige el cierre debe poder hacerlo **sin pensar**. Guías:

- **Una pantalla, un estado claro, una acción primaria.** "Caja abierta /
  cerrada" entendible de un vistazo. Botón grande: "Abrir caja" o "Cerrar
  caja".
- **El arqueo se siente como una lista de chequeo corta**, no un
  formulario:
  1. Cuenta el efectivo → un campo. El esperado aparece como ayuda. Chip
     en vivo: verde "Cuadra ✓" o ámbar "Sobran/Faltan $X".
  2. Confirma las transferencias → mismo patrón.
  3. El campo de razón **aparece solo si hay descuadre** (no estorba si
     todo cuadra).
  4. "¿Retiraste o consignaste efectivo?" opcional → muestra "Queda en
     caja: $X".
  5. Nota opcional.
  6. Botón "Confirmar cierre", deshabilitado hasta que las razones
     necesarias estén llenas. Antes de confirmar, un resumen claro.
- **Precarga inteligente**: base = remanente anterior; esperado calculado
  solo; `businessDate` precargado. El cajero confirma, no calcula.
- **Cero jerga**: "Efectivo en caja", "Transferencias", "Sobra/Falta",
  "Queda en caja". Nada de "discrepancia/agregados/reconciliación" en la
  UI.
- **Español neutro sin voseo**: "Confirma", "Cuenta el efectivo",
  "puedes", "registra". Nunca "Confirmá/Contá/podés".

---

## 3. Casos de uso — matriz

**Leer entera antes de implementar.** Si algún caso queda sin respuesta,
no avanzar.

### 3.1 Apertura

| Estado al abrir | Comportamiento |
|---|---|
| Caja cerrada | Cajero/admin abre: base inicial precargada con el remanente del último cierre (editable) + nota opcional. Se crea el shift `status: open`; el singleton pasa a `isOpen: true`. `periodStart` = `closedAt` del cierre anterior (o `openedAt` si es el primer cierre histórico). `businessDate` = fecha de `openedAt`. |
| Caja ya abierta | El botón "Abrir" no se muestra. Si por race dos usuarios intentan abrir a la vez, la transacción del singleton serializa y la segunda lanza StateError ("La caja ya está abierta por X"). |

### 3.2 Caja abierta (acumulación en vivo)

| Caso | Comportamiento |
|---|---|
| Cajero registra abonos | Cuentan al esperado de la ventana en vivo (se leen de `payments` por `registeredAt`). Sin cambios al flujo de `registerPayment`. |
| Sales registra pago bajo delegación | Cuenta al esperado, consolidado, sin marca especial. |
| Admin anula un payment de la ventana abierta | El esperado en vivo se recalcula solo. |
| Pasa la hora de cierre configurada | La pantalla muestra un recordatorio suave "Hora de cierre (HH:mm) alcanzada — recuerda hacer el cierre". No bloquea nada. |
| Banner global | Mientras `isOpen`, banner persistente "Caja abierta — desde HH:mm" en todos los roles autenticados (mirror del de delegación, otro color). |

### 3.3 Cierre

| Caso | Comportamiento |
|---|---|
| Cierre cuadrado | Contado == esperado en ambos métodos. No exige razón. Se persiste, singleton `isOpen: false`, `lastClosedAt` y `lastRemainingCash` actualizados. |
| Cierre con descuadre | Por cada método con descuadre, razón obligatoria (validación cliente + el doc se persiste con la razón). |
| Retiro/consignación | Campo opcional `withdrawalAmount`. `remainingCash = countedCash - withdrawal`. No afecta la discrepancia. `remainingCash` precarga la base del próximo turno. |
| Movimientos mientras la caja estuvo cerrada | Ya están dentro de `(periodStart, closedAt]` porque `periodStart` = cierre anterior. La UI muestra "Recibido antes de abrir la caja: $X". |
| Cierra temprano y entra plata después | Esa plata arranca la ventana del próximo cierre. No se pierde. El cierre actual queda inmutable. |
| `businessDate` | Precargado a la fecha de apertura; el cajero puede ajustarlo (útil si la jornada cruzó medianoche). |
| Cerrar sin caja abierta | El botón no se muestra. Si por race se intenta, StateError. |

### 3.4 Post-cierre

| Caso | Comportamiento |
|---|---|
| Admin anula un payment de un cierre ya cerrado | El doc del cierre NO cambia (snapshot inmutable). El cajero recibe la notif `payment_voided` existente. El ajuste se ve en reportes en vivo, no en el cierre histórico. |
| Admin consulta el historial | Lista de cierres ordenada por `closedAt` desc, descuadres destacados. Drill-down + export xlsx. |
| Admin cambia la hora de cierre | Solo afecta el recordatorio a futuro. No toca cierres pasados. |
| Auditor | Sin acceso. El cierre es info de caja, no entra en `/audit`. |

### 3.5 Offline / multi-plataforma

| Caso | Comportamiento |
|---|---|
| Cajero native pierde conexión y cierra caja | Firestore cachea; al volver sincroniza. La transacción del singleton resuelve con guard (puede fallar con StateError claro). |
| Web sin persistence | El submit falla en el momento (CLAUDE.md regla 5). Friendly error. |

---

## 4. Modelo de datos

### 4.1 Singleton de estado: `settings/cash_register`

Doc id fijo `cash_register`. Si no existe, equivale a caja cerrada.
Estado runtime denormalizado para lecturas baratas (banner, botones,
precarga de base). **Escritura admin + cajero.**

| Campo | Tipo | Notas |
|---|---|---|
| `isOpen` | bool | `true` mientras hay un turno abierto. |
| `openShiftId` | String? | Id del doc en `cash_shifts` abierto. Null si cerrada. |
| `openedBy` / `openedByName` | String? | Quién abrió el turno vigente. |
| `openedAt` | Timestamp? | Cuándo se abrió. |
| `openingFloat` | num? | Base inicial declarada en este turno. |
| `periodStart` | Timestamp? | Inicio de la ventana del turno abierto = `closedAt` del cierre anterior (o `openedAt` si es el primero). |
| `lastClosedAt` | Timestamp? | `closedAt` del último cierre. Semilla del `periodStart` de la próxima apertura. |
| `lastRemainingCash` | num? | `remainingCash` del último cierre. Precarga la base del próximo turno. |

Derivados en cliente: `bool get isOpen` directo. Factory
`CashRegister.closed()` para "doc no existe".

> Escritura no destructiva: usar `update` / `set(merge:true)` para no
> pisar campos entre apertura y cierre. (A diferencia de delegación, acá
> no hace falta el `set` sin merge.)

### 4.2 Config admin-only: `settings/cash_register_config`

Doc id fijo `cash_register_config`. Cubierto por el `match
/settings/{sid}` genérico (lectura: cualquier autenticado; escritura:
solo admin) — **no requiere regla nueva**. Lazy seed con default al
primer acceso, igual que `WorkScheduleRepository`.

| Campo | Tipo | Notas |
|---|---|---|
| `closingTime` | String | Hora de cierre `'HH:mm'` (24h interno). Default `'18:00'`. |

### 4.3 Ledger: `cash_shifts/{shiftId}`

Append-only, **id autogenerado** (no por fecha — puede haber más de un
cierre en una misma jornada y la unicidad la garantiza el singleton, no el
id). Se crea con `status: open` y se actualiza a `status: closed` al
cerrar (único update permitido). **Escritura admin + cajero.**

| Campo | Tipo | Notas |
|---|---|---|
| `status` | String enum | `'open'` \| `'closed'`. |
| `businessDate` | String | Etiqueta legible `YYYY-MM-DD`. Default = fecha de `openedAt`, editable al cerrar. |
| `openedBy` / `openedByName` | String | Quién abrió. |
| `openedAt` | Timestamp | Apertura. |
| `openingFloat` | num | Base inicial (precargada del remanente anterior). |
| `periodStart` | Timestamp | Inicio de la ventana (cierre anterior o `openedAt`). |
| `closedBy` / `closedByName` | String? | Quién cerró. Null mientras `open`. |
| `closedAt` | Timestamp? | Cierre = fin de la ventana. Null mientras `open`. |
| `expectedCash` | num? | `openingFloat` + Σ efectivo de payments en `(periodStart, closedAt]`. Congelado al cerrar. |
| `countedCash` | num? | Efectivo físico contado. |
| `cashDiscrepancy` | num? | `countedCash - expectedCash`. |
| `cashDiscrepancyReason` | String? | Obligatoria si `cashDiscrepancy != 0`. |
| `expectedTransfer` | num? | Σ transferencias de payments en la ventana. Congelado. |
| `confirmedTransfer` | num? | Transferencias confirmadas. |
| `transferDiscrepancy` | num? | `confirmedTransfer - expectedTransfer`. |
| `transferDiscrepancyReason` | String? | Obligatoria si `transferDiscrepancy != 0`. |
| `preOpenReceived` | num? | Informativo: dinero recibido en `(periodStart, openedAt)` (caja estuvo cerrada). |
| `withdrawalAmount` | num? | Retiro/consignación opcional. |
| `remainingCash` | num? | `countedCash - (withdrawalAmount ?? 0)`. Precarga base del próximo turno. |
| `paymentsCount` | int? | Cantidad de payments incluidos en la ventana. |
| `note` | String? | Nota libre del cierre. |

Sin migración. No hay docs históricos.

### 4.4 Cambios en colecciones existentes

**Ninguno.** El cierre solo LEE `payments` (collection group ya permitido
para cajero/admin). No se toca `Sale`, `SalePayment`,
`CashierRepository.registerPayment` ni los agregados.

### 4.5 Cómo se computa el esperado

Mismo criterio que `SalesMetrics.compute` para no divergir. Ventana
`(periodStart, closedAt]` (excluyente al inicio, incluyente al cierre →
contigua, sin solapes ni huecos):

```
cash     = p.cashAmount     ?? (method == 'efectivo'      ? p.amount : 0)
transfer = p.transferAmount ?? (method == 'transferencia' ? p.amount : 0)
expectedCash     = openingFloat + Σ cash      (payments en la ventana)
expectedTransfer =                Σ transfer   (idem)
preOpenReceived  = Σ (cash+transfer)          (payments en (periodStart, openedAt))
```

Se lee con `collectionGroup('payments').where('registeredAt', >, periodStart)
.where('registeredAt', <=, closedAt)` (índice `COLLECTION_GROUP` ya existe).
Para el esperado en vivo (caja abierta), usar `now` como cota superior.

---

## 5. Reglas Firestore — texto exacto a aplicar

**IMPORTANTE**: leer `firestore.rules` actual antes de tocar. Reusar
helpers existentes (`isSignedIn`, `isAdmin`, `isCajero`). NO duplicar.

En Firestore las reglas se combinan con **OR**: agregar un `match`
específico para `settings/cash_register` SUMA permisos sobre el genérico
`match /settings/{sid}` (hoy write solo admin). Así el cajero gana write
sin tocar la genérica. `settings/cash_register_config` queda cubierto solo
por la genérica → admin-only, sin regla nueva. Mismo mecanismo que usó la
subcolección `history` de delegación.

### 5.1 Bloque `settings/cash_register` (estado)

```
// ---------- Cierre de caja (estado singleton) ----------
// Estado runtime de la caja. La abren/cierran cajero y admin; la lee
// cualquier autenticado (el banner global "caja abierta" se muestra en
// todos los roles). El genérico settings/{sid} solo da write a admin;
// este match SUMA write a cajero. La config (hora de cierre) vive en
// settings/cash_register_config y queda admin-only por la regla genérica.
match /settings/cash_register {
  allow read: if isSignedIn();
  allow write: if isAdmin() || isCajero();
}
```

### 5.2 Bloque `cash_shifts/{shiftId}` (ledger)

```
// ---------- Cierre de caja (ledger de turnos) ----------
// Append-only. Cajero/admin crean el turno (status open) y lo cierran
// (único update permitido: solo mientras está open). Un turno cerrado es
// inmutable — `resource.data.status == 'open'` en el update lo garantiza.
// Lectura solo caja/admin (no sales, no auditor).
match /cash_shifts/{shiftId} {
  allow read: if isAdmin() || isCajero();
  allow create: if (isAdmin() || isCajero())
                  && request.resource.data.status == 'open';
  allow update: if (isAdmin() || isCajero())
                  && resource.data.status == 'open';
  allow delete: if isAdmin();
}
```

### 5.3 Sin cambios

- `match /sales/{sid}` y `match /sales/{sid}/payments/{pid}`: igual.
- `match /{path=**}/payments/{pid}`: igual (el cierre lee payments con la
  regla de collection group ya existente para cajero/admin).
- `match /settings/{sid}` genérico: igual (cubre `cash_register_config`).

### 5.4 Casos a simular en el Rules Playground (antes de deploy)

- [ ] Cajero lee/escribe `settings/cash_register` → permitido
- [ ] Sales escribe `settings/cash_register` → denegado; lee → permitido
- [ ] Cajero escribe `settings/cash_register_config` → denegado
- [ ] Admin escribe `settings/cash_register_config` → permitido
- [ ] Cajero crea `cash_shifts/X` con `status: 'open'` → permitido
- [ ] Cajero crea `cash_shifts/X` con `status: 'closed'` → denegado
- [ ] Cajero update `cash_shifts/X` cuando `status: 'open'` (cerrarlo) → permitido
- [ ] Cajero update `cash_shifts/X` cuando `status: 'closed'` → denegado
- [ ] Sales/Auditor lee `cash_shifts/X` → denegado
- [ ] Cajero borra → denegado; Admin borra → permitido

Solo si todos pasan: `firebase deploy --only firestore:rules`.

### 5.5 Índices

Probablemente **ninguno nuevo**:
- `cash_shifts where status orderBy closedAt desc` → puede pedir un
  compuesto `status + closedAt`. Si la consola lo pide, agregarlo y
  notarlo. (Alternativa para evitarlo: traer todos y filtrar/ordenar en
  memoria — bajo volumen.)
- Esperado vía `collectionGroup('payments').where('registeredAt', ...)`
  → índice `COLLECTION_GROUP` ya declarado.

---

## 6. Plan de implementación por fases

### Fase 1 — Backend + pantalla de gestión + config (admin-only, zero impact)

**Objetivo**: abrir/cerrar caja, ver estado y esperado en vivo, y
configurar la hora de cierre, todo desde el panel admin. Cajero NO se
entera todavía. Sales, hours, auditor: sin cambios.

#### Archivos a crear/tocar

1. **`lib/core/constants/firestore_paths.dart`**:
   - `static const cashRegisterSettings = 'cash_register';`
   - `static const cashRegisterConfigSettings = 'cash_register_config';`
   - `static const cashShifts = 'cash_shifts';`

2. **Crear** `lib/features/cashier/domain/cash_register.dart`:
   - `CashRegister` (§4.1) + `toMap` + `fromSnapshot` + `CashRegister.closed()`.

3. **Crear** `lib/features/cashier/domain/cash_register_config.dart`:
   - `CashRegisterConfig` con `closingTime` (`'HH:mm'`) + `toMap` +
     `fromMap` + `const CashRegisterConfig.defaults()` (`'18:00'`).
   - Helper `({int hour, int minute}) get parsed` para el recordatorio.

4. **Crear** `lib/features/cashier/domain/cash_shift.dart`:
   - Enum `CashShiftStatus { open, closed }` con `id`/`fromId`.
   - `CashShift` (§4.3) + `toMap` + `fromSnapshot`.
   - Helper `static String businessDateLabel(DateTime d)` → `YYYY-MM-DD`.
   - Getters derivados defensivos (`bool get cashBalances`, etc.).

5. **Crear** `lib/features/cashier/data/cash_shift_repository.dart`
   (espejar `sales_delegation_repository.dart` + el runTransaction de
   `cashier_repository.dart`):
   - `Stream<CashRegister> watchRegister()` — singleton; si no existe,
     `CashRegister.closed()`.
   - `Stream<CashRegisterConfig> watchConfig()` — lazy default.
   - `Future<void> saveConfig(CashRegisterConfig)` — `set` del doc config.
   - `Stream<CashShift?> watchOpenShift()` — vía `openShiftId`.
   - `Stream<List<CashShift>> watchClosedShifts({int limit = 50})`.
   - `Future<({num cash, num transfer, num preOpen, int count})> computeExpected({ required DateTime periodStart, required DateTime openedAt, required DateTime until, required num openingFloat })`
     — query `collectionGroup('payments')` por `registeredAt` en
     `(periodStart, until]` (§4.5). Corre FUERA de la transacción (las
     transactions no admiten queries de subcolección — mismo motivo que
     `deleteSale`). Lo usa tanto el esperado en vivo (until=now) como el
     cierre (until=closedAt).
   - `Future<void> openShift({required AppUser actor, required num openingFloat, String? note})`:
     - `runTransaction`: lee singleton; si `isOpen` → StateError. Crea
       `cash_shifts.doc()` con `status: open`, `periodStart =
       singleton.lastClosedAt ?? now`, `businessDate =
       businessDateLabel(now)`. Set singleton (merge) `isOpen: true`,
       `openShiftId`, `openedBy/Name`, `openedAt`, `openingFloat`,
       `periodStart`.
   - `Future<CashShift> closeShift({ required AppUser actor, required num countedCash, required num confirmedTransfer, String? cashReason, String? transferReason, num? withdrawalAmount, String? note, String? businessDate })`:
     - Leer singleton (`openShiftId`, `periodStart`, `openedAt`,
       `openingFloat`). Calcular esperado con `computeExpected(until=now)`.
     - Validar: descuadre efectivo != 0 ⇒ `cashReason` requerido; idem
       transfer; `remainingCash` no negativo. ArgumentError claro.
     - `runTransaction`: lee singleton; si no `isOpen` → StateError.
       Update `cash_shifts/{openShiftId}` a `status: closed` con todos los
       campos congelados (§4.3). Set singleton (merge) `isOpen: false`,
       `openShiftId: null`, `lastClosedAt: now`, `lastRemainingCash:
       remainingCash`, limpiar `opened*`/`openingFloat`/`periodStart`.
   - Providers al final: `cashShiftRepositoryProvider`,
     `cashRegisterProvider`, `cashRegisterConfigProvider`,
     `openCashShiftProvider`, `closedCashShiftsProvider` (todos
     `autoDispose` + `ref.watch(authStateProvider)`).
   - `AppClock.now()` / `Timestamp.fromDate(AppClock.toInstant(...))`.

6. **Crear** `lib/features/cashier/presentation/cash_close_screen.dart`
   (pantalla principal; aplicar §2 a rajatabla; espejar layout de
   `sales_delegation_screen.dart`):
   - `HeroBanner` + estado (Caja abierta/cerrada, desde cuándo, base).
   - Si cerrada: botón "Abrir caja" → bottom sheet (base precargada con
     `lastRemainingCash`, editable + nota).
   - Si abierta: tarjeta "esperado en vivo" (efectivo / transferencias,
     línea "recibido antes de abrir"), recordatorio si pasó la hora de
     cierre, y botón "Cerrar caja" → bottom sheet de arqueo guiado (§2).
   - Sección "Cierres recientes".

7. **Crear** `lib/features/cashier/presentation/cash_close_screen.dart`
   (config) o **`lib/features/admin/presentation/cash_closing_config...`**:
   editar la hora de cierre. Decisión simple: un `TimePicker` dentro de la
   misma `CashCloseScreen` visible solo para admin, o un card en
   Configuración. Mantenerlo mínimo.

8. **`lib/core/routing/app_router.dart`**:
   - Importar `cash_close_screen.dart`.
   - `GoRoute(path: 'cierre', builder: (_, __) => const CashCloseScreen())`
     dentro del bloque `settings` del ShellRoute admin (junto a `schedule`
     y `delegation`) → `/admin/settings/cierre`.

9. **`lib/features/admin/presentation/admin_settings_screen.dart`**:
   - `_SettingsCard` "Cierre de caja" (después de "Delegación caja"),
     navega a `/admin/settings/cierre`, con chip de estado (Abierta/
     Cerrada) leyendo `cashRegisterProvider`.

10. **`firestore.rules`**: bloques §5.1 y §5.2. Playground (§5.4) → deploy.

11. **`firestore.indexes.json`**: verificar (§5.5); agregar solo si la
    consola lo pide.

12. **`docs/data-model.md`**: documentar `settings/cash_register`,
    `settings/cash_register_config` y `cash_shifts/{shiftId}`.

#### Tests Fase 1

- [ ] `flutter analyze` 0 errores.
- [ ] Code review propio: NO toca `sales_repository.dart`,
  `cashier_repository.dart`, `sale_form_screen.dart`, `app.dart`, ni rules
  de payments.
- [ ] Playground §5.4 verde → `firebase deploy --only firestore:rules`.
- [ ] Smoke (admin en `flutter run -d chrome`):
  - Sin doc previo → "Caja cerrada". Abrir con base 0 → singleton + shift
    `open`, `periodStart` correcto.
  - Registrar (cajero en otra ventana) abono efectivo + transferencia →
    "esperado en vivo" los suma.
  - Cerrar contando exacto → cuadrado, sin pedir razón. `lastRemainingCash`
    seteado.
  - Reabrir → base precargada = remanente anterior; `periodStart` ==
    `lastClosedAt` anterior (ventana contigua).
  - Cerrar con descuadre → exige razón; doc inmutable tras cerrar.
  - Cambiar la hora de cierre y verificar que persiste.
  - Regresión: cajero abono normal / procesa; sales crea venta — igual.

#### Rollback Fase 1

Revertir archivos de `lib/features/cashier/`, routing, admin settings y
docs. Revertir `firestore.rules` + re-deploy. Docs huérfanos en Firestore
no afectan (sin lectores).

#### Commit

```
git add lib/features/cashier/ lib/core/ lib/features/admin/presentation/admin_settings_screen.dart firestore.rules docs/
git commit -m "Cierre de caja — Fase 1: backend + pantalla + hora configurable (admin-only, zero impact)"
git push origin claude/check-system-status-FP9g9
```

**STOP. Esperar feedback antes de Fase 2.**

---

### Fase 2 — Exponer a cajero + banner global + recordatorio + notificación

**Objetivo**: el cajero opera la caja desde su home; banner global "Caja
abierta"; recordatorio cuando pasa la hora de cierre; admin recibe notif
en cada cierre.

#### Archivos a tocar

1. **`lib/features/cashier/presentation/cashier_home_screen.dart`**:
   - Acceso a `/cashier/cierre` (chip de estado leyendo
     `cashRegisterProvider`). Lo ven cajero y admin.

2. **`lib/core/routing/app_router.dart`**:
   - `GoRoute(path: 'cierre', ...)` dentro de `/cashier` →
     `/cashier/cierre`. (El redirect ya permite `/cashier/*` a cajero+admin.)

3. **`lib/app.dart`**:
   - Banner global "Caja abierta" mirror de `_DelegationGlobalBannerHost`.
     Extender el host para apilar ambos banners (delegación + caja).
     Color distinto al naranja de delegación (ej. `primary` verde) para no
     confundir. Texto "Caja abierta — desde HH:mm". Solo si `isSignedIn` y
     `register.isOpen`.

4. **`lib/shared/models/app_notification.dart`**:
   - Agregar `cashShiftClosed('cash_shift_closed')` al enum.
   - `case` en `icon` (ej. `Icons.point_of_sale_outlined` — **verificar
     render en web release**, CLAUDE.md regla 6; fallback `Icons.lock_outline`).
   - `case` en `accentFor`.
   - ⚠️ Ambos switches exhaustivos — sin el case no compila.

5. **`lib/features/cashier/data/cash_shift_repository.dart`**:
   - Inyectar `NotificationsRepository` en el constructor (como
     `CashierRepository`). En `closeShift`, dentro de la misma
     `runTransaction` y **después** de los reads, `_notifications.emitInTxn`
     con `NotificationType.cashShiftClosed`, `targetRoles: const
     [AppRole.admin]`. Body: cuadrado → "Cierre cuadrado: efectivo $X,
     transfer. $Y"; con descuadre → incluir descuadre + razón.

6. **Recordatorio hora de cierre**: en `CashCloseScreen` (y opcionalmente
   un badge en `cashier_home_screen.dart`), comparar `AppClock.now()` con
   el `closingTime` del config cuando `isOpen`. Mostrar aviso suave. Sin
   timers persistentes ni push — es un check en cada build.

7. **`docs/workflows.md`**: receta "Operar el cierre de caja".

#### Tests Fase 2

- [ ] `flutter analyze` 0 errores (switch de notif cubierto).
- [ ] Smoke (cajero + admin):
  - Cajero abre/cierra desde `/cashier/cierre`.
  - Banner global aparece/desaparece en todos los roles.
  - Recordatorio aparece al pasar la hora configurada (cambiar la hora a
    una pasada para probar).
  - Admin recibe notif `cash_shift_closed` (cuadrado vs descuadre).
  - Regresión notifs: `notifications_sheet.dart` renderiza el tipo nuevo.
  - Regresión delegación: delegación activa + caja abierta → ambos banners
    conviven sin romper layout.

#### Rollback Fase 2

Revertir commits de Fase 2. La Fase 1 sigue funcional (admin-only).

#### Commit

```
git add lib/features/cashier/ lib/core/routing/ lib/app.dart lib/shared/models/app_notification.dart docs/
git commit -m "Cierre de caja — Fase 2: entry point cajero + banner + recordatorio + notif al admin"
git push origin claude/check-system-status-FP9g9
```

**STOP. Esperar feedback antes de Fase 3.**

---

### Fase 3 — Visibilidad y accountability (admin)

**Objetivo**: historial de cierres consultable, con detalle, descuadres
destacados y export xlsx.

#### Archivos a tocar

1. **Crear** `lib/features/admin/presentation/cash_shifts_screen.dart`:
   - Lista `status: closed` (`closedCashShiftsProvider`) con
     `RangeFilterBar`, descuadres en color de error, total contado del
     rango. Tap → detalle. Botón export.

2. **Crear** `lib/features/admin/presentation/cash_shift_detail_screen.dart`
   (o bottom sheet): snapshot completo (esperado/contado/descuadre por
   método, razones, retiro, base, ventana, quién abrió/cerró,
   paymentsCount, businessDate).

3. **`lib/shared/services/xlsx_export_service.dart`**:
   - `static Future<void> exportCashShifts({ required BuildContext context, required List<CashShift> shifts, required DateTime rangeStart, required DateTime rangeEnd })`.
   - Reusar `_stylizeHeader`, `_applyColumnWidths`, `deliver.deliverFiles`.
   - Columnas: fecha, abrió, cerró, base, esperado efectivo, contado,
     descuadre efectivo, razón, esperado transfer., confirmado, descuadre
     transfer., razón, retiro, queda en caja, nota.

4. **`lib/core/routing/app_router.dart`**: ruta para el historial (ej.
   `/admin/settings/cierre/historial`). Coherente con el menú.

5. **`admin_settings_screen.dart`** o la `CashCloseScreen`: enlace al
   historial.

#### Tests Fase 3

- [ ] `flutter analyze` 0 errores.
- [ ] Varios cierres (cuadrados y con descuadre) → lista ordenada,
  descuadres destacados.
- [ ] Detalle coincide con Firestore. Filtro por rango ajusta. Export xlsx
  con columnas correctas.

#### Rollback Fase 3

Revertir commits. Solo lectura/export; sin impacto en datos.

#### Commit

```
git add lib/features/admin/presentation/ lib/shared/services/xlsx_export_service.dart lib/core/routing/ docs/
git commit -m "Cierre de caja — Fase 3: historial admin + detalle + export xlsx"
git push origin claude/check-system-status-FP9g9
```

---

## 7. Edge cases — resolución específica

| Edge case | Resolución |
|---|---|
| Singleton no existe | `watchRegister` emite `CashRegister.closed()`. UI: cerrada. |
| Config no existe | `watchConfig` emite `CashRegisterConfig.defaults()` (`'18:00'`). |
| Primer cierre histórico (sin `lastClosedAt`) | `periodStart = openedAt`. No hay nada previo que barrer; `preOpenReceived = 0`. |
| Dos usuarios abren a la vez | La transacción del singleton serializa; la 2ª ve `isOpen: true` → StateError. |
| Cierre temprano y entra plata después | Esa plata arranca la ventana del próximo cierre (contigua). El cierre actual queda inmutable. **Nada se pierde.** |
| Jornada cruza medianoche | La ventana es por timestamp, no por fecha → un solo cierre la cubre. `businessDate` rotula con el día de apertura (editable). |
| Admin anula payment de un cierre cerrado | Inmutable; no recomputa. Notif `payment_voided` avisa al cajero. Ajuste en reportes en vivo. |
| Caja "olvidada" abierta de un día para otro | Sigue acumulando; el banner lo recuerda; el recordatorio de hora de cierre insiste. Sin auto-cierre (no hay backend). |
| Esperado cambia entre el cálculo y el commit | Aceptable: se calcula justo antes del cierre; diferencia mínima de timing aparecería como descuadre. Bajo volumen, riesgo marginal. |
| Reloj cliente ≠ server | Timestamps con `AppClock`; las ventanas usan los timestamps persistidos, no el reloj local por lectura. El recordatorio usa hora local (cosmético). |
| Delegación activa + caja abierta | Independientes. Dos banners conviven. Pagos de delegación cuentan al esperado sin distinción. |
| `withdrawalAmount` > `countedCash` | Validación cliente: `remainingCash` no negativo. Bloquear/advertir. |

---

## 8. Checklist final de validación (pre-release, tras Fase 3)

### Regresión
- [ ] Cajero: abono / procesa / cancela / marca pérdida
- [ ] Admin anula abono
- [ ] Sales crea venta (con y sin delegación activa)
- [ ] Delegación caja: activar/desactivar + banner + KPI
- [ ] `SalesMetrics.compute` y KPIs intactos
- [ ] Notificaciones existentes renderizan y agrupan bien
- [ ] Auditor ve su dashboard (sin acceso a cierres)
- [ ] Hours abre/cierra turno; listas maestras editables

### Funcionalidad nueva
- [ ] Abrir caja con base precargada del remanente anterior (editable)
- [ ] Esperado en vivo suma efectivo + transferencia de la ventana
- [ ] Ventana contigua: `periodStart` nuevo == `closedAt` anterior
- [ ] Plata entre cierres (caja cerrada) cae en el próximo cierre
- [ ] Cierre cuadrado no exige razón; con descuadre sí
- [ ] Retiro opcional → `remainingCash` correcto → base del próximo turno
- [ ] `businessDate` precargado y editable
- [ ] Hora de cierre configurable (admin) + recordatorio al pasar
- [ ] Banner global "Caja abierta" en todos los roles
- [ ] Notif `cash_shift_closed` al admin (cuadrado vs descuadre)
- [ ] Historial admin + detalle + descuadres + export xlsx
- [ ] Rules playground (§5.4) verde

### Documentación
- [ ] `docs/data-model.md`: 3 docs nuevos
- [ ] `docs/workflows.md`: receta "Operar el cierre de caja"
- [ ] `CHANGELOG.md`: "Agregado — cierre de caja con arqueo de efectivo y
      transferencias, ventana contigua y hora de cierre configurable"
- [ ] `CLAUDE.md`: sumar `cierre de caja` a la lista de features + patrón
      singleton+ledger si aplica
- [ ] `pubspec.yaml` bump (al liberar release real)

---

## 9. Out of scope (explícito, NO implementar)

- Caja por cajero (ownership por uid). Hoy singleton global.
- Editar o reabrir un cierre cerrado (inmutable).
- Desglose de delegación dentro del cierre (consolidado sin distinción).
- Recompute de cierres cerrados al anular payments (snapshot inmutable).
- Auto-cierre por la hora configurada / Cloud Functions (no hay backend).
  La hora de cierre solo recuerda; no cierra sola.
- Push del SO. Notifs in-app.
- Acceso del auditor a los cierres.

---

## 10. Mejoras post-MVP (opcionales, no en este plan)

- KPI en el dashboard admin: "descuadre acumulado del mes".
- Desglose de transferencias por destino dentro del cierre.
- Notif/recordatorio escalado si la caja sigue abierta X tiempo tras la
  hora de cierre.
- Branch especial en `notifications_sheet.dart` para agrupar cierres.

---

## 11. Notas de estilo (recordatorio)

- **Español neutro sin voseo**: "Confirma", "Abre caja", "Cuenta el
  efectivo", "puedes", "registra". Nunca "Confirmá/Abrí/podés".
- Trailing commas en todo bloque multilínea.
- Comentarios solo cuando el WHY no es obvio.
- `formatCop` para moneda, `formatDateTime` para fechas.
- Providers `autoDispose` + `ref.watch(authStateProvider)` para rebind.
- Sin tests salvo motores puros (no aplica acá).
