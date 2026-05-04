# Guía de release Android — CI Quality Group

Pasos para generar el APK firmado de release y distribuirlo a los
trabajadores. La parte de Dart/Flutter ya está lista en el repo; aquí
se documenta lo que hay que hacer en `android/` (que **vive solo en
tu máquina**, no en el repo) y los comandos del build.

> Lee de arriba abajo la primera vez. Las próximas releases solo
> ejecutas la sección 5 (Build) y 6 (Distribuir).

---

## 1. Generar iconos y splash nativos

Una vez después de hacer `git pull` y `flutter pub get`. Vuelve a
correr si cambiaste `assets/images/logo_*.png` o la config en
`pubspec.yaml`.

```powershell
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Esto sobrescribe (entre otros):
- `android/app/src/main/res/mipmap-*` → iconos del launcher
- `android/app/src/main/res/drawable*/launch_background.xml` → splash
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/*`

> Esos archivos están sin trackear por git (cada quien los regenera),
> así que no aparecen en el diff.

---

## 2. Nombre de la app en el launcher

Por defecto Android muestra el nombre del proyecto (`ci_quality_group`).
Para que aparezca "CI Quality Group" bonito en el cajón:

Edita `android/app/src/main/AndroidManifest.xml`. Busca la línea con
`android:label`:

```xml
<application
    android:label="ci_quality_group"
    ...
```

Cámbiala por:

```xml
<application
    android:label="CI Quality Group"
    ...
```

> NO cambies `android:name` (es el class name de la actividad nativa)
> ni el `applicationId` del `build.gradle.kts` (eso rompería el link
> con Firebase).

---

## 3. Crear el keystore de release (UNA SOLA VEZ)

El APK que sale de `flutter run` está firmado con un keystore de debug
genérico. Para distribuir necesitas **un keystore propio** que Android
usa para verificar que las próximas versiones de la app vienen del
mismo desarrollador. Si lo pierdes, no puedes publicar updates de esa
misma app — guárdalo en un lugar seguro (idealmente respaldado a un
gestor de contraseñas o disco externo cifrado).

```powershell
# Cambia <ruta_segura> por algo como C:\Users\ruben\.android-keystores\
keytool -genkey -v `
  -keystore "$env:USERPROFILE\cqg-release.jks" `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias cqg
```

Te va a pedir:
- Password del keystore (anótala)
- Nombre, organización, ciudad, país (no es crítico, pon datos reales)
- Password de la key (puede ser la misma del keystore para simplicidad)

Al final tendrás un archivo `cqg-release.jks` en tu home.

> **Nunca commitees** este `.jks` ni las passwords al repo. El
> `.gitignore` ya cubre `*.jks` y `key.properties`.

---

## 4. Conectar el keystore con el build de Flutter

### 4.1 Crear `android/key.properties`

Archivo nuevo en `android/key.properties` (NO lo commitees, ya está
en .gitignore):

```properties
storePassword=tu_password_del_keystore
keyPassword=tu_password_de_la_key
keyAlias=cqg
storeFile=C:/Users/ruben/cqg-release.jks
```

> Usa `/` en la ruta aunque sea Windows — Gradle lo maneja mejor.

### 4.2 Editar `android/app/build.gradle.kts`

Abre el archivo y busca el bloque `android { ... }`. Necesitas tres
cambios:

**A) Importar Properties al principio del archivo** (antes de
`plugins {}`):

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

**B) Dentro de `android { ... }`, agregar `signingConfigs`** (antes
del `buildTypes`):

```kotlin
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String?
        keyPassword = keystoreProperties["keyPassword"] as String?
        storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
        storePassword = keystoreProperties["storePassword"] as String?
    }
}
```

**C) En `buildTypes { release { ... } }`, apuntar a esa signingConfig**:

```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        // Opcional pero recomendado: shrink + obfuscate
        isMinifyEnabled = true
        isShrinkResources = true
    }
}
```

Si ya había una línea `signingConfig = signingConfigs.getByName("debug")`
(viene por defecto), reemplázala por `getByName("release")`.

