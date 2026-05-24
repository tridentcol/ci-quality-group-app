# Plan — Modo delegación caja (toggle on-demand)

Estado: **pendiente, no iniciado** (escrito 2026-05-24).
Rama de trabajo: `claude/check-system-status-FP9g9`.
Doc objetivo de un agente ejecutor en otra sesión. **Self-contained**:
no necesita más contexto que CLAUDE.md + este archivo.

---

## 0. Cómo usar este plan

Cada fase es **independientemente reversible**: si rollbackeás solo
esa fase, todo lo anterior sigue funcionando. NO mergear fases. NO
deployar dos fases en el mismo push. Después de cada fase: validar →
commit → push → esperar feedback antes de seguir.

Si una validación falla, **parar y reportar** antes de seguir.

---

## 1. Contexto y problema

### 1.1 Situación actual (1.3.0+13)

- `sales` no tiene campos de pago en su formulario. El pago lo registra
  `cajero`/`admin` después, desde la pantalla de pagos de la venta.
- Esto centraliza el control del dinero como los dueños quieren.
- **Problema**: 1–3 veces por semana, admin/cajero no están físicamente
  presentes (reuniones, ausencias) y sales termina recibiendo dinero.
  No tiene forma de registrar el método/destino/quién recibió, así que
  la trazabilidad de esos pagos se pierde.

### 1.2 Decisión tomada

Implementar un **toggle de delegación** controlado por admin:

- Admin activa el modo desde su home, opcionalmente con vencimiento.
- Mientras está activo, sales ve los campos de pago en el form de venta
  y puede registrar pago en el mismo submit (transaccional).
- Cada pago así creado queda marcado con `createdViaDelegation: true`.
- Toda activación/desactivación queda en histórico append-only.
- Notificación in-app a admin+cajero en cada activación, desactivación
  y pago registrado bajo delegación.
- KPI en el dashboard admin: "Pagos bajo delegación este mes".

### 1.3 Decisiones de diseño explícitas (NO revisitar sin justificación)

| Decisión | Razón |
|---|---|
| Toggle es **singleton global**, no por usuario | Una sola "ventana" abierta a la vez. Simple, predecible. |
| Campos de pago **opcionales** durante delegación | Sales puede crear ventas sin pago aunque delegación esté on (cliente no pagó al momento). La delegación habilita, no obliga. |
| `createSale` extendido para crear sale+payment en una sola transacción | UX limpia, atomicidad, sin pantallas intermedias. |
| **NO tocar flujo de edición** | Sales editando dentro de 24h sigue sin campos de pago. Si necesitan agregar pago a una venta existente, lo hace cajero/admin. Esto reduce drásticamente la superficie de cambio. |
| Sin auto-expiration automática del bool | `request.time < expiresAt` se chequea en rules. El doc se queda con `active: true` pero rules y cliente lo tratan como inactivo después de `expiresAt`. Cleanup cosmético se hace cuando admin entra a la pantalla. |
| Trazabilidad vía `SalePayment.createdViaDelegation` + history append-only + notifs persistidas | Sin necesidad de implementar `audit_log` (eso es Fase 9B, no iniciada). Suficiente para MVP. |
| Notifs por activación/desactivación target a admin+cajero (no a sales) | Quien necesita enterarse son los responsables de caja, no quien recibe el permiso. |
| Notif por cada pago bajo delegación target a admin+cajero | Visibilidad en tiempo real de qué está pasando mientras admin está fuera. |

---

## 2. Casos de uso — matriz completa

**Antes de implementar, leer esta matriz entera.** Cada celda
debe estar resuelta en el código. Si algún caso queda sin respuesta,
no avanzar.

### 2.1 Sales crea una venta

| Estado delegación al abrir form | Estado al submit | Comportamiento esperado |
|---|---|---|
| Inactiva | Inactiva | Form igual que hoy. Sin campos de pago. Crea venta sin payment. |
| Activa (vigente) | Activa (vigente) | Form muestra campos de pago opcionales. Si sales los llena → crea venta + payment (transaccional) con `createdViaDelegation: true`. Si los deja vacíos → crea venta sin payment (igual que el flujo normal). |
| Activa (vigente) | Inactiva o expirada | Banner naranja en el form: "El modo delegación se desactivó. Los datos de pago ingresados no se guardarán." Al submit, cliente omite los datos de pago y crea venta sin payment. Snackbar post-creación informa. |
| Inactiva | Activa (vigente) | Sales no ve los campos (form abierto antes). Crea venta sin payment. Si quería registrar pago, debe pedir a cajero/admin como flujo normal. |

### 2.2 Sales edita una venta dentro de las 24h

