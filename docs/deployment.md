# Deployment

Build de release y deploy. Para detalles específicos de plataforma ver
`android_release_guide.md` e `ios_build_checklist.md`.

## Pre-deploy checklist

1. `flutter analyze` pasa con 0 errores.
2. Cambios probados manualmente en emulador / chrome.
3. `pubspec.yaml` bumpeado (`version: X.Y.Z+N`).
4. `CHANGELOG.md` actualizado con la entrada nueva.
5. Commit y push hechos en la rama de desarrollo.

## Web

```powershell
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
firebase deploy --only hosting
```

Flags:
- `--no-tree-shake-icons` — empaqueta el icon font completo (~150 KB
  extra). Sin esto, iconos referenciados indirectamente desaparecen.
- `--no-wasm-dry-run` — silencia el warning del dry-run wasm de
  Flutter 3.41+. No afecta el build.

URL: `https://quality-group-app.web.app`

**Después del deploy:** hard refresh en el navegador (`Ctrl+Shift+R`).
Si los usuarios reportan que ven la versión vieja, contales del hard
refresh — el SW de Flutter cachea agresivamente.

### Si Firestore rules cambiaron

```powershell
firebase deploy --only firestore:rules
```

Propaga en 30s–1min. Hacé este deploy **antes** del de hosting si el
código nuevo asume permisos nuevos.

### Si firebase.json se rompe

`firebase init` lo sobrescribe con un template vacío que destruye los
cache headers. Si pasó:

```powershell
git checkout firebase.json
```

## Android

### Setup inicial (solo primera vez)

Ver `docs/android_release_guide.md` para crear el keystore
`cqg-release.jks` y `android/key.properties`.

### Build de release

```powershell
flutter build apk --release --split-per-abi
```

Output:
- `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` (~22 MB) ← **el que distribuís**
- `build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk` (~22 MB) — celulares viejos (raro)
- `build\app\outputs\flutter-apk\app-x86_64-release.apk` (~22 MB) — emuladores / tablets x86

### Alternativa: APK universal

```powershell
flutter build apk --release
```

Output: `build\app\outputs\flutter-apk\app-release.apk` (~63 MB).
Funciona en cualquier arquitectura. Más pesado pero más simple.

### Distribución

- Para el equipo interno: mandá `app-arm64-v8a-release.apk` por
  WhatsApp / Drive. Cubre el 99 % de celulares modernos.
- **Primera vez con keystore nuevo**: avisá que tienen que desinstalar
  la versión anterior. Después de eso, las actualizaciones se instalan
  encima sin desinstalar.
- **`versionCode` debe ser mayor** que la versión instalada. Si el
  usuario tiene `1.0.3+4` y le mandás otro `+4`, Android dice "ya
  instalado" y no actualiza. Bumpeá en cada release.

## iOS

Ver `docs/ios_build_checklist.md`. Actualmente no se está distribuyendo
iOS — el equipo usa Android. Si se necesita, hay que coordinar
TestFlight o App Store.

## Tag de release en Git

Opcional pero recomendado:

```powershell
git tag -a vX.Y.Z -m "Release X.Y.Z+N — descripción corta"
git push origin vX.Y.Z
```

Aparece en GitHub bajo "Tags" y opcionalmente se puede promover a
"Release" formal con notas + APK adjunto.

## Rollback de un release

### Web

Firebase Hosting guarda versiones previas. Desde Firebase Console:
1. Hosting → Quality Group → Release History.
2. Click en una versión previa → "Rollback".

Tarda <1 min. Inmediato para los usuarios después del próximo refresh.

### Android

No hay rollback automático. Si un APK quedó mal:

1. Identificar la versión última que funcionaba.
2. `git checkout vX.Y.Z` (el tag de esa versión, si existe).
3. `flutter clean && flutter pub get`.
4. **Bumpear el versionCode** a uno mayor que el roto (no podés
   distribuir el viejo "como está", Android lo rechaza por mismo
   versionCode).
5. Build + redistribuir.

## Verificación post-deploy

### Web

1. Abrí `https://quality-group-app.web.app` en incógnito.
2. Verificá login con cada rol (admin, sales, hours, auditor).
3. Smoke test del happy path de cada rol:
   - Admin → métricas cargan + filtro de rango funciona.
   - Sales → nueva venta + lista de ventas.
   - Hours → abrir/cerrar turno de un trabajador.
   - Auditor → dashboard filtrado muestra solo lo correspondiente.

### APK

1. Instalá en un device real o emulador.
2. Mismo smoke test que en web.
3. Verifica funcionalidad nativa que no aplica en web:
   - Export xlsx → comparte por WhatsApp / Drive.
   - (No hay más nativas — el in-app updater se removió.)

## Comandos de emergencia

| Situación | Comando |
|-----------|---------|
| Build falla con errores raros | `flutter clean && flutter pub get` |
| Web no levanta — verificar | `flutter run -d chrome` |
| Verificar reglas en consola | `firebase firestore:rules:get` |
| Ver últimos deploys de hosting | `firebase hosting:channel:list` |
| Cancelar deploy en curso | `Ctrl+C` (es atómico, no rompe nada) |
