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
| `role`        | String enum | `'admin' \| 'sales' \| 'hours' \| 'auditor'`.         |
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
| `material`             | String     | De `materials`.                        |
| `materialVariant`      | String?    | De `lamina_brands` filtrado por material parent. Solo si el material tiene subtipos. |
| `unit`                 | String     | De `units`. Default `Kilogramos`.      |
| `quantity`             | num        |                                        |
| `unitPrice`            | num        |                                        |
| `totalValue`           | num        | `quantity * unitPrice`. Recalculado en server side al update. |
| `paymentMethod`        | String     | `'Efectivo' \| 'Transferencia' \| 'Mixto'`. Derivado de los montos. |
| `cashAmount`           | num?       | Monto en efectivo. Null si la venta es vieja o 100% transferencia. |
| `transferAmount`       | num?       | Monto por transferencia. Null si 100% efectivo o vieja. |
| `transferDestination`  | String?    | De `transfer_destinations`. Null si 100% efectivo. |
| `payerName`            | String     | "Quién recibe". De `payers`.           |
| `createdBy`            | String     | uid de quien la creó.                  |
| `createdByName`        | String     | Nombre cacheado para mostrar.          |
| `createdAt`            | Timestamp  |                                        |
| `updatedAt`            | Timestamp? |                                        |
| `editableUntil`        | Timestamp? | 24h después de createdAt. Después solo admin edita. |
| `customFields`         | Map        | Campos extra definidos por el admin en form builder. |

**Backwards-compat**: ventas viejas no tienen `cashAmount`/`transferAmount`/`transferDestination`.
El modelo `Sale` los expone como `cashPortion` / `transferPortion` con
fallback inferido de `paymentMethod`.

Reglas:
- Lee: `admin`, `sales`, `auditor`.
- Crea/actualiza: `admin`, `sales`.
- Borra: solo `admin`.

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
| `providers`             | Clientes                 | sí        |                                            |
| `payers`                | Quién recibe             | sí        |                                            |
| `materials`             | Materiales               | sí        | LAMINA, CHATARRA, CHATARRA TUBERIA         |
| `lamina_brands`         | Tipos de materiales      | sí        | Items con `parent` = material. ListId histórico, no renombrar. |
| `payment_methods`       | Métodos de pago          | no        | Efectivo, Transferencia, Mixto             |
| `transfer_destinations` | Destinos de transferencia| sí        | Bancolombia, Nequi, Daviplata, …           |
| `units`                 | Unidades de medida       | no        | Kilogramos                                 |
| `worker_roles`          | Cargos de trabajadores   | sí        |                                            |

#### Mapping `listId` → campo de Sale

En `master_lists_repository.dart` (`_saleFieldByListId`). Define qué
listas afectan ventas históricas cuando el admin renombra un item.

| listId                  | Campo en Sale          |
|-------------------------|------------------------|
| `payers`                | `payerName`            |
| `providers`             | `providerName`         |
| `materials`             | `material`             |
| `lamina_brands`         | `materialVariant`      |
| `units`                 | `unit`                 |
| `payment_methods`       | `paymentMethod`        |
| `transfer_destinations` | `transferDestination`  |

`worker_roles` no está acá porque afecta `workers`, no `sales`.

### `form_schemas/{module}`

`FormSchema` — esquema dinámico de un módulo. Actualmente solo `'sales'`.

| Campo      | Tipo                | Notas                                  |
|------------|---------------------|----------------------------------------|
| `module`   | String              | `'sales'`.                             |
| `version`  | int                 | Se incrementa cada update.             |
| `fields`   | List<Map>           | Lista de `FieldDefinition` serializados. |
| `updatedAt`| Timestamp           |                                        |

Reglas: lee cualquiera autenticado, escribe solo admin.

### `counters/sales_consecutive`

Contador atómico para el consecutivo de ventas.

| Campo  | Tipo | Notas                                  |
|--------|------|----------------------------------------|
| `value`| int  | Último consecutivo emitido (no el siguiente). |

Acceso solo via `runTransaction` desde `SalesRepository.createSale`.

Reglas: lee/escribe `admin`, `sales`.

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
            └─── (auditFilter referencia indirecta)

workers.id ──── hours_entries.workerId

master_lists/{listId}/items/{itemId}.value
    └── referenciado por VALOR (no por id) en:
        sales.providerName  (listId = providers)
        sales.payerName     (listId = payers)
        sales.material      (listId = materials)
        sales.materialVariant (listId = lamina_brands, con parent = material)
        sales.unit          (listId = units)
        sales.paymentMethod (listId = payment_methods)
        sales.transferDestination (listId = transfer_destinations)
        workers.role        (listId = worker_roles)
```

Las referencias son por **valor de string**, no por doc id. Eso es lo
que hace que `renameItem` tenga que batch-update todas las sales que
referenciaban el value viejo (ver `master_lists_repository.dart`).
