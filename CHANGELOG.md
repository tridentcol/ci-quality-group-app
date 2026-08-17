# Changelog

Todos los cambios importantes de CI Quality Group quedan documentados aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
versionado [SemVer](https://semver.org/spec/v2.0.0.html). El número entre `+`
es el `versionCode` de Android — cada release se sube en uno para que los
celulares acepten la actualización sobre la versión anterior.

## [1.6.2+20] — 2026-08-17

### Corregido
- En desktop web, la foto del detalle de un movimiento (`/material/:id`)
  se veía gigante porque el `Row` con `Expanded` + `AspectRatio` crecía
  con el ancho de la ventana. El contenido del detalle ahora va dentro
  de un `ConstrainedBox` de 640px centrado, igual que un form/detail
  típico.
- Correo de notificación de material confirmado funcionando en
  producción: el intento real del usuario había caído con
  `PERMISSION_DENIED` porque el permiso IAM otorgado a la extensión
  (`roles/datastore.user` sobre `ext-firestore-send-email@...`) aún no
  había propagado. Se verificó con un envío de prueba real
  (`delivery.state: SUCCESS` en Firestore + log de Cloud Run
  confirmando la entrega SMTP) y se limpió el doc de `mail/` huérfano
  que quedó del intento fallido.

### Cambiado
- Dashboard de admin (`/admin/material`) reorganizado: arriba un
  comparativo siempre visible "Entró vs. Salió" (tap en cualquiera
  cambia la vista de abajo), y un `SegmentedButton` — mismo patrón que
  `AdminMetricsScreen` para Ventas/Horas — para ver el detalle
  (desglose por empresa, por material, feed de movimientos) de
  ingresos o salidas de a uno, en vez de los dos bloques completos
  apilados verticalmente.

## [1.6.1+19] — 2026-08-17

Serie de correcciones sobre el control de material (1.6.0+18) después
de probarlo con datos y usuarios reales. Bump de versionCode porque
en la sesión anterior se distribuyeron varios APK de prueba bajo el
mismo +18 — no volver a hacer eso, Android rechaza instalar un
versionCode igual o menor al ya instalado.

### Corregido
- Cámara/galería no abrían nada en Web (`MissingPluginException` por
  falta de `flutter clean` tras agregar `image_picker`/`firebase_storage`).
- Subida de fotos tiraba `[firebase_storage/unauthorized]` (`storage.rules`
  dependía de una función cross-service a Firestore que no funciona en
  runtime para este proyecto).
- Las fotos no cargaban en el detalle / el visor a pantalla completa se
  quedaba cargando para siempre (faltaba configurar CORS en el bucket
  de Storage — no es parte de ningún `firebase deploy`).
- Compresión de fotos más agresiva (1600px/q70 → 1280px/q60).

### Agregado
- Dashboard de admin (`/admin/material`) ahora también lista los
  movimientos individuales con su foto, no solo los totales agregados
  por empresa/material — admin puede entrar al detalle de cualquier
  ingreso/salida igual que hours, con la ventaja de que puede
  editarlo/borrarlo sin límite de 24h. La card se extrajo a un widget
  compartido (`MaterialEntryCard`) para que `/material` (hours) y
  `/admin/material` se vean idénticos.

## [1.6.0+18] — 2026-08-16

### Agregado
- **Control de ingreso y salida de material.** Nuevo módulo,
  totalmente independiente de `sales` (decisión explícita de Carlos),
  para registrar cada movimiento físico de bodega: foto del
  material/vagón (obligatoria), foto de procedencia/destino (opcional),
  material y cantidad (reusa las listas maestras de ventas), y la
  empresa contraparte — proveedor en ingreso (lista maestra nueva
  `Proveedores de material`) o cliente en salida (reusa la lista
  "Clientes" que ya usa Ventas, para no duplicar el catálogo). Cada
  movimiento genera un consecutivo atómico propio (`ING-XXX` o
  `SAL-XXX`). Lo maneja el mismo rol `hours` (control de horas) — gana
  una pantalla nueva `/material` con acceso directo desde `/hours` —
  más admin, que además tiene un dashboard (`/admin/material`) con
  ingresos y salidas por separado: totales del rango y desglose por
  empresa y por material en cada uno. Cada movimiento nuevo dispara una
  notificación in-app (campanita) al rol admin y, si hay destinatarios
  configurados en `Configuración → Notificaciones de material`, un
  correo con el resumen y las fotos vía la extensión de Firebase
  `firestore-send-email` (no requiere Cloud Functions propias).
  Primera vez que la app sube archivos: se habilitó Cloud Storage for
  Firebase (`storage.rules` nuevo) y se sumaron los paquetes
  `image_picker` + `firebase_storage`. Admin puede editar o borrar
  cualquier movimiento sin límite de tiempo (hours solo el suyo, dentro
  de 24h); borrar limpia también las fotos en Storage. Las reglas de
  Firestore/Storage validan que las fotos sean URLs reales de Storage,
  bloquean cambiar `type`/`consecutive` después de creado, y el correo
  a gerencia solo puede mandarse a los destinatarios configurados (no a
  direcciones arbitrarias).

(Los bugs encontrados al probar esto con datos reales — cámara/Web,
Storage, CORS — están en la entrada 1.6.1+19 de arriba.)

## [1.5.0+17] — 2026-07-26

### Agregado
- **Comisionistas: campo en la venta + análisis "quién vende más".** La
  venta tiene un campo opcional de comisionista, elegible de una lista
  maestra `Comisionistas` que solo el admin gestiona (estricta, sin
  captura libre, para que el conteo no se ensucie con variantes del mismo
  nombre). Una venta sin comisionista cuenta como venta directa de
  **bodega**. En el panel admin aparece una nueva sección "Por
  comisionista" (card en el dashboard + pantalla de detalle con KPIs,
  ranking y filtro de rango) que muestra cuánto vende cada comisionista y
  cuánto es venta directa de bodega, para comparar y poder manejar precios
  diferenciados. El campo se refleja en el detalle de la venta y en el
  export a Excel. Renombrar un comisionista en la lista maestra propaga a
  sus ventas históricas. Retrocompatible: las ventas anteriores quedan sin
  comisionista (bodega), sin migración.

