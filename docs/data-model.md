# Modelo de datos

Schema completo de Firestore. Si agregás/cambiás un campo, actualizá
este doc y `firestore.rules`.

## Colecciones

### `users/{uid}`

`AppUser` — vive una vez por usuario autenticado.

| Campo         | Tipo        | Descripción                                           |
|---------------|-------------|-------------------------------------------------------|
| `username`    | String      | Único, sin `@cqg.app`. Lo que el usuario tipea al login. |
| `fullName`    | String      | Nombre completo para mostrar en UI.                   |
| `role`        | String enum | `'admin' \| 'sales' \| 'hours' \| 'cajero' \| 'auditor'`. |
| `active`      | bool        | Si `false`, no puede iniciar sesión.                  |
| `auditFilter` | Map?        | Solo para rol `auditor`. `{ field: String, value: String }`. |
| `createdAt`   | Timestamp   | Cuándo se creó el doc.                                |

Reglas:
- Lee: el propio usuario o `admin`.
- Escribe: solo `admin`.

### `workers/{id}`

`Worker` — trabajadores operativos. Pueden tener turnos abiertos en `hours_entries`.

| Campo          | Tipo      | Notas                                  |
|----------------|-----------|----------------------------------------|
| `fullName`     | String    |                                        |
| `documentNumber` | String  | Cédula.                                |
| `role`         | String    | De la lista maestra `worker_roles`.    |
| `bank`         | String?   | Banco para pago.                        |
| `bankAccount`  | String?   | Número de cuenta.                       |
| `phone`        | String?   |                                        |
| `active`       | bool      | Soft-delete: si `false`, no aparece en dropdowns. |
| `createdAt`    | Timestamp |                                        |

### `sales/{id}`

`Sale` — una venta registrada. Consecutivo generado atómicamente.

| Campo                  | Tipo       | Notas                                  |
|------------------------|------------|----------------------------------------|
| `consecutive`          | String     | `CQG-001`, `CQG-002`, …                 |
| `date`                 | Timestamp  | Fecha comercial de la venta.            |
| `documentType`         | String     | `'Cédula'` o `'NIT'`.                   |
| `documentNumber`       | String     |                                        |
| `providerName`         | String     | Cliente. De `providers` (puede ser libre). |
| `items`                | List<Map>  | Items de material de la venta. Cada item: `{material, materialVariant?, unit, quantity, unitPrice}`. Siempre tiene al menos uno. |
| `material`             | String     | Mirror de `items[0].material`. Conservado para queries indexadas (auditor) y retro-compat. |
| `materialVariant`      | String?    | Mirror de `items[0].materialVariant`.  |
| `unit`                 | String     | Mirror de `items[0].unit`.             |
| `quantity`             | num        | Mirror de `items[0].quantity`.         |
| `unitPrice`            | num        | Mirror de `items[0].unitPrice`.        |
| `totalValue`           | num        | Suma de `quantity * unitPrice` de todos los items. Recalculado al update. |
| `paymentMethod`        | String     | `'Efectivo' \| 'Transferencia' \| 'Mixto'`. Derivado de los montos. |
| `cashAmount`           | num?       | Monto en efectivo. Null si la venta es vieja o 100% transferencia. |
| `transferAmount`       | num?       | Monto por transferencia. Null si 100% efectivo o vieja. |
| `transferDestination`  | String?    | De `transfer_destinations`. Null si 100% efectivo. |
| `payerName`            | String     | "Quién recibe". De `payers`.           |
| `commissionAgent`      | String?    | Comisionista que trajo la venta. Null/ausente = venta directa de bodega. De la lista maestra `commission_agents` (estricta). Opcional; no afecta agregados financieros. Usado para el análisis "quién vende más". |
| `createdBy`            | String     | uid de quien la creó.                  |
| `createdByName`        | String     | Nombre cacheado para mostrar.          |
| `createdAt`            | Timestamp  |                                        |
| `updatedAt`            | Timestamp? |                                        |
| `editableUntil`        | Timestamp? | Se fija al crear (`createdAt + 24 h`) y NUNCA se reasigna en `updateSale`. Es la única ventana de edición para sales: dentro de las 24 h puede modificar campos del formulario sin importar el `state`. Después solo admin edita. |
| `customFields`         | Map        | _Deprecado._ Campo legacy del extinto constructor de formularios. No se lee ni se escribe desde el cliente; queda en docs históricos por compatibilidad. |
| `state`                | String enum | `'generada' \| 'en_proceso' \| 'procesada' \| 'cancelada'`. Workflow informativo para sales (¿puedo entregar?). Lo controla cajero. Default legacy: `procesada`. |
| `paidAmount`           | num        | Suma de abonos confirmados (denormalizado de la subcolección `payments`). |
| `lossAmount`           | num        | Saldo castigado contablemente. Absorbe el `financialStatus` a `lost`. |
| `outstandingBalance`   | num        | `totalValue - paidAmount - lossAmount`. Denormalizado para queries. |
| `financialStatus`      | String enum | `'pending' \| 'partiallyPaid' \| 'paid' \| 'lost'`. Derivado por `Sale.computeFinancialStatus`. |
| `creditDueDate`        | Timestamp? | Plazo opcional para cobrar. Si queda en el pasado, la deuda aparece como vencida. Sin lógica automática. |
| `processedBy`          | String?    | uid del cajero que confirmó como `procesada`.    |
| `processedByName`      | String?    | Nombre cacheado.                                 |
| `processedAt`          | Timestamp? |                                                  |
| `canceledBy` / `canceledByName` / `canceledAt` | String?/String?/Timestamp? | Trazabilidad de la cancelación. |
| `cancelReason`         | String?    | Razón obligatoria al cancelar.                   |
| `markedAsLossBy` / `markedAsLossByName` / `markedAsLossAt` | String?/String?/Timestamp? | Trazabilidad de "marcar saldo como pérdida". |
| `lossReason`           | String?    | Razón obligatoria al marcar pérdida.             |

