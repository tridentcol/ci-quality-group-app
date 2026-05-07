# Changelog

Todos los cambios importantes de CI Quality Group quedan documentados aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
versionado [SemVer](https://semver.org/spec/v2.0.0.html). El número entre `+`
es el `versionCode` de Android — cada release se sube en uno para que los
celulares acepten la actualización sobre la versión anterior.

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