## [1.4.1+16] — 2026-07-12

### Agregado
- **Autocompletado de la cédula al elegir un cliente conocido.** En el
  formulario de venta, al seleccionar (o escribir) un cliente que ya
  tiene ventas registradas, el número de documento se rellena solo con
  el de su venta más reciente. Funciona de forma retroactiva: la primera
  vez que se le carga la cédula a un cliente ya existente, queda
  disponible para autocompletarse en las siguientes ventas. El
  autocompletado es "sticky": si el usuario escribió el documento a
  mano, no se sobrescribe al cambiar de cliente; solo se reemplaza el
  valor que la app había autocompletado. El match del cliente tolera
  diferencias de mayúsculas/acentos/espacios en nombres históricos
  (mismo criterio con que se deduplican clientes). No requiere cambios
  de schema ni de reglas — la cédula se deriva del historial de ventas
  (`Sale.documentNumber`).

## [1.4.0+14] — 2026-05-25

### Agregado
- **Modo "delegación caja" — excepción on-demand para que sales cobre.**
  El admin puede activar un toggle en `Configuración → Delegación caja`
  con duración opcional (preset 2h/hoy hasta 18:00/sin vencimiento o
  programación personalizada con date+time picker). Mientras esté
  vigente, un banner naranja persistente arriba del Navigator avisa a
  todos los roles autenticados, y el form de venta del rol `sales`
  muestra una sección extra para registrar el pago (efectivo /
  transferencia / mixto + destino + "quién recibe") en el mismo
  submit. Si sales llena los campos, el repo crea venta + payment en
  una sola `runTransaction` con el payment marcado
  `createdViaDelegation: true` y los agregados financieros
  (`paidAmount`, `outstandingBalance`, `financialStatus`) ya cuadrados.
  Si los deja vacíos, la venta se crea como una solicitud normal sin
  payment y caja la cobra después como siempre. El history de
  activaciones/desactivaciones queda persistido como subcolección
  append-only visible en la misma pantalla del admin.
- **Caja "verifica" en vez de "procesar" cuando la venta llegó
  pre-cobrada por sales.** El detalle del cajero detecta esa
  combinación (`isDelegationPrepaid`) y reetiqueta los botones:
  *Iniciar proceso* → *Verificar pago*, *Procesar* → *Confirmar
  recibido*, *Devolver* → *Reportar discrepancia* (con motivo
  obligatorio). Una card naranja *"Pago a verificar"* muestra el
  monto, método, desglose mixto, destino de transferencia, "quién
  recibe" y "Sales · nombre" del payment para que el cajero
  confirme que el dinero efectivamente entró antes de finalizar;
  después del cierre la misma card queda como *"Pago recibido
  (delegación)"* en gris para preservar la trazabilidad.