**Backwards-compat**: ventas viejas no tienen `cashAmount`/`transferAmount`/`transferDestination`.
El modelo `Sale` los expone como `cashPortion` / `transferPortion` con
fallback inferido de `paymentMethod`.

**Items legacy:** ventas viejas tampoco tienen `items[]`. `Sale.fromSnapshot`
las interpreta como una venta con un único item construido desde los
campos `material`/`materialVariant`/`unit`/`quantity`/`unitPrice` top-level.
No hay script de migración — el fallback in-place alcanza, y al editar
desde el form se escriben los items[] junto con el mirror del primero.

Las ventas viejas tampoco tienen `state` ni los campos financieros
nuevos. `Sale.fromSnapshot` las interpreta como `state: procesada`,
`paidAmount: totalValue`, `outstandingBalance: 0`, `financialStatus: paid`.
No hay script de migración — el fallback in-place alcanza.

Reglas:
- Lee: `admin`, `sales`, `cajero`, `auditor`.
- Crea: `admin`, `sales`.
- Actualiza: `admin`, `cajero`. Sales solo puede editar sus propias
  ventas mientras esté dentro de la ventana fija de 24 h desde
  `createdAt` (el state ya no influye).
- Borra: solo `admin`.

#### `sales/{id}/payments/{paymentId}`

`SalePayment` — abonos parciales contra una venta. La creación de un
payment + actualización de agregados del padre (`paidAmount`,
`outstandingBalance`, `financialStatus`) va siempre en un
`runTransaction` para mantener la consistencia.

| Campo                  | Tipo       | Notas                                  |
|------------------------|------------|----------------------------------------|
| `amount`               | num        | Total del abono. Debe ser > 0.         |
| `paymentMethod`        | String     | `'Efectivo' \| 'Transferencia' \| 'Mixto'`. |
| `cashAmount`           | num?       | Componente efectivo (si aplica).       |
| `transferAmount`       | num?       | Componente transferencia (si aplica).  |
| `transferDestination`  | String?    | Banco/billetera, requerido si `transferAmount > 0`. |
| `payerName`            | String?    | Quién en caja recibió el abono. Lista maestra `payers`. |
| `registeredBy`         | String     | uid del cajero/admin que lo registró.  |
| `registeredByName`     | String     | Nombre cacheado.                       |
| `registeredAt`         | Timestamp  |                                        |
| `notes`                | String?    | Notas opcionales del cajero.           |