| Caso | Comportamiento esperado |
|---|---|
| Venta creada SIN payment, delegación off | Edita campos normales. Sin cambios. |
| Venta creada SIN payment, delegación on | Edita campos normales. **NO aparecen campos de pago en edición.** Flujo de edición no cambia con delegación. |
| Venta creada CON payment bajo delegación, delegación off | Edita campos normales (descripción, items, etc.). Si edita items y cambia `totalValue`, los agregados financieros se recomputan como hoy (clampeo a >= 0 en sobrepago). El payment queda como está. |
| Venta creada CON payment bajo delegación, delegación on | Igual que arriba. **NO** se puede modificar ni borrar el payment desde el form de venta de sales. Si necesita corregir el pago, anula admin (delete) y se registra de nuevo. |

### 2.3 Admin/cajero procesa una venta con payment bajo delegación

| Caso | Comportamiento esperado |
|---|---|
| Venta tiene `paidAmount >= totalValue` (saldada por payment bajo delegación) | Cajero puede marcarla `procesada` con un tap. Flujo normal. |
| Venta tiene `paidAmount < totalValue` | Cajero registra abono(s) adicionales como flujo normal. Los abonos del cajero NO tienen `createdViaDelegation`. |
| Admin quiere anular el payment bajo delegación | Admin va a la pantalla de pagos, `voidPayment` como hoy. Notif `payment_voided` se emite igual. La historia queda en la notif persistida. |

### 2.4 Delegación se activa/desactiva con sales conectado

| Caso | Comportamiento esperado |
|---|---|
| Sales tiene la app abierta, admin activa delegación | El `salesDelegationProvider` emite update. Si sales está en home, no cambia nada visible. Si abre el form de venta, ve los campos de pago. Banner global aparece en AppBar. |
| Sales tiene el form abierto, admin activa delegación | El form re-renderea reactivamente y aparece la sección de pago vacía (los campos llenos en otros lados no se tocan). Banner global aparece. |
| Sales tiene el form abierto con campos llenos, admin desactiva delegación | Banner naranja en la sección de pago: "El modo delegación se desactivó. Los datos de pago no se guardarán." Campos siguen visibles para no perder lo escrito (cosmético). Al submit, cliente omite los datos. |
| Delegación expira sola (`expiresAt < now`) mientras sales tiene form abierto | Mismo comportamiento que arriba. El provider detecta la expiración via el `isCurrentlyActive` derivado y emite false. |
| Sales submit y delegación expiró entre el tap y el server | Server rechaza con `permission-denied`. Cliente captura el error con `friendlyError` y muestra: "El modo delegación expiró. Volvé a intentar — la venta se va a crear sin pago." Sales reintenta. |

### 2.5 Múltiples admins, múltiples sales

| Caso | Comportamiento esperado |
|---|---|
| Admin A activa, admin B desactiva 5 min después | Last-write-wins en el doc singleton. Ambas operaciones quedan en history. |
| 2 sales con form abierto durante delegación, ambos submit | Cada uno crea su sale + payment independiente. Sin conflict. |
| Sales A llena pago bajo delegación, sales B no llena pago bajo delegación | Cada uno crea su venta según lo que llenó. La delegación es habilitante, no obligatoria. |

### 2.6 Auditor

| Caso | Comportamiento esperado |
|---|---|
| Auditor consulta dashboard | Las ventas creadas bajo delegación aparecen normalmente filtradas por su `auditFilter`. El badge "bajo delegación" en la card es visible. |
| Auditor NO ve el toggle | El admin home no es accesible para auditor. La info de delegación no aparece en `/audit`. |

### 2.7 Offline

| Caso | Comportamiento esperado |
|---|---|
| Sales en native (Android) pierde conexión con delegación on | Firestore cachea offline. Sales puede crear venta + payment, queda en queue local. Al volver la red sincroniza. Si delegación expiró mientras estuvo offline, server rechaza al sincronizar — el SDK reporta error que sales ve la próxima vez que abra la app. |
| Sales en web pierde conexión | Web no tiene persistence (CLAUDE.md regla 5). El submit falla en el momento. Sin queue. |

---

## 3. Modelo de datos

### 3.1 Nueva colección: `settings/sales_delegation` (singleton)

Doc id fijo: `sales_delegation`. Si no existe, equivale a inactivo.

| Campo | Tipo | Notas |
|---|---|---|
| `active` | bool | `true` mientras esté activa. Solo admin la cambia. |
| `activatedBy` | String | uid del admin que la activó. |
| `activatedByName` | String | Nombre cacheado. |
| `activatedAt` | Timestamp | Cuándo se activó. |
| `expiresAt` | Timestamp? | Vencimiento opcional. Null = manual hasta desactivar. |
| `note` | String? | Razón humana ("Reunión con cliente X hasta las 4pm"). |
| `deactivatedBy` | String? | uid del admin que desactivó. Null si vigente o expiró sola. |
| `deactivatedByName` | String? | |
| `deactivatedAt` | Timestamp? | |

Derivado en cliente: `isCurrentlyActive = active && (expiresAt == null || expiresAt > AppClock.now())`.

### 3.2 Nueva subcolección: `settings/sales_delegation/history/{historyId}`