- **Trazabilidad visual en cards y listas.** Las cards del cajero
  llevan un chip naranja *"Bajo delegación · Pagado [parcial]"* en
  la tab Pendientes; las cards de sales un badge *"Con abono"*
  cuando la venta nació con pago de delegación. El timeline de
  abonos marca cada payment de delegación con el mismo chip y
  prefija el actor con *"Sales · "* para distinguirlo del flujo
  normal del cajero.
- **KPI "Delegación caja" en el dashboard del admin con drill-down.**
  Aparece solo cuando hubo pagos de delegación en el rango — naranja,
  con count + monto cobrado, tap para abrir `/admin/delegation/payments`
  con la lista filtrada (rango configurable) y link al detalle de
  cada venta.
- **Tres notificaciones nuevas:** `delegation_activated`,
  `delegation_deactivated`, `payment_delegation_recorded`. Las dos
  primeras se emiten al rol `cajero` + `admin` cuando el admin
  cambia el toggle. La tercera se emite cuando sales registra un
  pago de delegación.
- **Recibo de pago bajo delegación en el detalle de sales.** El
  vendedor que pre-cobró ahora ve su propio cobro en
  `SaleDetailScreen` con monto, método, payer y timestamp — antes
  solo podía verlo abriendo la pantalla de pagos del cajero (donde
  tampoco tenía permisos de lectura).

### Cambiado
- **Rules de Firestore:** sales ahora puede leer payments con
  `registeredBy == auth.uid` (necesario para que el detalle muestre
  su propio cobro de delegación). El history de delegación exige
  `keys().hasAll(['action','actorUid','actorName','at'])` como
  defensa contra entries malformadas vía API directa.
- **Métrica admin "Pendientes en caja"** ahora suma
  `outstandingBalance` en vez de `totalValue` para no double-counter
  el dinero ya cobrado vía delegación (antes una venta pre-cobrada
  parcial inflaba el KPI con el doble de plata).
- **Export xlsx de ventas:** ahora hidrata las columnas *Método*,
  *Efectivo*, *Transferencia*, *Destino transferencia* y *Quién
  recibe* desde la subcolección de payments cuando
  `Sale.paymentMethod` viene vacío (caso del flujo nuevo y
  delegación). Antes esas ventas exportaban esas columnas en blanco
  a pesar de tener dinero cobrado.
- **`DetailsCard` del cajero:** la fila "Quién recibe" ahora cae al
  payer del payment más reciente cuando `Sale.payerName` está vacío,
  y se oculta si tampoco hay payments — antes mostraba la fila
  siempre con valor en blanco para ventas del flujo nuevo.
- **Notif de `voidPayment`:** si el payment anulado era de
  delegación, también se notifica al rol cajero para que el cierre
  de caja refleje el cambio.
- **Notif de `cancelRequest`:** si la venta cancelada tiene
  `paidAmount > 0`, el body incluye el monto a verificar para
  devolución.

### Corregido
- **`SalesDelegationRepository.deactivate`** ya no falla con error
  opaco de servidor cuando el singleton `settings/sales_delegation`
  no existe todavía — devuelve `StateError` claro para que
  `friendlyError` muestre un mensaje útil.

## [1.3.0+13] — 2026-05-15

### Agregado
- **Múltiples materiales por venta.** El formulario de venta soporta
  uno o varios items de material por solicitud. El primer material es
  obligatorio; los adicionales se agregan con el botón "Agregar otro
  material" y se pueden quitar individualmente. Cada item lleva su
  propia cantidad, valor unitario, unidad y subtotal. El total de la
  venta es la suma de los subtotales. Las ventas históricas (1 solo
  material) se siguen viendo igual; el cambio aplica al ingresar la
  segunda referencia. Toda la app (detalle de venta, card de lista,
  caja, exportación Excel, métricas "Por material") refleja el
  desglose: en métricas, una venta con $300k de CHATARRA + $700k de
  LAMINA cobra parcialmente y aporta proporcionalmente a cada bucket.
- **Métrica "Por método de pago" desde abonos reales.** El donut del
  dashboard del admin ahora suma los `cashAmount`/`transferAmount` de
  cada `SalePayment` registrado en el rango (collection group query),
  no del campo legacy de la venta. Esto captura correctamente las
  ventas del flujo nuevo donde el método se decide al registrar cada
  abono. Para ventas legacy (admin viejo con `paymentMethod` en la
  venta y sin abonos en la subcolección) se mantiene el fallback
  proporcional. La leyenda muestra ahora el monto en pesos como dato
  primario y el porcentaje como hint pequeño debajo. Requiere índice
  `collectionGroup: payments` sobre `registeredAt`.