Reglas:
- Lee/crea: `admin`, `cajero`. Create exige `amount > 0`.
- Update: nadie (corregir un abono se hace borrando y registrando uno nuevo).
- Borra: solo `admin` (anula el pago y recalcula los agregados).
- Collection group: el dashboard de admin hace `collectionGroup('payments')`
  con un `where('registeredAt', ...)` para agregar el desglose por
  método de pago real. Firestore necesita dos cosas extra para que
  funcione: una regla con wildcard
  `match /{path=**}/payments/{pid} { allow read: ... }` y un índice
  single-field con scope `COLLECTION_GROUP` sobre `registeredAt`
  (declarado via `fieldOverrides` en `firestore.indexes.json`, no
  via `indexes[]` — la CLI rechaza single-field indexes ahí).

### `hours_entries/{id}`

`HoursEntry` — un día de un trabajador. Generado al abrir/cerrar turno.

| Campo            | Tipo       | Notas                                  |
|------------------|------------|----------------------------------------|
| `workerId`       | String     | Doc id en `workers`.                   |
| `workerName`     | String     | Cacheado.                              |
| `date`           | Timestamp  | Fecha del día (00:00).                 |
| `checkIn`        | Timestamp  |                                        |
| `checkOut`       | Timestamp? | Null si el turno sigue abierto.        |
| `breakdown`      | Map        | Resultado de `HoursCalculator`: claves = categorías (`ordinary`, `extraDay`, ...) → minutos. |
| `notes`          | String?    |                                        |
| `editableUntil`  | Timestamp? | Igual que sales — 24h después de cerrar. |
| `createdBy`      | String     |                                        |
| `createdByName`  | String     |                                        |
| `createdAt`      | Timestamp  |                                        |
| `updatedAt`      | Timestamp? |                                        |

Reglas:
- Lee/crea/actualiza: `admin`, `hours`.
- Borra: solo `admin`.

### `master_lists/{listId}`

`MasterList` — metadata de una lista maestra.

| Campo           | Tipo    | Notas                                   |
|-----------------|---------|-----------------------------------------|
| `name`          | String  | Display name.                           |
| `description`   | String? |                                         |
| `allowFreeText` | bool    | Si `true`, el field permite captura libre. |

Reglas: lee cualquiera autenticado, escribe solo admin.

#### `master_lists/{listId}/items/{itemId}`

`MasterListItem` — opciones de la lista.

| Campo           | Tipo    | Notas                                   |
|-----------------|---------|-----------------------------------------|
| `value`         | String  | Lo que ve el usuario.                   |
| `parent`        | String? | Para listas jerárquicas (ej. `lamina_brands` con parent = material). |
| `active`        | bool    | Soft-delete.                            |
| `userSuggested` | bool    | `true` si fue creado por un no-admin. Admin lo aprueba editándolo (queda en `false`). |
| `metadata`      | Map     | Extras opcionales.                      |

Reglas:
- Lee: cualquiera autenticado.
- Crea: admin, o cualquier autenticado **solo con `userSuggested: true`**.
- Update/delete: solo admin.

#### Listas maestras existentes (seed)