Append-only. Una entry por cada activación/desactivación.

| Campo | Tipo | Notas |
|---|---|---|
| `action` | String enum | `'activated'` \| `'deactivated'` |
| `actorUid` | String | uid del admin. |
| `actorName` | String | Cacheado. |
| `at` | Timestamp | Cuándo ocurrió. |
| `expiresAt` | Timestamp? | Solo si action=activated. |
| `note` | String? | Solo si action=activated. |

### 3.3 Cambios en `sales/{id}/payments/{paymentId}`

Agregar 1 campo:

| Campo | Tipo | Notas |
|---|---|---|
| `createdViaDelegation` | bool | `true` solo cuando creado por sales bajo delegación. Default `false` para abonos normales (cajero/admin) y para todos los payments históricos. |

Sin migración necesaria — el fallback es `false` para docs viejos.

### 3.4 Cambios en `sales/{id}`

**Ninguno.** El flag vive en el payment, no en la venta.

---

## 4. Reglas Firestore — texto exacto a aplicar

**IMPORTANTE**: leer `firestore.rules` actual antes de tocar. Ubicar las
secciones existentes; NO duplicar helpers. Si `isSales()` ya existe,
reusarlo. Si no existe, agregarlo.

### 4.1 Helpers nuevos

```
function delegationDoc() {
  return get(/databases/$(database)/documents/settings/sales_delegation);
}

function delegationExists() {
  return exists(/databases/$(database)/documents/settings/sales_delegation);
}

function delegationActive() {
  return delegationExists()
    && delegationDoc().data.active == true
    && (
      !('expiresAt' in delegationDoc().data)
      || delegationDoc().data.expiresAt == null
      || request.time < delegationDoc().data.expiresAt
    );
}
```

Nota: Firestore cachea `get()` y `exists()` dentro de una misma
evaluación de rule. Las 3 invocaciones a `delegationDoc()` cuentan
como 1 sola lectura facturable.

### 4.2 Sección `match /settings/sales_delegation`

```
match /settings/sales_delegation {
  allow read: if isSignedIn();
  allow write: if isAdmin();

  match /history/{hid} {
    allow read: if isAdmin();
    allow create: if isAdmin()
                    && request.resource.data.actorUid == request.auth.uid;
    allow update, delete: if false;
  }
}
```

### 4.3 Cambio en `match /sales/{sid}/payments/{pid}`

**Solo cambia el `allow create`**. El resto (read, update, delete) queda
exactamente como está hoy.

Antes (asumido, verificar contra rules actuales):
```
allow create: if (isAdmin() || isCajero())
                && request.resource.data.amount is number
                && request.resource.data.amount > 0;
```

Después:
```
allow create: if request.resource.data.amount is number
                && request.resource.data.amount > 0
                && (
                  isAdmin() || isCajero()
                  || (
                    isSales()
                    && delegationActive()
                    && request.resource.data.registeredBy == request.auth.uid
                    && request.resource.data.createdViaDelegation == true
                  )
                );
```

El check `createdViaDelegation == true` actúa como guard: si sales
intentara crear un payment sin el flag, sería denegado aunque
delegación esté activa. Esto fuerza que el flujo de sales SIEMPRE
marque la trazabilidad.

### 4.4 Sin cambios

- `match /sales/{sid}` queda igual.
- `match /{path=**}/payments/{pid}` (wildcard del collection group) queda igual.

---

## 5. Plan de implementación por fases

### Fase 1 — Backend del toggle (zero impact en sales)

**Objetivo**: tener el switch funcional en el admin home. Sales y
cajero NO se enteran del cambio.

#### Archivos a crear/tocar

1. **Crear** `lib/features/admin/domain/sales_delegation.dart`:
   - Clase `SalesDelegation` con todos los campos de §3.1.
   - Constructor + `toMap()` + `fromSnapshot()`.
   - Getter derivado `bool get isCurrentlyActive => active && (expiresAt == null || expiresAt!.isAfter(AppClock.now()));`
   - Factory `SalesDelegation.inactive()` para el caso "doc no existe".

2. **Crear** `lib/features/admin/domain/sales_delegation_history_entry.dart`:
   - Clase + `toMap` + `fromSnapshot` con campos de §3.2.

3. **Crear** `lib/features/admin/data/sales_delegation_repository.dart`:
   - `class SalesDelegationRepository`.
   - `Stream<SalesDelegation> watch()` — escucha el doc; si no existe emite `SalesDelegation.inactive()`.
   - `Future<void> activate({required AppUser actor, Duration? expiresIn, String? note})`:
     - `runTransaction`: lee doc actual, escribe `active: true` + campos, escribe entry en `history/{auto}` con `action: 'activated'`.
   - `Future<void> deactivate({required AppUser actor})`:
     - `runTransaction`: lee doc actual, escribe `active: false` + `deactivatedBy/At`, escribe entry en `history/{auto}` con `action: 'deactivated'`.
   - Provider `salesDelegationRepositoryProvider` al final.
   - Provider `salesDelegationProvider`:
     ```dart
     final salesDelegationProvider =
         StreamProvider.autoDispose<SalesDelegation>((ref) {
       ref.watch(authStateProvider);  // rebind on auth change (convención)
       return ref.watch(salesDelegationRepositoryProvider).watch();
     });
     ```

