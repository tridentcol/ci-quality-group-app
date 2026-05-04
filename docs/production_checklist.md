# Checklist de puesta en producción — CI Quality Group

Pasos que **solo se hacen una vez** desde la consola de Firebase / Google
Cloud o desde tu máquina con permisos. El código ya está listo; aquí solo
quedan las configuraciones externas.

> Marca cada caja a medida que avances. Si saltas un paso, anótalo en
> "Pendientes" al final.

---

## 1. Authorized domains en Firebase Auth

Para que el login web funcione, el dominio tiene que estar en la lista.

- [ ] Consola Firebase → **Authentication** → **Settings** →
      **Authorized domains**.
- [ ] Confirma que aparezcan:
  - `quality-group-app.web.app`
  - `quality-group-app.firebaseapp.com`
  - `localhost` (para desarrollo)
- [ ] Si en el futuro montas dominio propio, agrégalo aquí también.

---

## 2. Política de contraseñas

Por defecto Firebase Auth acepta contraseñas de 6 caracteres. Subir el
mínimo evita "123456".

- [ ] Consola Firebase → **Authentication** → **Settings** →
      **Password policy** → **Customize**.
- [ ] **Minimum length**: `8`.
- [ ] **Require uppercase**: opcional (recomendado).
- [ ] **Require numeric**: opcional (recomendado).
- [ ] **Enforcement**: `Require` (no `Notify`, queremos que se aplique).
- [ ] Save.

> Esto solo aplica para nuevas contraseñas / cambios. Las cuentas
> existentes siguen con la suya hasta que la cambien.

---

## 3. Backups automáticos de Firestore

Si alguien borra datos por error, sin backups no hay vuelta atrás.

### 3.1 Habilitar el bucket destino

- [ ] Consola Google Cloud → **Storage** → **Buckets** → **Create**:
  - Name: `quality-group-app-firestore-backups`
  - Region: `us-east1` (o la que esté más cerca; us-east1 = Carolina)
  - Storage class: **Nearline** (más barato para backups que rara vez
    se leen)
  - Lifecycle: opcional, "Delete objects older than 90 days".

### 3.2 Programar el export

Desde una terminal con `gcloud` autenticado al proyecto:

```bash
gcloud firestore operations cancel-all  # por si hay otros corriendo
gcloud scheduler jobs create http firestore-daily-backup \
  --schedule="0 3 * * *" \
  --time-zone="America/Bogota" \
  --uri="https://firestore.googleapis.com/v1/projects/quality-group-app/databases/(default):exportDocuments" \
  --http-method=POST \
  --oauth-service-account-email="$(gcloud config get-value project)@appspot.gserviceaccount.com" \
  --message-body="{\"outputUriPrefix\":\"gs://quality-group-app-firestore-backups\"}"
```

- [ ] Confirma en **Cloud Scheduler** que el job aparece y está
      `Enabled`.
- [ ] Al día siguiente, revisa el bucket: debería haber una carpeta
      `2025-XX-XX` con el dump.

### 3.3 Probar restore (una vez)

Vale la pena hacerlo una sola vez para validar el procedimiento (no en
producción real, ojalá en un proyecto de prueba).

```bash
gcloud firestore import gs://quality-group-app-firestore-backups/2025-XX-XX
```

---

## 4. Crashlytics (telemetría de crashes — solo móvil)

Crashlytics no soporta web; aplica cuando hagas el build de iOS/Android.
Cuando llegue el momento:

- [ ] `flutter pub add firebase_crashlytics`
- [ ] **Android** `android/build.gradle.kts`:
      `classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.2")`
- [ ] **Android** `android/app/build.gradle.kts`:
      `id("com.google.firebase.crashlytics")` en `plugins {}`
- [ ] **iOS**: nada extra; FlutterFire lo wirea con el Pod.
- [ ] En `lib/main.dart`, dentro de `_initFirebase` (con guard `kIsWeb`):
  ```dart
  if (!kIsWeb) {
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
  ```
- [ ] Consola Firebase → **Crashlytics** → activar para Android e iOS.

> Por ahora se omite del repo porque el paquete agrega plumbing nativo
> que no necesitamos hasta que haya build de móvil.

---

## 5. Alertas de billing en COP

Para que no te llegue una factura inesperada de Firebase Blaze.

- [ ] Consola Google Cloud → **Billing** → **Budgets & alerts** → **Create
      budget**.
- [ ] Name: `cqg-monthly-cap`.
- [ ] Specify projects: `quality-group-app`.
- [ ] Amount: por ejemplo `20000` COP.
- [ ] Alerts: 50 %, 90 %, 100 %.
- [ ] Email recipients: tu correo (y el de quien te ayude con sysadmin).

---

## 6. Limpieza opcional del bundle web

El `main.dart.js` actual pesa ~5.5 MB sin gzip. Firebase Hosting ya sirve
gzipped (~1.5 MB efectivo), pero si ves arranque lento:

- [ ] **Bundlear Inter localmente** en lugar de tirarla de
      `fonts.gstatic.com` (evita un round-trip):
  1. Descarga `Inter-VariableFont_opsz,wght.ttf` desde
     https://rsms.me/inter/.
  2. Guárdalo en `assets/fonts/Inter.ttf`.
  3. En `pubspec.yaml`, añade:
     ```yaml
     fonts:
       - family: Inter
         fonts:
           - asset: assets/fonts/Inter.ttf
     ```
  4. En el theme, reemplaza `GoogleFonts.inter()` por
     `TextStyle(fontFamily: 'Inter')`. Quita la dependencia
     `google_fonts` si ya no se usa en otros lados.

- [ ] **Deferred imports** para Form Builder y Master Lists (módulos
      pesados que el admin no abre todos los días). No urgente; medir
      antes de hacerlo.

---

## 7. Comandos útiles del día a día

### Deploy completo

```bash
flutter build web --release
firebase deploy --only hosting
```

### Solo reglas / índices

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only firestore  # ambos
```

### Ver logs de hosting

```bash
firebase hosting:channel:list
```

### Rollback rápido

```bash
firebase hosting:rollback
```

---

## Pendientes / notas

(usar este espacio para anotar lo que dejes para después)

-