| listId                  | Display name             | Free text | Notas                                      |
|-------------------------|--------------------------|-----------|--------------------------------------------|
| `providers`             | Clientes                 | sí        | También la usa `material_entries.clientName` (salidas de material) — reusada a propósito, no se duplicó el catálogo. |
| `payers`                | Quién recibe             | sí        |                                            |
| `commission_agents`     | Comisionistas            | no        | Estricta: solo el admin gestiona. Vacío en venta = bodega. |
| `materials`             | Materiales               | sí        | LAMINA, CHATARRA, CHATARRA TUBERIA         |
| `lamina_brands`         | Tipos de materiales      | sí        | Items con `parent` = material. ListId histórico, no renombrar. |
| `payment_methods`       | Métodos de pago          | no        | Efectivo, Transferencia, Mixto             |
| `transfer_destinations` | Destinos de transferencia| sí        | Bancolombia, Nequi, Daviplata, …           |
| `units`                 | Unidades de medida       | no        | Kilogramos                                 |
| `worker_roles`          | Cargos de trabajadores   | sí        |                                            |
| `material_providers`    | Proveedores de material  | sí        | Empresas de las que se compra material (control de ingreso). Separada de `providers` a propósito — ahí significa "Clientes" (a quién se le vende). |

#### Mapping `listId` → campo de Sale

En `master_lists_repository.dart` (`_saleFieldByListId`). Define qué
listas afectan ventas históricas cuando el admin renombra un item.

| listId                  | Campo en Sale          |
|-------------------------|------------------------|
| `payers`                | `payerName`            |
| `commission_agents`     | `commissionAgent`      |
| `providers`             | `providerName`         |
| `materials`             | `material`             |
| `lamina_brands`         | `materialVariant`      |
| `units`                 | `unit`                 |
| `payment_methods`       | `paymentMethod`        |
| `transfer_destinations` | `transferDestination`  |

`worker_roles` no está acá porque afecta `workers`, no `sales`.
`material_providers` tampoco — afecta `material_entries.providerName`
(ver `_propagationByListId` en `master_lists_repository.dart`, que ya
generalizó este mapping a "colección + campo" en vez de asumir
siempre `sales`). `providers` sí tiene un `secondaries` extra ahí que
propaga también a `material_entries.clientName`.

### `material_entries/{id}`

`MaterialEntry` — control de ingreso Y salida de material, ambos
**totalmente independientes de `sales`** (decisión explícita de
Carlos: la salida física de bodega no es la venta comercial, aunque en
la práctica muchas veces coincidan). Ambos tipos viven en la misma
colección, distinguidos por `type`. Consecutivo `ING-XXX` (ingreso) o
`SAL-XXX` (salida) generado atómicamente — cada tipo tiene su propio
contador (`counters/material_entries_consecutive` y
`counters/material_exits_consecutive`), mismo patrón que
`Sale.consecutive`.

| Campo                 | Tipo       | Notas                                  |
|-----------------------|------------|-----------------------------------------|
| `consecutive`         | String     | `ING-001…` o `SAL-001…` según `type`.   |
| `type`                | String enum | `'ingreso' \| 'salida'`.                |
| `date`                | Timestamp  | Fecha del movimiento.                   |
| `material`            | String     | De la lista maestra `materials` (compartida con ventas). |
| `materialVariant`     | String?    | De `lamina_brands`, opcional.           |
| `quantity`            | num        |                                          |
| `unit`                | String     | De la lista maestra `units`.            |
| `providerName`        | String?    | Solo `type == 'ingreso'`. Empresa proveedora, de `material_providers` (lista nueva, separada de `providers`). |
| `clientName`          | String?    | Solo `type == 'salida'`. Empresa cliente/destino — **reusa** la lista maestra `providers` (la misma "Clientes" de Ventas; decisión explícita para no duplicar el catálogo). |
| `originDescription`   | String?    | Texto libre: de dónde viene (ingreso) o hacia dónde va (salida), ej. "Barranquilla — Recicladora XYZ". |
| `vehicleRef`          | String?    | Placa o número de vagón, opcional.      |
| `materialPhotoUrl`    | String     | Requerida. Foto del material/vagón, sube a Storage antes del write. |
| `originPhotoUrl`      | String?    | Opcional. Foto de procedencia (ingreso) o destino (salida). |
| `notes`               | String?    |                                          |
| `createdBy` / `createdByName` / `createdAt` | | Igual que `Sale`.        |
| `updatedAt`           | Timestamp? |                                          |
| `editableUntil`       | Timestamp? | `createdAt + 24h`, mismo patrón que sales/hours. |