4. **Crear** `lib/features/admin/presentation/sales_delegation_screen.dart`:
   - Pantalla con:
     - Estado actual (activa/inactiva + tiempo restante si tiene `expiresAt`)
     - Switch grande para activar/desactivar
     - Al activar, modal pregunta:
       - Duración: chips `1h`, `4h`, `8h`, `Sin vencimiento` (default `4h`)
       - Nota opcional (TextFormField)
     - Sección "Historial reciente" (últimas 20 entries de history)
   - Reusar `HeroBanner`, `Card`, `FilledButton.icon` (convenciones de UI).
   - Usar `formatDateTime` + duración legible.

5. **Editar** `lib/core/routing/app_router.dart`:
   - Agregar ruta `/admin/delegation` dentro del `ShellRoute` de admin.

6. **Editar** `lib/features/admin/presentation/admin_home_screen.dart` (o donde estén los accesos rápidos del admin):
   - Card nuevo: "Delegación caja" con estado actual y botón "Configurar" que navega a `/admin/delegation`.

7. **Editar** `firestore.rules`:
   - Agregar helpers de §4.1.
   - Agregar bloque `match /settings/sales_delegation` de §4.2.
   - **NO tocar** el bloque de payments todavía. Eso es Fase 2.

8. **Editar** `firestore.indexes.json`: probablemente no requiera índices nuevos en esta fase. Verificar; si la query de history pide uno, agregarlo.

#### Tests Fase 1

Antes de deploy:
- [ ] `flutter analyze` 0 errores.
- [ ] Code review propio: leer el diff entero, asegurar que no toca:
  - `sales_repository.dart`
  - `cashier_repository.dart`
  - `sale_form_screen.dart`
  - rules de payments
  - Cualquier archivo de sales o cashier

Deploy de rules:
- [ ] **Firebase Console → Firestore → Rules → Playground**, simular:
  - Admin lee `settings/sales_delegation` → permitido
  - Sales lee `settings/sales_delegation` → permitido
  - Sales escribe `settings/sales_delegation` → denegado
  - Admin escribe `settings/sales_delegation` → permitido
  - Admin crea `settings/sales_delegation/history/abc` con su uid → permitido
  - Admin crea con uid distinto → denegado
  - Admin update history → denegado
- [ ] Si todos pasan, `firebase deploy --only firestore:rules`.

Smoke test manual (web local con `flutter run -d chrome`):
- [ ] Login como admin. Navegar a `/admin/delegation`. Doc no existe → ver "Inactiva".
- [ ] Activar con 1h y nota "test". Confirmar en Firebase Console que el doc se creó con los campos correctos.
- [ ] Confirmar que apareció un entry en `history/`.
- [ ] Desactivar. Confirmar que `active: false` y `deactivatedAt` se setearon.
- [ ] Confirmar que apareció otro entry en `history/`.
- [ ] **Login como sales en otra ventana**. Crear una venta normal (sin cambios). Confirmar que funciona igual que antes.
- [ ] **Login como cajero**. Registrar un abono normal. Confirmar que funciona igual.

#### Rollback Fase 1

Si algo se rompe:
- Revertir los archivos de admin (commits).
- Revertir `firestore.rules` y re-deploy.
- El doc `settings/sales_delegation` queda huérfano en Firestore; sin lectores, no afecta.

#### Commit

```
git add lib/features/admin/ lib/core/routing/ firestore.rules
git commit -m "Modo delegación caja — Fase 1: backend del toggle (admin-only, zero impact sales/cajero)"
git push origin claude/check-system-status-FP9g9
```

**STOP. Esperar feedback antes de Fase 2.**

---

### Fase 2 — Rules de payments (el cambio más riesgoso)

**Objetivo**: permitir que sales cree payments cuando delegación está
activa. Sin cambios de UI todavía — sales sigue sin ver los campos.

#### Archivos a tocar

1. **Editar** `firestore.rules`:
   - Modificar `allow create` del bloque `match /sales/{sid}/payments/{pid}` según §4.3.

2. **Nada más.** No tocar ningún `.dart`.

#### Tests Fase 2

**Tests en Firebase Console Playground (OBLIGATORIO antes de deploy)**:

Asegurarse de que existe el doc `settings/sales_delegation` desde Fase 1.
Crear dos snapshots de simulación: uno con delegación activa, otro inactiva.

Casos a simular (cada uno create en `/sales/SOMEID/payments/NEWID`):

