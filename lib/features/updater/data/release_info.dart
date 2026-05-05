import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

/// Snapshot del último APK publicado para Android. Vive en
/// Firestore: `app_metadata/release`.
class ReleaseInfo {
  const ReleaseInfo({
    required this.androidLatestBuild,
    required this.androidLatestVersion,
    required this.androidApkUrl,
    this.androidReleaseNotes,
    this.androidMinRequiredBuild = 0,
  });

  /// Build number del APK más nuevo subido (sube en cada release).
  /// Lo comparamos contra `currentBuild` de la app instalada.
  final int androidLatestBuild;

  /// Texto bonito ("1.0.1") para mostrar al usuario.
  final String androidLatestVersion;

  /// URL pública/firmada del APK en Firebase Storage.
  final String androidApkUrl;

  /// Texto que aparece en el banner y en la pantalla de update.
  final String? androidReleaseNotes;

  /// Si la app del usuario tiene un build menor que este, se considera
  /// "obligatorio actualizar" y el banner pasa a no-dismissable. Útil
  /// para parches de seguridad. 0 = no hay piso.
  final int androidMinRequiredBuild;

  static ReleaseInfo? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final build = (data['androidLatestBuild'] as num?)?.toInt();
    final version = data['androidLatestVersion'] as String?;
    final url = data['androidApkUrl'] as String?;
    if (build == null || version == null || url == null || url.isEmpty) {
      return null;
    }
    return ReleaseInfo(
      androidLatestBuild: build,
      androidLatestVersion: version,
      androidApkUrl: url,
      androidReleaseNotes: data['androidReleaseNotes'] as String?,
      androidMinRequiredBuild:
          (data['androidMinRequiredBuild'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Stream del doc Firestore. Re-suscribe cuando cambia la sesión para
/// que el listener no se quede con un token de auth viejo.
final releaseInfoProvider = StreamProvider<ReleaseInfo?>((ref) {
  ref.watch(authStateProvider);
  return FirebaseFirestore.instance
      .collection('app_metadata')
      .doc('release')
      .snapshots()
      .map((snap) => ReleaseInfo.fromMap(snap.data()));
});