`MaterialEntry.counterpartyName` (getter, no persistido) devuelve
`providerName` o `clientName` según el `type` — lo usan el dashboard y
el correo para no tener que ramificar en cada lugar que agrega "por
empresa".

**Fotos y Storage:** suben a
`material_entries/{entryId}/{material\|origin}.jpg` vía
`FirebaseStorage`, comprimidas en origen
(`ImagePicker(imageQuality: 70, maxWidth: 1600)`). La `entryId` se
genera en cliente (`_col.doc()`, sin escribir todavía) para poder subir
las fotos ANTES de crear el doc y así conocer sus URLs. Las
`getDownloadURL()` de Firebase Storage llevan un token embebido que
**no requiere sesión** para visualizarse — es justamente lo que
permite incrustarlas en el correo a gerencia (ver `mail/{id}` abajo).
No hay cola offline para fotos: si falla la subida, el submit falla
con mensaje claro y hay que reintentar con conexión.

Reglas:
- Lee/crea: `admin`, `hours`. Create exige `type in ['ingreso', 'salida']`
  y que `materialPhotoUrl`/`originPhotoUrl` sean download URLs reales de
  Storage (`firebasestorage.googleapis.com/...`) — sin esto, alguien con
  acceso a la API cruda (no el formulario) podría meter un string
  arbitrario ahí, que termina en el `<img src>` del correo a gerencia.
- Actualiza: `admin` siempre; `hours` solo su propio doc dentro de
  `editableUntil`. `type` y `consecutive` son inmutables en cualquier
  update (el consecutivo ING-/SAL- ya codifica el tipo).
- Borra: solo `admin`.
- `storage.rules` (archivo nuevo en la raíz del repo) es más simple de
  lo que sería ideal: solo exige sesión autenticada (sin distinguir
  rol) para leer/crear/actualizar, más límite 10MB y `contentType`
  `image/*` para crear/actualizar. **Se intentó** atar esto al mismo
  criterio de rol + dueño/ventana de 24h que usa Firestore, consultando
  `material_entries/{entryId}` vía la función cross-service
  `firestore.get()`/`firestore.exists()` — compila sin error, pero en
  la práctica (probado con uploads reales vía la API REST de Storage)
  siempre devuelve `permission-denied`, incluso en el caso más simple.
  No se identificó la causa exacta; ver el comentario largo al principio
  de `storage.rules` antes de reintentarlo. El control de acceso real
  por rol sigue viviendo en `firestore.rules` (`material_entries` solo
  admin/hours) — el `entryId` en el path de Storage es un id de
  Firestore autogenerado (~20 caracteres al azar), no adivinable.

### `mail/{id}`

Colección que consume la extensión oficial de Firebase
**`firestore-send-email`** (instalada y configurada por el usuario —
no es Cloud Functions propias, ver `docs/architecture.md`). Un doc acá
= un correo en cola. `MaterialEntriesRepository.createEntry` escribe
uno **DESPUÉS** de la transacción que crea el movimiento (a propósito
fuera de ella, en un try/catch silencioso) solo si
`settings/material_notifications.recipientEmails` no está vacío. El
correo es de mejor esfuerzo — si falla, el ingreso/salida ya quedó
guardado y gerencia igual se entera por la notificación in-app (esa sí
va dentro de la transacción, porque es barata y siempre debe reflejar
lo que realmente se guardó).

| Campo             | Tipo   | Notas                                  |
|--------------------|--------|-----------------------------------------|
| `to`               | List<String> | Destinatarios. La regla exige que sea subconjunto de `settings/material_notifications.recipientEmails` — nadie puede mandar a una dirección arbitraria vía la API cruda. |
| `message.subject`  | String | Asunto.                                 |
| `message.html`     | String | Cuerpo con el resumen + `<img>` a las fotos (download URLs de Storage). |