- [ ] Cajero, delegación off, payload válido → **permitido** (regresión)
- [ ] Cajero, delegación on, payload válido → **permitido**
- [ ] Admin, delegación off, payload válido → **permitido** (regresión)
- [ ] Admin, delegación on, payload válido → **permitido**
- [ ] Sales, delegación off, payload válido con `createdViaDelegation: true` → **denegado**
- [ ] Sales, delegación off, payload válido sin el flag → **denegado**
- [ ] Sales, delegación on, payload con `createdViaDelegation: true` y `registeredBy == auth.uid` → **permitido**
- [ ] Sales, delegación on, payload SIN el flag → **denegado**
- [ ] Sales, delegación on, payload con flag pero `registeredBy` distinto a su uid → **denegado**
- [ ] Sales, delegación on pero `expiresAt < now` → **denegado**
- [ ] Sales, delegación on, payload con `amount: 0` → **denegado**

**Solo si los 11 casos pasan**, deployar:
```
firebase deploy --only firestore:rules
```

Smoke test manual post-deploy (~30s después del deploy):
- [ ] Login como cajero. Registrar un abono en cualquier venta. Confirmar que funciona.
- [ ] Login como admin. Registrar un abono. Confirmar que funciona.
- [ ] Login como sales. Intentar crear un payment directamente desde Firebase Console (set un doc en `sales/X/payments/Y`) → Console muestra "permission denied" si la regla no le permite todavía sin el flag.

#### Rollback Fase 2

```
git checkout HEAD~1 firestore.rules
firebase deploy --only firestore:rules
```

Propagación 30s–1min. La Fase 3 todavía no existe, así que el frontend
sigue funcionando.

#### Commit

```
git add firestore.rules
git commit -m "Modo delegación caja — Fase 2: rules permiten a sales crear payment bajo delegación con flag obligatorio"
git push origin claude/check-system-status-FP9g9
```

**STOP. Esperar feedback antes de Fase 3.**

---

### Fase 3 — UI de sales condicional

**Objetivo**: cuando delegación está activa, sales ve campos de pago en
el form de venta y puede registrar pago en el mismo submit.

#### Archivos a tocar

1. **Editar** `lib/features/sales/data/sales_repository.dart`:
   - Extender `createSale(...)` con parámetros opcionales:
     ```dart
     // Datos de pago opcional (solo se escribe si vienen los 3)
     num? paymentCashAmount,
     num? paymentTransferAmount,
     String? paymentTransferDestination,
     String? paymentPayerName,
     String? paymentMethod,
     ```
   - Si `paymentCashAmount != null || paymentTransferAmount != null`,
     dentro de la misma `runTransaction` que genera el consecutivo:
     - Crear ref `paymentRef = saleRef.collection('payments').doc()`
     - `txn.set(paymentRef, { ...payment data..., createdViaDelegation: true })`
     - Actualizar agregados del sale en el mismo `txn.set(saleRef, ...)`:
       - `paidAmount: amount`
       - `outstandingBalance: max(0, totalValue - amount)`
       - `financialStatus: Sale.computeFinancialStatus(...)`
     - Notif `payment_delegation_recorded` con `emitInTxn` (target rol cajero+admin).
   - **NO** tocar `updateSale`. El flujo de edición no cambia.

2. **Editar** `lib/features/sales/presentation/sale_form_screen.dart`:
   - Agregar lectura del provider:
     ```dart
     final delegation = ref.watch(salesDelegationProvider).valueOrNull
                          ?? SalesDelegation.inactive();
     final showPayment = delegation.isCurrentlyActive;
     ```
   - Si `showPayment`, renderar la sección de pago (reusar `_PaymentSection`
     ya existente para admin/cajero — si está en otro archivo, importarlo;
     si está privado, extraerlo a `lib/features/sales/presentation/widgets/sale_payment_section.dart` compartido).
   - **Banner naranja** si `showPayment` cambió a `false` después de que sales llenó algo (track con `_didFillPayment`):
     - "⚠️ El modo delegación se desactivó. Los datos de pago no se guardarán."
   - **NO** hacer required los campos de pago. Sales puede dejarlos vacíos.
   - En `_submit`:
     - Si `showPayment` al momento del submit y al menos uno de los montos > 0, pasarlos a `createSale`.
     - Si `showPayment` es false al submit (caso "expiró mid-form"), ignorar los datos de pago y crear venta sin payment.
     - Después del submit exitoso, si se ignoraron datos de pago por desactivación, mostrar snackbar: "Venta creada. Los datos de pago no se guardaron porque el modo delegación se desactivó."

3. **Editar** `lib/app.dart` (o donde esté el `Scaffold` raíz):
   - Banner global persistente cuando `delegation.isCurrentlyActive`:
     - Color naranja suave, ícono warning, texto "Modo delegación caja activo — expira HH:mm" (o "sin vencimiento")
     - Visible en TODOS los roles (admin, sales, cajero, auditor).
     - Implementar como `MaterialBanner` en el shell, o como widget custom en el AppBar bottom.