---

## 5. Build del APK

```powershell
flutter clean
flutter pub get
flutter build apk --release
```

El APK queda en:

```
build\app\outputs\flutter-apk\app-release.apk
```

Si quieres APKs separados por arquitectura (más pequeños, ~20 MB cada
uno en lugar de ~50 MB del universal), agrega `--split-per-abi`:

```powershell
flutter build apk --release --split-per-abi
```

Salen tres:
- `app-armeabi-v7a-release.apk` (Android viejo, ~20 MB)
- `app-arm64-v8a-release.apk` (la mayoría de teléfonos modernos)
- `app-x86_64-release.apk` (emuladores, raro en producción)

Para distribuir a trabajadores, **manda el `app-arm64-v8a-release.apk`** —
funciona en cualquier teléfono Android de los últimos 6 años.

---

## 6. Probar el release antes de mandarlo

Importante: el build release pasa por R8 (shrinking + obfuscation) y a
veces stripea algo de Firebase que solo se ve en runtime. Pruébalo en
tu propio teléfono primero:

```powershell
# Conecta tu teléfono por USB con depuración activada.
flutter install --release
```

Verifica:
- [ ] Login funciona
- [ ] Listar ventas funciona
- [ ] Crear una venta funciona
- [ ] Listar horas funciona
- [ ] Marcar entrada/salida funciona
- [ ] Export Excel funciona y comparte el archivo
- [ ] Cerrar sesión y volver a entrar (sin permission-denied)

Si algo falla solo en release, abre `android/app/build.gradle.kts` y
desactiva temporalmente `isMinifyEnabled = false` para confirmar que
es R8. Si lo es, agrega keep rules en `android/app/proguard-rules.pro`.

---

## 7. Distribuir a los trabajadores

### Opción A: Mandar el APK directamente (lo más simple)

1. Sube el `app-arm64-v8a-release.apk` a Google Drive / WhatsApp.
2. El trabajador lo baja en su teléfono.
3. Antes de instalar, en su teléfono activa **Settings → Apps →
   Special access → Install unknown apps** → permite a Drive/WhatsApp.
4. Toca el APK → Install.
5. Para actualizar después, repites el proceso (manda el APK nuevo,
   ellos tocan Install y se sobrescribe — manteniendo los datos).

> El APK debe estar firmado con **el mismo keystore** que el anterior,
> sino Android lo trata como otra app y pide desinstalar primero
> (pierde datos locales).

### Opción B: Firebase App Distribution (recomendado para >5 usuarios)

Te ahorra mandar APKs por WhatsApp cada vez. Los trabajadores reciben
un email/notif cuando subes una versión nueva y la instalan con un tap.

#### Setup inicial (una vez)

```powershell
# Instala la CLI
npm install -g firebase-tools
firebase login
```

En la consola Firebase → **App Distribution** → Crear un grupo de
testers (ej. `trabajadores-cqg`) y agregar los emails.

#### Cada vez que quieras distribuir

```powershell
firebase appdistribution:distribute `
  build\app\outputs\flutter-apk\app-arm64-v8a-release.apk `
  --app 1:624883853247:android:ab8d142b4ab821086b630a `
  --release-notes "Notas de la versión 1.0.0 — primera release" `
  --groups "trabajadores-cqg"
```

> El `--app` es el `mobilesdk_app_id` de Firebase (tu Android app).
> Lo encuentras en Project Settings → General → Tus apps → Android.

Los trabajadores reciben un email con un link, instalan **una sola vez**
la app de "Tester" de Firebase, y a partir de ahí cada update llega
como notificación automática.

---

## 8. Próximas releases

```powershell
# 1. Bump version en pubspec.yaml (ej. 1.0.0+1 → 1.0.1+2)
#    Convención: 1.0.X+N donde X es la release pública y N el build number.

# 2. Build
flutter build apk --release --split-per-abi

# 3. Distribuir (App Distribution o WhatsApp del APK).
```

> El `+N` (build number) **debe subir** en cada release, sino Android
> rechaza la actualización con "downgrade not allowed".