Reglas: `create` para `admin`/`hours` con
`keys().hasOnly(['to','message'])`, `to` no vacío y subconjunto de los
destinatarios configurados, y `message.subject`/`message.html` como
`String`. `read`/`update`/`delete`: nadie desde el cliente — la
extensión gestiona el estado de envío con
privilegios de admin, fuera de estas rules.

### `settings/material_notifications`

Doc singleton admin-only: a quién le llega el correo de "nuevo
ingreso de material".

| Campo             | Tipo         | Notas                              |
|--------------------|--------------|-------------------------------------|
| `recipientEmails`  | List<String> | Si está vacía, no se envía ningún correo (el resto del flujo sigue igual). |

Reglas: cubierto por la regla genérica `settings/{sid}` (lee cualquier
autenticado, escribe solo admin) — no requiere match propio.

### `counters/sales_consecutive`

Contador atómico para el consecutivo de ventas.

| Campo  | Tipo | Notas                                  |
|--------|------|----------------------------------------|
| `value`| int  | Último consecutivo emitido (no el siguiente). |

Acceso solo via `runTransaction` desde `SalesRepository.createSale`.

Reglas: lee/escribe `admin`, `sales`.

### `counters/material_entries_consecutive` y `counters/material_exits_consecutive`

Contadores atómicos para los consecutivos `ING-XXX` (ingreso) y
`SAL-XXX` (salida) — uno por tipo, para que la numeración de cada uno
no se mezcle. Mismo patrón que `sales_consecutive`, acceso solo via
`runTransaction` desde `MaterialEntriesRepository.createEntry`.

Reglas: `counters/{cid}` es genérico — lee/escribe `admin`, `sales`,
`hours`.

### `notifications/{id}`

`AppNotification` — un aviso in-app. Colección plana, con dos arrays de
targets (uid y/o rol). El cliente hace **dos queries paralelas**
(`targetUids array-contains uid` y `targetRoles array-contains role`)
y mergea + dedup en memoria, porque Firestore no permite OR en `where`.

| Campo            | Tipo            | Notas                                  |
|------------------|-----------------|----------------------------------------|
| `type`           | String enum     | `'sale_created' \| 'sale_processed' \| 'sale_canceled' \| 'sale_returned_to_sales' \| 'sale_marked_loss' \| 'payment_voided' \| 'material_entry_created'` (y los tipos de delegación caja). |
| `title`          | String          | Encabezado corto ("Solicitud procesada"). |
| `body`           | String          | Cuerpo ("CQG-123 — Cliente X, $1.500.000"). |
| `saleId`         | String?         | Venta asociada. Si está, tap navega al recurso. |
| `createdAt`      | Timestamp       |                                        |
| `createdBy`      | String          | uid del actor que disparó el evento.   |
| `createdByName`  | String          | Nombre cacheado.                       |
| `targetUids`     | List<String>    | uids específicos que reciben la notif. |
| `targetRoles`    | List<String>    | Roles que reciben la notif (`'cajero'`, `'admin'`, etc.). |
| `readBy`         | List<String>    | uids que ya marcaron como leída.       |
| `data`           | Map?            | Payload extra para navegación/agrupación. |

Reglas:
- Lee: solo si el usuario está en `targetUids` o su rol está en `targetRoles`.
- Crea: cualquier autenticado, exigiendo `createdBy == request.auth.uid`
  (anti-suplantación). Los emisores reales son los repos de sales y
  cashier dentro de su `runTransaction`.
- Update: solo el target user, y solo el campo `readBy`
  (`diff().affectedKeys().hasOnly(['readBy'])`). No se puede editar el
  contenido — para anular una notif se borra.
- Borra: solo admin (cleanup manual; no hay TTL).

**Recorte visual a 30 días:** el repo filtra en memoria. Las notifs más
viejas siguen en backend pero el sheet no las muestra.

**Agrupación visual:** notifs consecutivas del mismo `type` en un bucket
de 1h se colapsan en un solo item expandible (cada notif se persiste
por separado; la dedup es solo UI).

### `settings/work_schedule`