4. **Verificar** que `Sale.computeFinancialStatus` ya existe y se puede llamar pasándole los nuevos valores. Si no existe, crear método estático que reciba `(totalValue, paidAmount, lossAmount)` y devuelva el enum.

5. **Editar** `lib/shared/models/app_notification.dart`:
   - Agregar al enum `NotificationType`:
     - `delegationActivated` con ícono `Icons.lock_open_outlined`
     - `delegationDeactivated` con ícono `Icons.lock_outline`
     - `paymentDelegationRecorded` con ícono `Icons.payments_outlined`
   - Definir `accentFor(scheme)` para cada uno.

6. **Editar** `lib/features/admin/data/sales_delegation_repository.dart`:
   - En `activate()`, después del set y antes del commit, llamar
     `notifications.emitInTxn(...)` con `delegationActivated`, target rol
     `cajero` + `admin` (sin incluir al actor para no notificarse a sí mismo).
   - Idem en `deactivate()` con `delegationDeactivated`.

7. **Editar** `lib/features/sales/presentation/sale_form_screen.dart` o
   `sales_repository.dart` (donde corresponda):
   - Al crear payment bajo delegación, emitir `paymentDelegationRecorded`
     a rol `cajero` + `admin`. Body: "Sales {nombre} registró pago bajo delegación: {consecutivo} — {payerName}, {monto}".

#### Tests Fase 3

`flutter analyze` 0 errores.

Smoke test con `flutter run -d chrome` (dos ventanas: una admin, una sales):

**Caso A: flujo normal sin delegación**
- [ ] Sales abre form. No ve campos de pago. Igual que hoy.
- [ ] Sales crea venta sin payment. Verifica en Firebase Console: sale sin subdoc payment.
- [ ] Cajero ve la venta, registra abono. Funciona como hoy.

**Caso B: delegación activa antes de abrir form**
- [ ] Admin activa delegación con 4h.
- [ ] Sales abre form. Ve campos de pago (vacíos).
- [ ] Sales llena venta + pago efectivo $100k + payer "Juan". Submit.
- [ ] En Firebase Console: sale creada con consecutivo, subdoc payment con `createdViaDelegation: true`, `cashAmount: 100000`, etc.
- [ ] Verifica que `paidAmount`, `outstandingBalance`, `financialStatus` están bien.
- [ ] Admin recibe notif `payment_delegation_recorded`.

**Caso C: delegación se activa con sales en form abierto**
- [ ] Sales abre form (delegación off, no ve campos).
- [ ] Admin activa.
- [ ] Sales ve aparecer la sección de pago en su form en vivo. Banner global aparece.

**Caso D: delegación se desactiva con sales mid-form**
- [ ] Sales abre form con delegación on.
- [ ] Sales llena pago: efectivo $50k.
- [ ] Admin desactiva delegación.
- [ ] Sales ve banner naranja "modo desactivado, no se guardará".
- [ ] Sales submit. Venta se crea SIN payment. Snackbar informa.
- [ ] En Firebase Console: sale sin subdoc payment.

**Caso E: delegación expira mid-form**
- [ ] Admin activa con expiración en 2 min.
- [ ] Sales abre form, empieza a llenar.
- [ ] Esperar 2 min.
- [ ] Provider emite `isCurrentlyActive: false`. Banner naranja aparece.
- [ ] Submit ignora los datos de pago. Venta sin payment.

**Caso F: race condition expira entre submit y server**
- Difícil de reproducir manualmente. Skip — la regla del server es la red de seguridad. Confiar que `friendlyError` muestra el mensaje y que sales puede reintentar.

**Caso G: edición de venta con payment bajo delegación**
- [ ] Sales edita una venta del Caso B dentro de 24h.
- [ ] Cambia un campo no-pago (ej. cantidad de item).
- [ ] Confirma que NO ve campos de pago en edición.
- [ ] Submit. Venta se actualiza. Payment queda intacto. `outstandingBalance` recomputa.

**Caso H: cajero procesa venta con payment bajo delegación**
- [ ] Login como cajero. Ve la venta del Caso B. Tiene `paidAmount` completo.
- [ ] Cajero marca `procesada`. Funciona como hoy.

**Caso I: admin anula payment bajo delegación**
- [ ] Admin va a pantalla de pagos de la venta del Caso B.
- [ ] Anula el payment.
- [ ] `paidAmount` vuelve a 0, `outstandingBalance` vuelve a `totalValue`.
- [ ] Notif `payment_voided` se emite.

**Caso J: edge — sales intenta enviar pago con monto > totalValue**
- [ ] Sales crea venta con `totalValue: 100`, intenta pagar $200.
- [ ] Cliente valida (sobrepago no permitido en payment desde el form).
- [ ] Si no hay validación cliente, server acepta y `outstandingBalance` queda en 0 (clampeo). Decidir según UX.

#### Rollback Fase 3

Revertir los commits de Fase 3. La Fase 2 deja las rules permitiendo a
sales crear payments con flag, pero como la UI no expone los campos, no
se usan. Es seguro.

