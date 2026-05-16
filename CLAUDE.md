# CLAUDE.md — Contexto para AI agents

**Lee este documento al iniciar.** Es la fuente de verdad sobre cómo
trabajar en este repo. Si algo no está acá pero deberías saberlo,
**actualizá este archivo** como parte del cambio.

---

## Qué es esta app

**CI Quality Group** — app interna Flutter (Android + iOS + Web) para una
empresa colombiana. Dos flujos principales:

1. **Control de ventas** de chatarra/lámina con consecutivo automático
   `CQG-XXX`, formulario fijo que admite múltiples materiales por venta,
   workflow de caja (generada → enProceso → procesada), abonos parciales
   y export a Excel.
2. **Control de horas laboradas** con cálculo legal automático (extra
   diurna/nocturna, dominical, festivos colombianos) y export mensual.

Plus un **panel admin** completo con métricas, listas maestras editables,
gestión de usuarios y herramienta de fusión de duplicados. Más un **rol
auditor** para socios/inversores que solo ven el subset de datos que les
corresponde.

---

## Stack

- **Flutter ≥ 3.32** (Dart ≥ 3.4) — Android + iOS + Web desde un solo codebase.
- **Firebase** — Auth (usuario/contraseña → `<username>@cqg.app`),
  Firestore (offline en native, en memoria en web), Hosting (web).
- **Riverpod** (`flutter_riverpod`) — estado y DI.
- **go_router** — navegación declarativa con redirect por rol.
- **fl_chart** — gráficas (line + pie).
- **excel** + `share_plus` — export tabular.

Sin Cloud Functions ni backend custom. Toda la lógica vive en cliente +
Firestore + reglas de seguridad.

---

## Reglas críticas (NO romper)

1. **Branch de desarrollo**: `claude/check-system-status-FP9g9`. Siempre
   commit + push a esa rama, nunca a `main`.
2. **`firebase_options.dart` está gitignored** porque tiene API keys.
   Si lo borrás, regenerá con `flutterfire configure`.
3. **`firebase.json` tiene cache headers críticos** — no lo sobrescribas.
   Si `firebase init` lo destruye, `git checkout firebase.json`.
4. **No agregues paquetes nativos en web** sin conditional import
   (`if (dart.library.html)`). `dio`, `open_filex` rompen el bundle web.
5. **No habilites `persistenceEnabled` de Firestore en web** —
   IndexedDB falla en incógnito y deja la app trabada en el splash.
6. **Font de íconos bundleado como asset** — `assets/fonts/cqg_material_icons.otf`
   (copia del OTF completo del SDK Flutter, ~1.6 MB) declarado en
   `pubspec.yaml` con `family: MaterialIcons`. Esto **override** el font
   del SDK y garantiza que el mismo glifo aparezca en Android, iOS y Web.
   Si en algún build un icono renderea como caja vacía (tofu), NO es
   problema del font — revisá:
   (a) cache del navegador / CDN (hard refresh + Clear site data),
   (b) que el deploy haya re-incluido el OTF en `build/web/assets/fonts/`,
   (c) que el TTL en `firebase.json` para `*.otf` siga en 1 h con
   `must-revalidate` (la línea está en la sección de headers). Cualquier
   icono de `Icons.*` está disponible.
7. **Comentarios**: solo escribí cuando el WHY no es obvio. Ver
   `docs/conventions.md`. No documentes lo que el código ya dice.
8. **Trailing commas obligatorias** (lint configurado). Bloques de varias
   líneas siempre con `,` antes del `)`.
9. **No hagas hooks ni magic** — esta app es pragmática, no académica.
10. **No agregues tests si no te los pidieron explícitamente**, salvo
    para motores puros (cálculo de festivos, hours calculator). El resto
    se valida manualmente.

---

## Layout del repo

```
ci-quality-group/
├── CLAUDE.md                  # este archivo
├── CHANGELOG.md               # historial de versiones — actualizar en cada release
├── README.md                  # overview para humanos
├── pubspec.yaml               # version: X.Y.Z+N — bumpear en cada release
├── firebase.json              # config de Hosting + Firestore. NO sobrescribir
├── firestore.rules            # reglas de seguridad — siempre actualizar al cambiar roles/colecciones
├── firestore.indexes.json     # índices compuestos (evitamos sumarlos cuando podemos)
├── analysis_options.yaml      # lint rules
├── docs/
│   ├── architecture.md        # capas, providers, repositorios
│   ├── data-model.md          # schema Firestore completo
│   ├── conventions.md         # estilo de código + reglas de comentarios
│   ├── workflows.md           # playbooks para tareas comunes (agregar campo, rol, lista, etc.)
│   ├── debugging.md           # síntomas → diagnóstico → fix
│   ├── deployment.md          # build APK + deploy web
│   ├── android_release_guide.md
│   ├── ios_build_checklist.md
│   └── production_checklist.md
├── lib/
│   ├── main.dart              # entry point + Firebase init + Firestore settings
│   ├── app.dart               # MaterialApp.router + tema
│   ├── firebase_options.dart  # GITIGNORED — generado por flutterfire configure
│   ├── core/                  # infra compartida (no específica a una feature)
│   │   ├── constants/         # roles, paths de Firestore
│   │   ├── routing/           # go_router + redirect por rol
│   │   ├── theme/             # paleta, tipografía, modo claro/oscuro
│   │   └── utils/             # money, dates, errors, text_match
│   ├── features/              # una carpeta por feature, cada una con data/domain/presentation
│   │   ├── auth/              # login + AppUser + AuthRepository
│   │   ├── admin/             # panel admin, métricas, listas maestras, usuarios
│   │   ├── auditor/           # dashboard del rol auditor
│   │   ├── sales/             # ventas (formulario + lista + detalle, multi-material)
│   │   ├── cashier/           # caja (procesar solicitudes, abonos, pérdidas)
│   │   ├── hours/             # control de horas + motor de cálculo
│   │   └── workers/           # CRUD de trabajadores
│   └── shared/                # widgets y services reutilizables entre features
│       ├── widgets/           # AppLogo, MasterListField, HeroBanner, ...
│       └── services/          # xlsx_export_service + conditional imports web/io
├── android/                   # signing config en android/key.properties (gitignored)
├── ios/
├── web/                       # index.html con splash CSS
├── assets/
│   ├── images/                # logos
│   └── seed/                  # data inicial (workers, etc.)
└── test/
    ├── colombian_holidays_test.dart   # motor de festivos
    └── hours_calculator_test.dart     # motor de horas
```