`WorkSchedule` — configuración de jornada laboral.

| Campo                 | Tipo  | Notas                              |
|-----------------------|-------|------------------------------------|
| `weekdayStart`        | String| `'07:00'`                          |
| `weekdayEnd`          | String| `'16:00'`                          |
| `saturdayStart`       | String| `'07:00'`                          |
| `saturdayEnd`         | String| `'11:00'`                          |
| `sundayStart`         | String| `'07:00'`                          |
| `sundayEnd`           | String| `'16:00'`                          |
| `lunchStart`          | String| `'12:00'`                          |
| `lunchEnd`            | String| `'13:00'`                          |
| `dayStart`            | String| `'06:00'` — frontera diurno/nocturno. |
| `dayEnd`              | String| `'19:00'`                          |

Reglas: lee cualquiera autenticado, escribe solo admin.

### `settings/cash_register`

`CashRegister` — estado runtime de la caja (cierre de caja). Singleton.
Si el doc no existe, equivale a caja cerrada.

| Campo               | Tipo       | Notas                                            |
|---------------------|------------|--------------------------------------------------|
| `isOpen`            | bool       | `true` mientras hay un turno abierto.            |
| `openShiftId`       | String?    | Id del doc en `cash_shifts` abierto. Null si cerrada. |
| `openedBy` / `openedByName` | String? | Quién abrió el turno vigente.               |
| `openedAt`          | Timestamp? | Cuándo se abrió.                                 |
| `openingFloat`      | num?       | Base inicial declarada al abrir.                 |
| `periodStart`       | Timestamp? | Inicio de la **ventana contigua** del turno = `lastClosedAt` del cierre anterior (o `openedAt` si es el primero). Todo lo cobrado en `(periodStart, closedAt]` entra al cierre — nada se pierde aunque se cierre temprano/tarde o cruce la medianoche. |
| `lastClosedAt`      | Timestamp? | `closedAt` del último cierre. Semilla del `periodStart` de la próxima apertura. |
| `lastRemainingCash` | num?       | `remainingCash` del último cierre. Precarga la base del próximo turno. |

Reglas:
- Lee: cualquier autenticado (el banner global "caja abierta" se muestra
  en todos los roles).
- Escribe: `admin` y `cajero`. El `match` específico SUMA write a cajero
  por encima del genérico `settings/{sid}` (que solo da write a admin).

### `settings/cash_register_config`

`CashRegisterConfig` — configuración del cierre de caja. Singleton
admin-only. Lazy default si no existe.

| Campo         | Tipo   | Notas                                              |
|---------------|--------|----------------------------------------------------|
| `closingTime` | String | Hora de cierre sugerida `'HH:mm'` (24h). Default `'18:00'`. Es solo un **recordatorio** operativo, NO la frontera del dinero (esa la define `periodStart`/`closedAt`). |

Reglas: lee cualquiera autenticado, escribe solo admin (regla genérica
`settings/{sid}` — no tiene match propio).

### `cash_shifts/{shiftId}`

`CashShift` — ledger append-only de turnos de caja. Id autogenerado (un
doc por turno). Se crea con `status: open` y se actualiza una sola vez a
`status: closed` con el arqueo. Una vez cerrado es **inmutable**: si luego
se anula un payment de su ventana, este doc NO cambia (el ajuste se ve en
reportes en vivo). Sin migración — no hay docs históricos.

