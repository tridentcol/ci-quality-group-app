# Checklist para build iOS

Esta nota es para activar la app en iOS cuando tengas la Mac. El código
Dart ya está iOS-ready (todos los packages tienen soporte oficial); lo
que sigue es configuración del lado de Apple/Xcode.

---

## 1. Pre-requisitos en la Mac

Una vez (~30 min):

```sh
# Instalar Xcode desde el App Store (~20 GB, ~30 min descarga + install).
sudo xcode-select --install
sudo xcodebuild -license accept

# Cocoapods (manejador de dependencias nativas de iOS).
sudo gem install cocoapods

# Flutter ya configurado (lo mismo que en Windows).
flutter doctor   # debe mostrar Xcode + iOS toolchain en verde
```

## 2. Cuenta de Apple Developer

- $99 USD / año en https://developer.apple.com/programs/
- Si vas a distribuir solo internamente vía TestFlight, esto basta.
- Si quieres App Store público, suma ~3-5 días de revisión por update.

## 3. Configuración del proyecto en Xcode

Abre `ios/Runner.xcworkspace` (NO `Runner.xcodeproj`) y ajusta:

### 3a. Bundle Identifier
Runner target → General → Bundle Identifier:
```
com.ciqualitygroup.app
```
(o lo que prefieras; este string queda fijo de por vida en App Store).

### 3b. Display Name
```
CI Quality Group
```

### 3c. Signing & Capabilities
- "Automatically manage signing"
- Team: tu equipo de Apple Developer

### 3d. iOS Deployment Target
Mínimo: **iOS 13.0** (Firebase requiere 13+).

## 4. Firebase iOS

### 4a. Registrar la app en Firebase Console

Project Settings → "Add app" → iOS:
- Bundle ID: el mismo del paso 3a (`com.ciqualitygroup.app`).
- App nickname: "CI Quality Group iOS"
- Descarga `GoogleService-Info.plist`.

### 4b. Agregar el plist al proyecto

Arrastra `GoogleService-Info.plist` a `ios/Runner/` desde Xcode (no
desde Finder). Asegúrate de marcar:
- ☑ Copy items if needed
- ☑ Runner target

## 5. Info.plist — purpose strings

`ios/Runner/Info.plist`. Agrega ANTES de `</dict>` final:

```xml
<!-- Si en el futuro agregas el comprobante de transferencia: -->
<key>NSCameraUsageDescription</key>
<string>CI Quality Group necesita la cámara para tomar foto del comprobante de transferencia.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>CI Quality Group accede a tu galería para escoger el comprobante de transferencia.</string>
```

Si NO usas comprobante / cámara aún, puedes omitirlas. iOS solo crashea
si pides el permiso sin la string declarada.

## 6. Podfile

`ios/Podfile` debería tener:

```ruby
platform :ios, '13.0'
```

Si no, edítalo. Después en `ios/`:

```sh
pod install
```

## 7. Primera prueba en simulador

```sh
flutter pub get
cd ios && pod install && cd ..
open -a Simulator     # arranca un iPhone simulator
flutter run -d <device-id>   # `flutter devices` para ver el id
```

## 8. Build para device físico (TestFlight)

```sh
flutter build ipa --release
```

Genera `build/ios/ipa/ci_quality_group.ipa`. En Xcode:

- Product → Archive (compila para device)
- Distribute App → App Store Connect → Upload
- Espera ~15-30 min mientras Apple procesa

En App Store Connect:
- Crea la app con el bundle ID
- En TestFlight, agrega testers internos (hasta 100 sin revisión Apple)
- Los testers instalan el app **TestFlight** desde App Store y reciben
  un link/email para tu app.

## 9. Sin Mac propia: Codemagic

Si no quieres comprar Mac, sirve **Codemagic**:
- 500 minutos gratis/mes (suficiente para ~10 builds)
- Pegas certificados y provisioning profile como secretos
- Build se ejecuta en sus runners macOS

Setup en https://codemagic.io/ → conectar repo de GitHub.

---

## Diferencias iOS vs Android (lo que ya está manejado)

- ✅ `share_plus` con `sharePositionOrigin` — necesario para iPad, ya lo
  pasamos en `xlsx_export_service.dart`.
- ✅ Locale `es_CO` y formato 12h vía `Localizations.override` —
  funciona igual en iOS.
- ✅ `intl` con `initializeDateFormatting` — funciona igual.
- ✅ `timezone` package — funciona igual.
- ✅ Firestore offline persistence — funciona igual.
- ✅ Material widgets — se ven Material, no Cupertino. Para una app
  interna está bien (la consistencia con la web/Android es mayor valor
  que el "look nativo iOS").

## Lo que solo se valida en device real (después del primer build)

- Pulido visual con safe-areas en iPhone con notch (Dynamic Island).
- Comportamiento del time picker 12h con locale `es_CO` (puede
  comportarse ligeramente distinto que en Android).
- Performance del scroll en listas largas.
- Permisos de notificaciones / cámara cuando se agreguen.

Si algo falla solo en iOS, lo iteramos en ese momento. El código actual
no hace nada Android-specific que rompa en iOS.