---

## Convención de features

Cada feature en `lib/features/<name>/` sigue esta estructura:

- **`domain/`** — modelos puros (clases con `toMap`/`fromSnapshot`),
  lógica de negocio sin dependencias de Firebase ni Flutter.
- **`data/`** — repositorios (acceso a Firestore) + providers de Riverpod.
- **`presentation/`** — Screens (`*_screen.dart`) y widgets específicos
  de la feature (`presentation/widgets/`).

**Excepción:** algunas features no necesitan las 3 capas. Ej. `auditor`
solo tiene `presentation/` porque consume providers de `sales` y `auth`.

---

## Comandos clave

```powershell
# Setup
flutter pub get
flutterfire configure --project=quality-group-app   # si falta firebase_options.dart

# Desarrollo
flutter run -d chrome              # web
flutter run                        # mobile (emulador o device conectado)
flutter analyze                    # lint — debe pasar con 0 errores

# Build
flutter build apk --release --split-per-abi          # APKs por arquitectura
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run

# Deploy
firebase deploy --only firestore:rules   # actualizar rules
firebase deploy --only hosting           # deploy web

# Git
git pull
git add <files>
git commit -m "<mensaje claro>"
git push origin claude/check-system-status-FP9g9
```

---

## Workflow de cambios (cómo trabajar)

1. **Entender el cambio.** Si es ambiguo, pedí aclaración antes de tocar
   código. No asumas.
2. **Identificar archivos afectados.** Usá Grep/Glob. Consultá
   `docs/workflows.md` si es una tarea común (agregar campo, agregar
   rol, agregar lista maestra).
3. **Hacer el cambio.** Respetá las convenciones de `docs/conventions.md`.
4. **`flutter analyze`** — debe pasar con 0 errores antes de commit.
5. **Validación manual.** Si afecta UI, abrí en `flutter run -d chrome`
   o emulador y probá los happy paths + edge cases.
6. **Actualizar docs si corresponde:**
   - `CLAUDE.md` si cambia algo de la regla general.
   - `docs/architecture.md` si cambia la arquitectura.
   - `docs/data-model.md` si cambia un schema de Firestore.
   - `docs/workflows.md` si descubriste un patrón nuevo o tarea común.
   - `CHANGELOG.md` para todo cambio user-facing (sumalo en la entrada
     de versión "Unreleased" arriba del último release).
7. **Commit + push.** Mensaje claro en imperativo, una línea de título
   + cuerpo si hace falta explicar el WHY. Push a la rama de desarrollo
   indicada arriba.

### Cuándo bumpear `pubspec.yaml`

- Solo para **releases reales** que se distribuyen (APK o web deploy).
- Para builds intermedios de desarrollo no.
- Subí el `+N` (versionCode) **siempre** que distribuyas un APK nuevo —
  Android no acepta updates con el mismo versionCode.

---

## Roles y permisos

| Rol      | Pantallas accesibles                          | Firestore (resumen)               |
|----------|-----------------------------------------------|-----------------------------------|
| `admin`  | Todo                                           | r/w sobre todo                    |
| `sales`  | `/sales/*`                                     | r/w sobre `sales`, lectura de listas |
| `hours`  | `/hours/*`                                     | r/w sobre `hours_entries`         |
| `auditor`| `/audit` (dashboard filtrado por su auditFilter)| solo lectura sobre `sales`        |

Detalles completos en `docs/data-model.md` y `firestore.rules`.

---

## Pointers a documentación profunda

- **Arquitectura, capas, Riverpod, routing, providers:** `docs/architecture.md`
- **Schema completo de Firestore y relaciones:** `docs/data-model.md`
- **Estilo de código, comentarios, naming:** `docs/conventions.md`
- **Recetas para tareas comunes (paso a paso):** `docs/workflows.md`
- **Diagnóstico de problemas conocidos:** `docs/debugging.md`
- **Build de release y deploy:** `docs/deployment.md`
- **Android release detallado:** `docs/android_release_guide.md`
- **iOS build:** `docs/ios_build_checklist.md`
- **Checklist pre-producción:** `docs/production_checklist.md`

---

## Cosas que NO existen (no las inventes)

- **In-app updater** — se removió en 1.0.2. Distribución de APK es manual.
- **App Check / reCAPTCHA** — se removió, daba más problemas que valor.
- **Constructor de formularios (form_builder)** — se removió en 1.3.0.
  El formulario de venta es estático; cualquier campo nuevo se suma a
  mano siguiendo `docs/workflows.md` → "Agregar un campo nuevo al
  modelo Sale". Tampoco existen `customFields` ni `form_schemas/` en
  Firestore activos.
- **Cloud Functions** — no hay backend custom. Si necesitás trabajo
  server-side, hablalo con el usuario antes.
- **Notificaciones push** — no implementado.
- **Sync con sistemas externos** — sin integraciones. Todo es manual via xlsx.
