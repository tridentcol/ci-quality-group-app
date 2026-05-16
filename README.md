# CI Quality Group — App Interna

App móvil interna de **CI Quality Group** para llevar dos flujos:

1. **Control de ventas** (chatarra, lámina y chatarra de tubería) reemplazando
   el formato Excel manual con consecutivo automático `CQG-XXX`.
2. **Control de horas laboradas** de los trabajadores operativos, con
   categorización legal automática (ordinaria, extra diurna, extra nocturna,
   dominical y sus variantes) y festivos colombianos calculados localmente.

Todo bajo un **panel de administración** que permite editar listas maestras,
formularios dinámicos, usuarios, jornadas, ver dashboards en tiempo real y
exportar a `.xlsx` por rango de fechas.

> **Estado actual**: foundations en este push (auth, tema, motor de horas,
> motor de festivos, modelos, scaffolding de pantallas). El llenado de cada
> módulo (formularios, dashboards, export) llega en pushes siguientes.

---

## Stack

- **Flutter** (Android + iOS desde un solo código).
- **Firebase Auth** (usuario/contraseña — el username se mapea internamente a
  `<username>@cqg.app` para Firebase).
- **Cloud Firestore** con caché offline ilimitada (sincroniza automáticamente
  cuando vuelve la conexión).
- **Riverpod** para estado, **go_router** para navegación.
- **Excel** generado en cliente con el paquete `excel`, compartido vía
  `share_plus` (correo, WhatsApp, Drive, etc.).
- **Festivos colombianos** calculados con algoritmo de Pascua + Ley Emiliani.
  Sin dependencias de red.

---

## Setup local

Asume que ya tienes Flutter >= 3.24 y el CLI de Firebase + FlutterFire.

```bash
# 1. Generar plataformas Android e iOS
flutter create --org co.ciqualitygroup --project-name ci_quality_group \
               --platforms=android,ios .

# Si flutter create reescribe pubspec.yaml, restauralo:
git checkout -- pubspec.yaml lib/

# 2. Dependencias
flutter pub get

# 3. Configurar Firebase (genera lib/firebase_options.dart real)
dart pub global activate flutterfire_cli
flutterfire configure --project=<tu-proyecto-firebase> --platforms=android,ios

# 4. Correr en emulador / dispositivo
flutter run
```

### Empaquetar APK firmado

```bash
flutter build apk --release
# El APK queda en build/app/outputs/flutter-apk/app-release.apk
```

---

## Roles y autenticación

Hay **tres usuarios** fijos (creados manualmente desde Firebase Console o
desde el panel admin cuando esté listo):

| Rol      | Descripción                                              |
|----------|----------------------------------------------------------|
| `admin`  | Acceso total, dashboards, listas maestras, formularios.  |
| `sales`  | Encargado de control de ventas. Solo el formulario.      |
| `hours`  | Encargado de control de horas. Solo el registro diario.  |

El login pide **usuario + contraseña**. Internamente se traduce a
`<usuario>@cqg.app` para Firebase Auth — los usuarios nunca ven correos.

Para crear el primer admin manualmente en Firebase Console:

1. **Authentication -> Users -> Add user** -> email `admin@cqg.app`, contraseña.
2. **Firestore -> users/{uid}** con:
   ```json
   {
     "username": "admin",
     "fullName": "Administrador CI Quality Group",
     "role": "admin",
     "active": true
   }
   ```

A partir de ahí, el admin podrá crear los otros dos usuarios desde la app
(módulo "Usuarios" — pendiente de UI en el próximo push, pero el modelo está).

---

## Reglas de jornada laboral (configurables)

| Día            | Jornada ordinaria | Almuerzo descontado |
|----------------|-------------------|---------------------|
| Lun – Vie      | 07:00 – 16:00     | 12:00 – 13:00 (1 h) |
| Sábado         | 07:00 – 11:00     | —                   |
| Dom / Festivo  | 07:00 – 16:00     | 12:00 – 13:00 (1 h) |

- **Diurno**: 06:00 – 19:00.
- **Nocturno**: 19:00 – 06:00.
- Cualquier minuto fuera de la jornada ordinaria cuenta como extra,
  clasificado por franja (diurna / nocturna) y por tipo de día (hábil /
  dominical-festivo).
- Almuerzo: solo se descuenta si la jornada del trabajador interseca el rango
  configurado.

Estos valores son el default y se persisten en
`settings/work_schedule` para que el admin los pueda ajustar desde la app.