### Corregido
- **Payer vacío en "Por quién recibe".** Cuando se procesaba una venta
  del flujo nuevo sin registrar ningún abono (entrega contra acuerdo
  de palabra), su `payerName == ''` se sumaba como una fila en blanco
  al tope del breakdown. Ahora el agregado ignora payers vacíos en la
  fuente (`SalesMetrics.compute`) y el payer real del flujo nuevo se
  toma de cada `SalePayment.payerName`.
- **`Sale.fromSnapshot` resiliente a docs viejos.** El cast directo
  `data['totalValue'] as num` y los campos legacy de material/unit/
  quantity/unitPrice podían crashear la app entera al toparse con un
  doc histórico parcialmente migrado. Ahora todos esos reads usan
  null-coalescing y `totalValue` se deriva de los items[] si el campo
  no está en el doc.
- **Consistencia `total` vs `byMethod` en ventas canceladas.** El KPI
  "Cobrado" siempre sumó `paidAmount` de canceladas (la plata entró);
  pero el donut "Por método de pago" las saltaba, dejando ambos
  números desalineados. El fallback legacy ahora corre antes del
  filtro por `procesada` y los abonos de canceladas también
  contribuyen al donut.
- **Validación client-side de ventana 24 h al guardar.** Si la ventana
  expiraba entre que sales abría el form y guardaba, Firestore
  rebotaba con `permission-denied` opaco. Ahora antes de llamar a
  `updateSale` el form valida `editableUntil` contra el reloj actual y
  muestra "La ventana de edición de 24 h ya expiró. Solo el admin
  puede modificar esta venta."
- **`_DonutCard` filtra secciones de valor 0.** `fl_chart` renderea
  secciones con `value: 0` como un pixel invisible que ensucia la
  dona; ahora filtramos esas entradas antes del render.
- **Bounds guard en `_removeItem`.** Protección defensiva contra
  doble-tap o rebuilds concurrentes al quitar un item del formulario.
- **`updateSale` recomputa agregados financieros al cambiar `items`.**
  Bug: al editar una venta procesada (ej. agregar otro material), el
  `totalValue` se actualizaba pero `outstandingBalance` y
  `financialStatus` quedaban stale hasta que se registrara el siguiente
  abono. La consecuencia visible: el "Saldo" en la pantalla de pagos
  seguía mostrando el valor viejo. Ahora `updateSale` corre dentro de
  una transacción cuando recibe `items`: lee `paidAmount`/`lossAmount`
  del doc actual, recomputa el saldo y el status, y persiste todo
  junto. Mismo patrón que ya usaba `registerPayment` en
  `CashierRepository`.
- **`deleteSale` borra en cascada los abonos.** Antes, borrar una venta
  dejaba huérfanos los docs de `sales/{id}/payments/{paymentId}` en
  Firestore — el `collectionGroup('payments')` del dashboard los seguía
  viendo como data fantasma y `doc.reference.parent.parent` podía
  retornar null. Ahora un `WriteBatch` borra primero la subcolección y
  después el padre.
- **`hours_repository.updateEntry` siempre recompute `breakdown`.** Mismo
  patrón del bug de items[] en sales: editar solo `checkIn` (sin pasar
  `checkOut`) dejaba el desglose stale aunque el rango efectivo
  cambiara. Ahora se recompute siempre que tengamos ambos extremos del
  día. Además, todo el método corre en `runTransaction` para evitar
  race conditions cuando dos sesiones cierran el mismo día casi
  simultáneo (la invariante "editableUntil se fija en el primer
  cierre" estaba expuesta sin ello).
- **Propagación de renames a workers y a la subcolección de payments.**
  La tabla `_saleFieldByListId` solo sabía propagar a `sales` —
  renombrar un item de `worker_roles` no tocaba `workers.role` (quedaba
  huérfano del catálogo), y renombrar `transfer_destinations`/
  `payment_methods`/`payers` no propagaba a los abonos registrados
  (subcolección `sales/{saleId}/payments`). Refactor: nueva tabla
  `_propagationByListId` con primary + secondaries por listId, y un
  helper `propagateValueChange` compartido por `renameItem` y
  `applyMerges`. `findClusters` y `syncCatalogFromSales` ahora también
  funcionan para `worker_roles` (cuenta refs en `workers`, no en
  `sales`).
- **`outstandingBalance` clampeado a `>= 0` en sobrepagos.** Si un abono
  empuja `paidAmount > totalValue`, el saldo se mostraba como número
  negativo confuso. Nuevo helper `Sale.computeOutstandingBalance` que
  clampea a 0 y se usa consistentemente en `registerPayment`,
  `voidPayment`, `updateSale` y el fallback de `Sale.fromSnapshot`. El
  crédito a favor del cliente (caso raro) queda implícito: la diferencia
  `paidAmount - totalValue` se calcula en UI si se necesita.

### Cambiado
- **Ventana de edición de venta: 24 h fijas y única.** La ventana se
  fija al crear (`createdAt + 24 h`) y JAMÁS se reasigna al editar.
  Además, ya no se requiere que la solicitud siga en estado
  `generada` para que sales la edite: mientras esté dentro de las
  24 h y haya sido creada por el mismo user, puede tocar los campos
  del formulario sin importar si caja ya la tomó (excepto los campos
  financieros, que siguen siendo del dominio cajero). El mensaje en
  el detalle ahora dice "Editable hasta {hora} (24 h desde el
  registro, no se reinicia al editar)".

