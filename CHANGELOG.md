# Changelog

Todos los cambios importantes de CI Quality Group quedan documentados aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
versionado [SemVer](https://semver.org/spec/v2.0.0.html). El número entre `+`
es el `versionCode` de Android — cada release se sube en uno para que los
celulares acepten la actualización sobre la versión anterior.

## [1.1.0+5] — 2026-05-13

### Agregado
- **Workflow de estado de venta.** Las solicitudes que crea ventas
  arrancan en `generada` y solo caja puede llevarlas a `en_proceso` →
  `procesada` o `cancelada`. Ventas viejas (sin `state` en backend) se
  interpretan como `procesada` retro-compat. Trazas en el doc
  (`processedBy`, `canceledBy`, `markedAsLossBy` + razones).
- **Rol cajero** (color `#E6A100`). Toma solicitudes, las procesa,
  registra abonos, anula pagos (solo admin), marca pérdidas. Único rol
  con acceso a `/cashier/*`.
- **Pagos parciales con timeline.** Subcolección
  `sales/{id}/payments` con un doc por abono. Pantalla
  `SalePaymentsScreen` con header (total / pagado / saldo / pérdida +
  pill de `financialStatus` + plazo editable inline), timeline
  cronológico y FAB con bottom sheet para registrar pago.
- **payerName por abono.** Cada `SalePayment` lleva su propio campo
  opcional `payerName` (lista maestra `payers`). El form de sales ya
  no lo pide al crear: lo elige cajero al recibir cada abono.
- **Pérdidas con razón obligatoria.** Marca el saldo pendiente como
  `lost` (absorbente: `financialStatus` queda en `lost` aunque se cobre
  después). Solo admin puede revertir.
- **Plazo de pago** (`creditDueDate`) editable inline en
  `SalePaymentsScreen`. Si queda en el pasado, la deuda aparece como
  vencida en el tab `Deudas` del cajero (banner ámbar + chip "Solo
  vencidas").
- **Home de caja con 3 tabs** (Pendientes / Deudas / Cerradas), badges
  numéricos, búsqueda por consecutivo o cliente, rango de fecha y sort
  por antigüedad o saldo en Deudas.
- **Notificaciones in-app** con campana en el AppBar y badge de no
  leídas. Bottom sheet con filtro Todas/No leídas, marcar todas,
  agrupación visual por hora y navegación al recurso. Triggers:
  solicitud creada (→ cajero+admin), procesada (→ creador),
  cancelada (→ creador), pérdida (→ admin). Sin push del SO ni Cloud
  Functions — todo cliente.
- **Modo de fusión manual de listas maestras.** Desde el detalle de una
  lista que mapea a sales (clientes, materiales, etc.), botón
  "Fusionar manualmente" entra a modo selección por checkbox y permite
  juntar N items en uno canónico. Usa el mismo motor
  (`DuplicateService.applyMerges`) que el detector automático.
- **KPIs nuevos en admin.** Por cobrar, Pendientes en caja y Pérdidas
  como tarjetas separadas en el dashboard de ventas, derivados de los
  agregados denormalizados del doc Sale.

### Cambiado
- **Métricas de ventas** atribuyen `paidAmount` (no `totalValue`) y
  solo cuentan ventas con `state == procesada`. KPIs y gráficas
  reflejan lo realmente cobrado, no lo facturado. El auditor también
  aplica este filtro.
- **Form de sales** oculta `paymentMethod`, `transferDestination` y
  `payerName` — esos campos los completa cajero al procesar.
- **`SaleDetailScreen`** muestra pill de estado prominente + caption
  con trazas (`Procesada por X · fecha`). Oculta breakdown de pago y
  payer cuando el usuario es sales.

### Reglas Firestore
- Bloque nuevo `match /notifications/{id}` con target por uid o rol.
- Subcolección `match /sales/{sid}/payments/{pid}` con `amount > 0`
  exigido al crear; update prohibido; delete solo admin.
- Sales solo puede update sobre sus ventas mientras sigan en `generada`
  y dentro de la ventana de 24 h. Cajero puede update siempre. Admin
  todo.

## [1.0.3+4] — 2026-05-07

### Agregado
- **Pago dividido en ventas.** Una venta puede pagarse 100 % en efectivo,
  100 % por transferencia, o parte en cada uno (modo Mixto). Tres campos
  nuevos en el modelo: `cashAmount`, `transferAmount`, `transferDestination`.
- **Lista maestra `Destinos de transferencia`** con seed de Bancolombia,
  Nequi, Daviplata y Bancolombia Ahorro a la Mano. El admin puede agregar
  destinos nuevos sin tocar código y los cambios propagan a ventas históricas.
- **Módulo de desglose en detalle de venta.** Donut chart + texto con la
  partición efectivo/transferencia y porcentajes. Aparece solo cuando aporta
  info (pago mixto o transferencia con destino).
- **Filtro de auditor por destino de transferencia.** Permite crear auditores
  que solo ven ventas con cierto destino bancario.

### Cambiado
- **Métricas por método de pago** (admin) ahora reparten los montos reales
  entre Efectivo y Transferencia en pagos mixtos, en lugar de inflar una
  sola categoría. Las métricas son más precisas.
- **Gráfica de tendencia diaria del auditor** migrada de `BarChart` a
  `LineChart` para que respete el intervalo de etiquetas del eje X. Antes
  las fechas se solapaban en rangos largos.
- **SegmentedButton de modo de pago** sin íconos para que "Transferencia"
  entre completo en pantallas estrechas.
- **Export xlsx de ventas** ahora incluye 3 columnas nuevas: Efectivo,
  Transferencia y Destino transferencia.

### Corregido
- **MasterListField** vuelve a captura libre cuando la metadata de la lista
  todavía no existe en Firestore. Antes, un usuario de ventas se quedaba
  con un dropdown vacío que no dejaba escribir.

## [1.0.2+3] — 2026-05-07

### Agregado
- **Web deploy.** Primera versión de la app desplegada en Firebase Hosting
  (`https://quality-group-app.web.app`).

### Cambiado
- **Persistencia offline de Firestore** ahora está activa solo en native
  (Android/iOS). En web se deshabilitó porque IndexedDB puede fallar en
  modo incógnito o cuando hay otras pestañas abiertas.

### Eliminado
- **In-app updater.** El feature que descargaba e instalaba el APK desde
  dentro de la app se removió porque rompía el bundle web (incompatibilidad
  de `dio` y `open_filex` con `dart2js` en release). La distribución del APK
  vuelve a ser manual por WhatsApp / Drive.

### Corregido
- `Icons.merge_type` reemplazado por `Icons.call_merge` para que el ícono
  del botón de fusión renderice correctamente en el bundle web.

## [1.0.1+2] — 2026-05-06

### Agregado
- **Rol Auditor / Inversor.** Nuevo rol pensado para socios e inversores
  como Pedro: solo ven el subset de ventas que matchea un filtro
  configurable (ej. `materialVariant = PEDRO`). Dashboard dedicado con
  KPIs (total facturado, # ventas, ticket promedio, cantidad por unidad,
  mejor día histórico), tendencia diaria y lista cronológica.
- **Desglose de clientes** (nuevos vs recurrentes) en métricas de admin,
  con tap-to-expand a una pantalla con KPIs, distribución y recomendación.
- **Desglose de materiales más vendidos** con bar chart por material y
  porcentaje del total.
- **Tipos de materiales generalizado.** Antes "Tipos de lámina" estaba
  hardcoded para el material LAMINA. Ahora cualquier material puede tener
  subtipos (varilla 3/8, chatarra de tubería, etc.) con dropdown padre→hijo
  en el formulario.
- **Edición en lista maestra propaga a ventas.** Renombrar un cliente,
  material, vendedor, etc. en el catálogo actualiza todas las ventas
  históricas que lo referenciaban — sin huérfanos.
- **Anti-duplicados con normalización fonética.** Tres capas de defensa:
  autocomplete fuzzy en vivo, snap silencioso al canónico al salir del
  campo, y modal de confirmación al guardar si detecta similitud.
- **Herramienta de fusión de duplicados** en cada lista maestra. El admin
  elige el nombre canónico, los demás se eliminan, y todas las ventas se
  reescriben en una transacción.

### Corregido
- DuplicateReviewScreen rediseñada (era ilegible).
- Overflows en clients_breakdown, master_list_detail y chart del auditor.
- Migración a Flutter 3.32+ (`RadioGroup`, `FormField.value`).

## [1.0.0+1] — 2026-05-04

### Agregado
- Primera versión release del APK con keystore propio (`cqg-release.jks`).
- Iconos nativos del launcher + splash screen branded para Android e iOS.
- Branding del login y drawer.
- Paleta de neutros 100 % grises (sin tinte azul).
- `/admin` abre directamente en métricas.

### Eliminado
- App Check / reCAPTCHA — daba más problemas que valor en producción.
