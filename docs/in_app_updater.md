# In-app updater — guía de release

La app revisa al arrancar el doc Firestore `app_metadata/release` y lo
compara con la versión instalada. Si hay un APK más nuevo publicado,
muestra un banner en cada home con botones "Actualizar / Instalar".

Esta guía describe cómo publicar una nueva versión.

---

## 1. Setup inicial (UNA SOLA VEZ)

### 1.1 Habilitar Firebase Storage

- [ ] Consola Firebase → **Storage** → **Get Started**
- [ ] Selecciona "Start in production mode" (las rules las afinamos abajo)
- [ ] Region: `us-east1` (más cerca, latencia menor para Colombia)

### 1.2 Configurar Storage rules

Edita `storage.rules` (créalo si no existe):

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // APKs públicos para que dio pueda descargarlos sin auth.
    // Solo el admin puede subir archivos nuevos.
    match /releases/{file=**} {
      allow read: if true;
      allow write: if request.auth != null
        && get(/databases/(default)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
```

Despliega:

```powershell
firebase deploy --only storage
```

Si te pregunta cuál `storage.rules` usar, agrégalo a `firebase.json`:

```json
{
  "storage": {
    "rules": "storage.rules"
  },
  ...
}
```

### 1.3 Crear el doc inicial

Solo la primera vez, crea el doc en Firestore para que la app no
explote por leer un doc inexistente. En la consola Firebase →
**Firestore Database** → **Start collection**:

- Collection ID: `app_metadata`
- Document ID: `release`
- Fields:
  - `androidLatestBuild` (number) = `1`
  - `androidLatestVersion` (string) = `"1.0.0"`
  - `androidApkUrl` (string) = `""` (vacío por ahora)
  - `androidReleaseNotes` (string) = `"Versión inicial"`
  - `androidMinRequiredBuild` (number) = `0`

Save.

---

## 2. Cada vez que publiques una versión nueva

### 2.1 Bump version en `pubspec.yaml`

```yaml
version: 1.0.1+2
```

Convención: `1.0.X+N` donde:
- `X` sube en cada release pública
- `N` (build number) **DEBE subir** sino Android rechaza el update con
  "version downgrade"

### 2.2 Build el APK

```powershell
flutter build apk --release --split-per-abi
```

Sale `app-arm64-v8a-release.apk` (~23 MB) en
`build\app\outputs\flutter-apk\`. Es el que vas a subir a Storage.

### 2.3 Sube el APK a Firebase Storage

**Opción A — Web (consola):**

- Firebase Console → **Storage** → click en folder `releases/` (créalo
  si no existe)
- **Upload file** → selecciona `app-arm64-v8a-release.apk`
- Renombrarlo a `cqg-v1.0.1-build2.apk` (descriptivo, evita pisar
  versiones anteriores)
- Una vez subido, click en el archivo → tab **File location** → copia
  el **Download URL** (el largo, con token)

**Opción B — CLI:**

```powershell
# Si no la tienes:
npm install -g firebase-tools

# Subir
firebase storage:upload `
  build\app\outputs\flutter-apk\app-arm64-v8a-release.apk `
  --location releases/cqg-v1.0.1-build2.apk
```

(Después igual hay que ir a la consola para copiar el download URL —
la CLI no lo imprime.)

### 2.4 Actualiza el doc Firestore

Consola → **Firestore Database** → `app_metadata/release` → **Edit**:

| Campo | Nuevo valor |
|---|---|
| `androidLatestBuild` | `2` (el `+N` del pubspec) |
| `androidLatestVersion` | `"1.0.1"` |
| `androidApkUrl` | URL del paso 2.3 |
| `androidReleaseNotes` | `"Fix duplicados en cliente/recibe + setup updater in-app"` |
| `androidMinRequiredBuild` | `0` (déjalo así salvo que sea un parche crítico de seguridad — entonces lo igualas a `androidLatestBuild` para forzar) |

Save.

### 2.5 Verificación

- Abre la app en tu propio teléfono (la versión vieja, sin actualizar)
- Espera 5-10 segundos en cualquier home → debe aparecer el banner
  "Versión 1.0.1 disponible — Actualizar"
- Tap en "Actualizar" → barra de progreso → "Listo para instalar"
- Tap "Instalar" → Android pide confirmación → instalas → app reinicia
  con la nueva versión

Si el banner no aparece, revisa el doc Firestore + que el
`androidLatestBuild` sea estrictamente mayor que el `+N` del pubspec
local instalado.

---

## 3. Updates obligatorios (forzar)

Si hay un parche que TODO trabajador tiene que instalar (ej. fix de
seguridad o bug que rompe data), pones:

```
androidMinRequiredBuild: 2   // == androidLatestBuild
```

El banner pasa a no-dismissable: el botón de cerrar (X) desaparece, y
en la pantalla de update no se puede tocar "Volver". El trabajador
tiene que actualizar para seguir usando la app.

---

## 4. Rollback (si una release rompe algo)

Si publicas un APK con un bug feo:

1. Sube el APK ANTERIOR a Storage con un nombre nuevo (ej.
   `cqg-v1.0.1-build3-rollback.apk`)
2. En Firestore, **incrementa** `androidLatestBuild` (a 4 si la mala
   era 3) y pon `androidApkUrl` apuntando al binario anterior.
3. Los trabajadores reciben el "update" que en realidad los devuelve
   a la versión estable.

> Android no permite "downgrade" estricto (instalar un APK con
> `versionCode` menor sobre uno mayor). Por eso siempre se INCREMENTA
> el `androidLatestBuild` aunque el binario sea uno viejo.

---

## 5. Costos (Firebase Storage)

- Free tier: 5 GB storage + 1 GB/día de descarga
- 10 trabajadores × 23 MB APK = 230 MB por release → ~4 releases/día
  caben en el tier gratuito sin problema
- Por encima de eso: `~$0.026/GB descargado` (Blaze plan)

Como compañía interna con releases ocasionales, esto es prácticamente
gratis indefinidamente.