| Campo                       | Tipo       | Notas                                  |
|-----------------------------|------------|----------------------------------------|
| `status`                    | String enum | `'open'` \| `'closed'`.               |
| `businessDate`              | String     | Etiqueta legible `YYYY-MM-DD` (por defecto el día de apertura, editable al cerrar). Solo display/orden; la ventana del dinero no depende de ella. |
| `openedBy` / `openedByName` | String     | Quién abrió.                           |
| `openedAt`                  | Timestamp  | Apertura.                              |
| `openingFloat`              | num        | Base inicial.                          |
| `periodStart`               | Timestamp  | Inicio de la ventana del dinero (cierre anterior o `openedAt`). |
| `closedBy` / `closedByName` | String?    | Quién cerró. Null mientras `open`.     |
| `closedAt`                  | Timestamp? | Cierre = fin de la ventana. Null mientras `open`. |
| `expectedCash`              | num?       | `openingFloat` + Σ efectivo de payments en la ventana. Congelado al cerrar. |
| `countedCash`               | num?       | Efectivo físico contado.               |
| `cashDiscrepancy`           | num?       | `countedCash - expectedCash`.          |
| `cashDiscrepancyReason`     | String?    | Obligatoria si `cashDiscrepancy != 0`. |
| `expectedTransfer`          | num?       | Σ transferencias de payments en la ventana. Congelado. |
| `confirmedTransfer`         | num?       | Transferencias confirmadas.            |
| `transferDiscrepancy`       | num?       | `confirmedTransfer - expectedTransfer`. |
| `transferDiscrepancyReason` | String?    | Obligatoria si `transferDiscrepancy != 0`. |
| `preOpenReceived`           | num?       | Informativo: dinero recibido en `(periodStart, openedAt)` (caja estuvo cerrada). |
| `withdrawalAmount`          | num?       | Retiro/consignación opcional al cerrar. |
| `remainingCash`             | num?       | `countedCash - (withdrawalAmount ?? 0)`. Precarga la base del próximo turno. |
| `paymentsCount`             | int?       | Cantidad de payments incluidos en la ventana. |
| `note`                      | String?    | Nota libre.                            |

El esperado se calcula con un `collectionGroup('payments')` filtrado por
`registeredAt` en `(periodStart, until]` (mismo criterio de método que
`SalesMetrics.compute`; reusa el índice `COLLECTION_GROUP` existente).

Reglas:
- Lee: `admin`, `cajero`. (No sales, no auditor.)
- Crea: `admin`, `cajero`, exigiendo `status == 'open'`.
- Actualiza: `admin`, `cajero`, solo mientras `resource.data.status == 'open'`
  (cerrar es el único update; un cerrado queda inmutable).
- Borra: solo `admin`.

## Índices compuestos

En `firestore.indexes.json`. Generamos lo mínimo. Patrón actual:
filtrar `.where('date', ...)` por rango + `.orderBy('date', desc)` ya
funciona con índice automático. Cuando agregamos `.where('field', ...)`
+ orderBy, Firestore pide un índice compuesto — el log de la consola
da link directo a crearlo.

**Tip**: para evitar índices extra, **filtramos en memoria** sobre
resultados de queries simples cuando el volumen es bajo (<10K docs).
Ej. el dashboard de auditor: `watchByField('materialVariant', 'PEDRO')`
trae todas las ventas que matcheen y el rango se aplica con `.where()`
en Dart.

## Relaciones

```
users.uid ──┬─── sales.createdBy
            ├─── hours_entries.createdBy
            ├─── material_entries.createdBy
            └─── (auditFilter referencia indirecta)

workers.id ──── hours_entries.workerId

master_lists/{listId}/items/{itemId}.value
    └── referenciado por VALOR (no por id) en:
        sales.providerName  (listId = providers)
        sales.payerName     (listId = payers)
        sales.commissionAgent (listId = commission_agents)
        sales.material      (listId = materials)
        sales.materialVariant (listId = lamina_brands, con parent = material)
        sales.unit          (listId = units)
        sales.paymentMethod (listId = payment_methods)
        sales.transferDestination (listId = transfer_destinations)
        workers.role        (listId = worker_roles)
        material_entries.providerName (listId = material_providers)
        material_entries.clientName   (listId = providers, compartida con sales)
        material_entries.material      (listId = materials, compartida con sales)
        material_entries.materialVariant (listId = lamina_brands)
        material_entries.unit          (listId = units, compartida con sales)
```

Las referencias son por **valor de string**, no por doc id. Eso es lo
que hace que `renameItem` tenga que batch-update todas las sales que
referenciaban el value viejo (ver `master_lists_repository.dart`).
