import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'release_info.dart';

enum UpdaterPhase {
  /// Sin info todavía o no aplica (ej. en web).
  idle,

  /// La versión instalada es igual o mayor que la publicada.
  upToDate,

  /// Hay un APK más nuevo y todavía no se descargó.
  available,

  /// Descarga en progreso.
  downloading,

  /// APK ya descargado, listo para instalar.
  downloaded,

  /// El instalador del sistema está abierto.
  installing,

  /// Falló la descarga / lectura de versión.
  error,
}

class UpdaterState {
  const UpdaterState({
    required this.phase,
    this.currentBuild,
    this.release,
    this.progress = 0.0,
    this.downloadedFile,
    this.errorMessage,
  });

  factory UpdaterState.initial() => const UpdaterState(phase: UpdaterPhase.idle);

  final UpdaterPhase phase;

  /// Build instalado en este dispositivo.
  final int? currentBuild;

  /// Info del último release publicado (puede ser null mientras carga).
  final ReleaseInfo? release;

  /// 0.0 — 1.0 mientras está descargando.
  final double progress;

  /// Path local del APK descargado.
  final String? downloadedFile;

  /// Mensaje legible para mostrar en el banner cuando hay error.
  final String? errorMessage;

  /// `true` si el build actual está por debajo del mínimo requerido —
  /// en ese caso el banner no debe ser ocultable.
  bool get isMandatory {
    final r = release;
    if (r == null || currentBuild == null) return false;
    return currentBuild! < r.androidMinRequiredBuild;
  }

  UpdaterState copyWith({
    UpdaterPhase? phase,
    int? currentBuild,
    ReleaseInfo? release,
    double? progress,
    String? downloadedFile,
    String? errorMessage,
    bool clearError = false,
    bool clearFile = false,
  }) {
    return UpdaterState(
      phase: phase ?? this.phase,
      currentBuild: currentBuild ?? this.currentBuild,
      release: release ?? this.release,
      progress: progress ?? this.progress,
      downloadedFile:
          clearFile ? null : (downloadedFile ?? this.downloadedFile),
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class UpdaterController extends StateNotifier<UpdaterState> {
  UpdaterController(this._ref) : super(UpdaterState.initial()) {
    if (!kIsWeb && Platform.isAndroid) {
      _bindToReleaseStream();
    }
    // En web/iOS/desktop dejamos el state en idle. La web ya tiene su
    // propio mecanismo de update (deploy a Firebase Hosting + service
    // worker). iOS se actualiza por TestFlight/App Store cuando llegue.
  }

  final Ref _ref;
  final _dio = Dio();
  CancelToken? _downloadToken;

  void _bindToReleaseStream() {
    _ref.listen<AsyncValue<ReleaseInfo?>>(
      releaseInfoProvider,
      (_, next) => next.whenData(_onRelease),
      fireImmediately: true,
    );
  }

  Future<void> _onRelease(ReleaseInfo? release) async {
    if (release == null) return;
    final pkg = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(pkg.buildNumber) ?? 0;

    if (release.androidLatestBuild <= currentBuild) {
      state = state.copyWith(
        phase: UpdaterPhase.upToDate,
        currentBuild: currentBuild,
        release: release,
        clearError: true,
      );
      return;
    }
    // Hay update — pero no descargamos automáticamente, esperamos
    // a que el usuario toque "Actualizar".
    state = state.copyWith(
      phase: UpdaterPhase.available,
      currentBuild: currentBuild,
      release: release,
      progress: 0,
      clearError: true,
      clearFile: true,
    );
  }

  /// Inicia la descarga del APK. Cuando termina, transiciona a `downloaded`
  /// pero NO abre el instalador automáticamente; eso lo hace `install()`
  /// con un tap explícito del usuario.
  Future<void> startDownload() async {
    final release = state.release;
    if (release == null) return;
    if (state.phase == UpdaterPhase.downloading) return;

    state = state.copyWith(
      phase: UpdaterPhase.downloading,
      progress: 0,
      clearError: true,
      clearFile: true,
    );

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/cqg-update-${release.androidLatestBuild}.apk';
      _downloadToken = CancelToken();
      await _dio.download(
        release.androidApkUrl,
        path,
        cancelToken: _downloadToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final p = received / total;
          state = state.copyWith(progress: p.clamp(0.0, 1.0));
        },
      );
      state = state.copyWith(
        phase: UpdaterPhase.downloaded,
        progress: 1.0,
        downloadedFile: path,
      );
    } on DioException catch (e) {
      // Cancelación voluntaria del usuario → vuelve a "available" sin error.
      if (CancelToken.isCancel(e)) {
        state = state.copyWith(
          phase: UpdaterPhase.available,
          progress: 0,
          clearFile: true,
          clearError: true,
        );
        return;
      }
      state = state.copyWith(
        phase: UpdaterPhase.error,
        errorMessage: 'Error de red: ${e.message ?? e.type.name}',
      );
    } catch (e) {
      state = state.copyWith(
        phase: UpdaterPhase.error,
        errorMessage: 'No se pudo descargar la actualización: $e',
      );
    }
  }

  void cancelDownload() {
    _downloadToken?.cancel('cancelled-by-user');
  }

  /// Lanza el instalador del sistema. Android muestra un diálogo
  /// pidiendo confirmación; el usuario tiene que tocar "Instalar".
  /// La app se cierra y se reinicia con la nueva versión.
  Future<void> install() async {
    final path = state.downloadedFile;
    if (path == null) return;
    state = state.copyWith(phase: UpdaterPhase.installing);
    try {
      final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        state = state.copyWith(
          phase: UpdaterPhase.downloaded,
          errorMessage:
              'No se pudo abrir el instalador: ${result.message}. '
              'Activa "Instalar apps desconocidas" para esta app en Ajustes.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        phase: UpdaterPhase.downloaded,
        errorMessage: 'Error al abrir el instalador: $e',
      );
    }
  }

  /// Permite al usuario "ocultar" el banner durante esta sesión cuando
  /// el update no es obligatorio. Próximo arranque vuelve a aparecer.
  void dismiss() {
    if (state.isMandatory) return;
    state = state.copyWith(phase: UpdaterPhase.upToDate, clearError: true);
  }

  @override
  void dispose() {
    _downloadToken?.cancel();
    _dio.close();
    super.dispose();
  }
}

final updaterControllerProvider =
    StateNotifierProvider<UpdaterController, UpdaterState>((ref) {
  return UpdaterController(ref);
});