### Eliminado
- **Constructor de formularios.** Se removió la feature completa de
  `form_builder` (módulo `/admin/form-builder`, entrada del menú
  lateral, colección `form_schemas` en Firestore, motor de fórmulas
  y renderer dinámico). El formulario de ventas ahora es estático
  con la estructura canónica de la app (fecha, documento, cliente,
  materiales, valores). Esto reduce significativamente la
  complejidad — la feature aportaba más riesgo de romper la app que
  valor real, y el flujo unificado de caja ya cubre las necesidades
  reales del producto. El campo `customFields` se preserva en
  Firestore para ventas viejas que lo tengan, pero ya no se lee ni
  se escribe desde el cliente. La regla `match /form_schemas` se
  removió de `firestore.rules`.

## [1.2.1+11] — 2026-05-14

### Cambiado
- **KPI cards en mobile: tiles horizontales apilados.** En pantallas
  `< 600 dp` (cualquier teléfono en vertical, sea APK o web mobile)
  cada `KpiCard` se renderea como tile horizontal — icono en un
  cuadrado tintado a la izquierda, label + subtítulo en columna al
  medio, valor a la derecha — y los tiles se apilan verticalmente con
  separación de 8 dp. En tablets y desktop (`≥ 600 dp`) el layout
  vertical en grid de N columnas (Row con `IntrinsicHeight`) sigue
  igual. La razón del cambio: como cada tile mobile tiene todo el
  ancho del scroll para el valor, el `FittedBox` rara vez tiene que
  escalarlo abajo, así que la fuente del valor se ve uniforme entre
  todas las tarjetas (antes "Cobrado: $1.234.567" salía más chico que
  "Procesadas: 3" por ser más largo). La decisión se inyecta vía
  `_CompactKpiScope` interno — los call-sites no cambian.

## [1.2.0+10] — 2026-05-14

### Corregido
- **Revert del umbral de `KpiRow`** (1.2.0+9). El cambio anterior subió
  el threshold a 600 dp asumiendo que se necesitaba modo Wrap (2 cards
  + 1 orphan) en todo teléfono. Pero eso le rompió la simulación web
  de teléfono al user, que se veía bien con threshold 380. Vuelvo a
  380. La diferencia visual web-vs-app que el user reporta requiere
  más diagnóstico antes de tocar este widget de nuevo.

## [1.2.0+8] — 2026-05-14

### Agregado
- **Notificación: solicitud devuelta a sales** (`saleReturnedToSales`).
  Cierra el único loop colaborativo bidireccional del workflow: cuando
  cajero devuelve una solicitud `enProceso → generada` para corrección,
  el creador (sales) recibe notif con la razón. Tap navega al form de
  edición de la venta. Sin esto la solicitud reaparecía en la lista de
  sales sin pista de por qué cajero la rechazó.
- **Notificación: abono anulado** (`paymentVoided`). Cuando admin
  ejecuta `voidPayment`, el cajero que registró el abono recibe la
  notif con el monto y la razón. Evita el bug clásico de re-registrar
  el mismo pago creyendo que se perdió. Tap navega al ledger de pagos
  de la venta para que vea el estado actualizado.