#### Commit

```
git add lib/features/sales/ lib/features/admin/data/sales_delegation_repository.dart lib/app.dart lib/shared/models/app_notification.dart
git commit -m "Modo delegación caja — Fase 3: UI condicional en sales form + notifs + transactional sale+payment"
git push origin claude/check-system-status-FP9g9
```

**STOP. Esperar feedback antes de Fase 4.**

---

### Fase 4 — Visibilidad y accountability

**Objetivo**: hacer visible en la UI cuándo una venta/payment se creó
bajo delegación, y agregar KPI mensual al dashboard del admin.

#### Archivos a tocar

1. **Editar** `lib/features/sales/presentation/widgets/sale_card.dart`
   (o el equivalente):
   - Si la venta tiene algún payment con `createdViaDelegation: true`,
     mostrar badge pequeño "⚠️ Delegación" en la card.
   - Reusar estilo de badges existentes.

2. **Editar** `lib/features/sales/presentation/sale_detail_screen.dart`:
   - En la sección de pagos, marcar visualmente los que tienen
     `createdViaDelegation: true` (chip "Bajo delegación" o ícono).

3. **Editar** `lib/features/admin/data/metrics.dart`:
   - Agregar campo a `SalesMetrics`: `int paymentsViaDelegationCount` y
     `num paymentsViaDelegationAmount`.
   - Calcular en `SalesMetrics.compute` filtrando los payments del rango
     con el flag.
   - Sumar a `SalesMetrics.empty()`.

4. **Editar** `lib/features/admin/presentation/admin_metrics_screen.dart`:
   - Agregar KPI en alguna `KpiRow` (sección de operación o nueva sección
     "Excepciones"):
     - "Pagos bajo delegación (mes)" con count + monto
     - Tap → navega a `/admin/delegation/payments` (drill-down)

5. **Crear** `lib/features/admin/presentation/payments_via_delegation_screen.dart`:
   - Lista filtrada del collection group `payments` con `createdViaDelegation: true`
     en el rango configurable (default mes actual).
   - Cada item: consecutivo venta, payer, sales que registró, monto, fecha, link al detalle de venta.
   - `RangeFilterBar` arriba.
   - Export xlsx opcional (reusar `xlsx_export_service`).

6. **Editar** `lib/core/routing/app_router.dart`:
   - Agregar ruta `/admin/delegation/payments`.

#### Tests Fase 4

- [ ] `flutter analyze` 0 errores.
- [ ] Crear varios payments bajo delegación en distintos días.
- [ ] Verificar badge en cards de sales.
- [ ] Verificar chip en sale detail.
- [ ] Login admin, ver KPI en metrics.
- [ ] Tap → drill-down funciona y lista coincide.
- [ ] Filtrar por rango cambia el conteo.

#### Rollback Fase 4

Revertir los commits. Funcionalidad cosmética, sin impacto en datos.

#### Commit

```
git add lib/features/admin/ lib/features/sales/presentation/ lib/core/routing/
git commit -m "Modo delegación caja — Fase 4: badges en cards, chip en detalle, KPI y drill-down en admin"
git push origin claude/check-system-status-FP9g9
```

---

## 6. Edge cases — resolución específica

| Edge case | Resolución |
|---|---|
| Doc `settings/sales_delegation` no existe nunca | Stream emite `SalesDelegation.inactive()`. UI trata como off. |
| Admin activa con `expiresIn: null` y nunca desactiva | Queda activa permanentemente. Banner global persistente. KPI cuenta los pagos. Se asume disciplina del admin. |
| Admin activa, expira sola, admin nunca entra a la pantalla | El bool en backend queda en `true` pero `isCurrentlyActive` derivado en cliente lo trata como false. Rules también. Sin efecto operativo. Cuando admin entre, ve "Expirada el X" y puede limpiar (set `active: false`). |
| Dos admins activan al mismo tiempo | Last-write-wins. La 2da activación sobrescribe `activatedBy/At/expiresAt`. Ambas entries quedan en history. |
| Admin activa, otro admin desactiva 1 min después | Ambas operaciones quedan en history. Aceptable. |
| Reloj cliente ≠ reloj server | `expiresAt` se chequea en cliente con `DateTime.now()`. Si el reloj cliente está adelantado, sales no ve los campos aunque la regla del server los permitiría (más restrictivo, OK). Si está atrasado, sales ve los campos pero el server rechaza al submit (friendly error). |
| Sales en native offline, crea venta+payment bajo delegación, vuelve online y delegación expiró | Firestore SDK reintenta. Server rechaza el payment write. ¿Y el sale? Si la transacción es atómica, el sale tampoco se crea. **Verificar este comportamiento**. Si el transaction se rechaza completo, sales ve error al volver online. Si solo el payment se rechaza pero sale se crea, hay inconsistencia. **Implementar como una sola transacción server-side donde ambos writes están en el mismo `runTransaction`**. |
| Sales abre 2 forms a la vez (web, multitab) y delegación se desactiva entre uno y otro | Cada tab tiene su propio provider listening. Ambos reaccionan al cambio. Sin race condition aparente. |
| Admin activa con duración inválida (negativa, gigante) | Validación cliente en el modal: max 24h, mínimo 1h cuando se elige timer. Defensivo, no crítico. |
| Sales submit, server demora, mientras tanto delegación se desactiva | El write ya está en flight. Si llega al server con delegación activa, OK. Si llega después, rechazo. Edge muy raro, friendly error suficiente. |
| Notif `delegation_activated` se envía a admin actor también | Filtrar en el `emitInTxn` para excluir al `actor.uid` del `targetUids`. Mejor UX. |
| Si Fase 9B (`audit_log`) se implementa en el futuro | El history append-only de este plan se puede deprecar a favor del audit_log. Por ahora son independientes. |