### Categorías generadas

- `ordinary` — Hora ordinaria.
- `extraDay` — Hora extra diurna.
- `extraNight` — Hora extra nocturna.
- `sundayOrdinary` — Hora dominical diurna ordinaria.
- `extraSundayDay` — Hora extra dominical diurna.
- `extraSundayNight` — Hora extra dominical nocturna.
- `lunch` — Tiempo descontado por almuerzo (no se paga, solo diagnóstico).

---

## Festivos colombianos

Calculados localmente cubriendo:

- Fechas fijas (Año Nuevo, Trabajo, Independencia, Boyacá, Inmaculada, Navidad).
- Pascua y derivados (Jueves Santo, Viernes Santo, Ascensión, Corpus Christi,
  Sagrado Corazón) usando algoritmo de Pascua gregoriano.
- Movibles por **Ley Emiliani** (Reyes, San José, San Pedro y San Pablo,
  Asunción, Diversidad Étnica, Todos los Santos, Independencia de Cartagena).

Verificable con `flutter test test/colombian_holidays_test.dart`.

---

## Estructura del proyecto

```
lib/
├── main.dart                          # entry point + Firebase init
├── app.dart                           # MaterialApp.router + tema
├── firebase_options.dart              # PLACEHOLDER, reemplazar con flutterfire configure
├── core/
│   ├── theme/                         # verde árbol + negro, light/dark
│   ├── routing/app_router.dart        # go_router con redirect por rol
│   ├── constants/                     # roles, paths Firestore
│   └── utils/                         # money, dates
├── features/
│   ├── auth/                          # login, AuthRepository, AppUser
│   ├── admin/                         # panel admin, listas maestras
│   ├── workers/                       # gestión de trabajadores
│   ├── sales/                         # ventas (multi-material por venta)
│   ├── cashier/                       # caja (procesar / abonos / pérdidas)
│   └── hours/                         # control de horas
│       └── domain/
│           ├── colombian_holidays.dart    # motor de festivos
│           ├── hours_calculator.dart      # motor de cálculo legal
│           ├── hours_categories.dart
│           ├── work_schedule.dart
│           └── hours_entry.dart
└── shared/                            # widgets reutilizables
test/
├── colombian_holidays_test.dart       # tests del calendario
└── hours_calculator_test.dart         # tests del motor
assets/
├── images/logo.png                    # logo CI Quality Group
├── seed/workers_seed.json             # 10 trabajadores activos
└── fonts/                             # DESCARGAR Inter (ver abajo)
```

### Tipografía Inter

`pubspec.yaml` declara `assets/fonts/Inter-{Regular,Medium,SemiBold,Bold}.ttf`.
Descárgalos de https://rsms.me/inter/ (versión 4.x) y colócalos en
`assets/fonts/`. Mientras no estén, `google_fonts` los descarga en runtime
así que la app sigue funcionando — los archivos locales son solo para mejor
arranque en frío.

---

## Modelo de datos (Firestore)

```
users/{uid}                         -> AppUser (username, fullName, role, active)
workers/{id}                        -> Worker (nombre, cédula, banco, cargo, ...)
sales/{id}                          -> Sale (consecutivo, fecha, material, ...)
hours_entries/{id}                  -> HoursEntry (workerId, checkIn, checkOut, breakdown)
master_lists/{id}                   -> MasterList (providers, payers, materials, ...)
master_lists/{id}/items/{itemId}    -> MasterListItem (value, parent, active)
counters/sales_consecutive          -> { value: <int> }  // contador atómico
settings/work_schedule              -> WorkSchedule (jornadas + almuerzo)
```

---

## Roadmap

- [x] Foundations: tema, auth, router, modelos, motor de festivos, motor de
      horas, tests, seed inicial.
- [ ] CRUD de listas maestras (admin).
- [ ] CRUD de trabajadores con activación/desactivación.
- [ ] Formulario dinámico de ventas con consecutivo `CQG-XXX` por transacción
      atómica de Firestore.
- [ ] Formulario de horas con apertura/cierre de día y ventana de 24 h para
      editar.
- [ ] Dashboard admin (totales, gráficas, filtros).
- [ ] Constructor de formularios (admin agrega/quita campos).
- [ ] Exportación tabular `.xlsx` con filtros por rango.
- [ ] CRUD de usuarios desde la app (admin).
- [ ] Configuración de jornada y almuerzo desde la app.

---

## Licencia / Uso

Software interno de CI Quality Group. No distribución pública.