- **`PayersBreakdownScreen`** (`/admin/metrics/payers`). Pantalla
  detallada con KPIs (# personas distintas, top quien recibe, total
  recibido), distribución completa con barras + % del total y filtro
  de rango propio. Misma estructura que `MaterialsBreakdownScreen` y
  `ClientsBreakdownScreen` para que el patrón sea predecible.
- **Campo `byPayer` en `SalesMetrics`** (mapa completo). `topPayers`
  ahora se deriva de acá; el detalle nuevo consume el mapa entero.

### Cambiado
- **Form de venta unificado para sales + admin.** Hasta esta versión
  admin tenía un branch propio en `SaleFormScreen` que pedía
  `paymentMethod`, monto efectivo/transferencia, destino y `payerName`
  para crear ventas `state=procesada` directamente. Eso rompía el
  workflow: las ventas de admin no pasaban por caja, no aparecían en
  el tab "Pendientes" y no se notificaban. Ahora cualquier rol
  (sales o admin) crea solicitudes `state=generada` con solo los
  datos comerciales — cajero las procesa y registra los abonos. Se
  removió el `_PaymentSection`, el modo Mixto y la sección de pago
  del form (código muerto en el archivo, queda para una pasada de
  limpieza posterior).
- **"Top quien recibe" → "Por quién recibe"** en el dashboard. Card
  ahora tappable con chevron, igual que "Por material" y "Clientes".
  Tap navega a la pantalla de detalle nueva.
- **Alineación del dashboard de métricas.** Espaciado consistente
  entre módulos: cuando una sección no se renderea (ej. línea de
  cobrado por día con menos de 2 días, breakdown por material vacío),
  no queda un gap fantasma. Antes el `SizedBox(height: 16)` previo
  vivía afuera del `if`, dejando aire entre módulos sin razón.

### Routing nuevo
- `/admin/metrics/payers` → `PayersBreakdownScreen`.

## [1.1.2+7] — 2026-05-14

### Corregido
- **Íconos web (segundo intento).** El deploy de 1.1.1+6 todavía no
  mostraba íconos. Causa: declarar `family: MaterialIcons` en
  `pubspec.yaml` con `uses-material-design: true` deja DOS entries para
  la misma familia en `FontManifest.json` (la auto-inyectada del SDK
  más la nuestra). Flutter Web no las combina como fallback chain en
  release — sólo carga la primera (la del SDK, atrapada en cache vieja
  e incompleta). Fix: `uses-material-design: false` en pubspec. Ahora
  el manifest tiene **una sola** entry de `MaterialIcons`, apuntando a
  `assets/fonts/cqg_material_icons.otf`. El font del SDK ni siquiera se
  bundlea en `build/web/`. No afecta widgets de Material — sólo evita
  la auto-inclusión del font.

## [1.1.1+6] — 2026-05-14

### Corregido
- **Íconos rotos en web (definitivo).** Hasta esta versión la app servía
  el font `MaterialIcons` del SDK directamente desde la URL fija
  `/assets/fonts/MaterialIcons-Regular.otf`. Un deploy temprano (antes de
  agregar `--no-tree-shake-icons`) sirvió ahí un OTF subseteado, y como
  Firebase Hosting tenía `Cache-Control: max-age=2592000` (30 días) para
  fonts, navegadores y CDN siguieron entregando el font incompleto a los
  usuarios. Tres rondas de reemplazos en Dart (`call_merge`, `compress`,
  `checklist_outlined`, `notifications_none`, etc.) no podían arreglarlo
  porque el binario que llegaba al cliente era el viejo. Fix:
  - Se bundlea el OTF completo (1.6 MB) bajo
    `assets/fonts/cqg_material_icons.otf` y se declara en
    `pubspec.yaml` con `family: MaterialIcons`. URL nueva =
    cache miss garantizado para todos.
  - `firebase.json` baja el TTL de `*.otf|woff|woff2|ttf` de 30 días a
    **1 hora con `must-revalidate`**, para que esto no se repita.
  - Los íconos canónicos que se habían degradado a sus variantes "sin
    sufijo" vuelven a sus versiones originales: `notifications_outlined`,
    `hourglass_top_outlined`, `account_balance_wallet_outlined`,
    `report_gmailerrorred_outlined`, `warning_amber_outlined`,
    `calculate_outlined`, `timer_outlined`, `lock_open_outlined`,
    `play_arrow_outlined`, `undo_outlined`, `cancel_outlined`,
    `notes_outlined`, `event_outlined`, `point_of_sale_outlined`,
    `call_merge`. Mobile y web ahora se ven idénticos.

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