---

## 7. Checklist final de validación (pre-release)

Antes de considerar "terminado" después de Fase 4:

### Regresión (lo que ya andaba debe seguir andando)
- [ ] Sales sin delegación crea venta como antes (sin campos de pago)
- [ ] Sales sin delegación edita venta dentro de 24h
- [ ] Cajero registra abono normal (sin delegación)
- [ ] Cajero registra abono con delegación on (no debería notar diferencia)
- [ ] Admin registra abono
- [ ] Admin anula abono normal
- [ ] Cajero procesa venta
- [ ] Cajero cancela venta
- [ ] Cajero marca pérdida
- [ ] Auditor ve su dashboard filtrado
- [ ] Hours user abre/cierra turno
- [ ] Listas maestras editables
- [ ] Métricas existentes coinciden con periodo previo

### Funcionalidad nueva
- [ ] Admin activa delegación con 4h + nota → doc en Firestore correcto
- [ ] Admin desactiva → doc actualizado, history append
- [ ] Sales con delegación activa ve campos en form
- [ ] Sales crea sale+payment bajo delegación → transacción atómica, ambos docs creados
- [ ] Sales con delegación on puede crear venta SIN llenar pago
- [ ] Banner global aparece en todos los roles
- [ ] Notifs llegan a admin+cajero (activación, desactivación, payment recorded)
- [ ] Badge "Bajo delegación" en cards de venta
- [ ] Chip "Bajo delegación" en detalle de venta
- [ ] KPI en dashboard admin coincide con count real
- [ ] Drill-down lista los payments correctos
- [ ] Export xlsx incluye flag de delegación
- [ ] Expiración cosmética: si `expiresAt < now`, banner desaparece automáticamente

### Documentación
- [ ] `docs/data-model.md` actualizado con `settings/sales_delegation` y campo nuevo en payment
- [ ] `docs/workflows.md` agrega receta "Cómo usar el modo delegación caja" (admin operativo)
- [ ] `CHANGELOG.md` con entry "Agregado — modo delegación caja para excepciones cuando admin/cajero no está disponible"
- [ ] `CLAUDE.md` actualizado si introduce alguna regla nueva (probablemente no)
- [ ] `pubspec.yaml` bump a `1.4.0+14`
- [ ] Tag opcional `v1.4.0`

---

## 8. Out of scope (explícito, NO implementar)

- Push notifications del SO (FCM/APNs). Las notifs son in-app.
- Edición de payment desde sales (sigue siendo admin-only delete + recreate).
- Permitir a sales agregar pago a una venta existente bajo delegación.
- Audit log completo (eso es Fase 9B del `plan_fase_9.md`).
- Granularidad por usuario (delegar a sales específico). Si en el futuro
  hay >1 sales, evaluar.
- Auto-expiración del bool con Cloud Functions. Mientras no haya backend
  custom, el chequeo en rules es suficiente.
- UI para que sales VEA si delegación está activa antes de abrir el form.
  El banner global cubre esto.

---

## 9. Mejoras post-MVP (opcionales, no en este plan)

- KPI semanal/diario en home de admin "veces activada esta semana".
- Plantillas de duración personalizadas (admin define defaults).
- Notif al admin 15 min antes de que la delegación expire.
- Cuando expira sola, banner cambia color (amarillo → gris) hasta que admin la limpie.
- Reabrir delegación rápido con un toggle persistente en el menú admin.

---

## 10. Si algo no encaja con la realidad del repo

Si al ejecutar este plan descubrís que algún archivo/método/widget que
referenciamos NO existe con ese nombre exacto, **no inventés**. Hacé:

1. `grep` por el nombre supuesto en `lib/`.
2. Si encontrás algo equivalente con otro nombre, usalo y notalo en el commit.
3. Si no encontrás nada, parar y reportar al usuario antes de inventar la estructura.

Este doc fue escrito con conocimiento de los docs del repo a la fecha
2026-05-24. Si el repo cambió después, partes pueden estar
desactualizadas. **Verificá primero, ejecutá segundo.**
