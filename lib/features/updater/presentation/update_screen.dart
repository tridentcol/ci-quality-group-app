import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/theme_mode_toggle.dart';
import '../data/updater_controller.dart';

/// Pantalla dedicada para gestionar la descarga + instalación del APK.
/// Se llega tocando "Actualizar" en el [UpdateBanner].
///
/// La descarga arranca automáticamente al entrar (si está disponible y
/// todavía no se descargó). La pantalla muestra el progreso, las release
/// notes y un botón "Instalar" cuando termina.
class UpdateScreen extends ConsumerStatefulWidget {
  const UpdateScreen({super.key});

  @override
  ConsumerState<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends ConsumerState<UpdateScreen> {
  @override
  void initState() {
    super.initState();
    // Lanza la descarga automáticamente al entrar si todavía no está
    // ni descargada ni en progreso.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(updaterControllerProvider);
      if (state.phase == UpdaterPhase.available) {
        ref.read(updaterControllerProvider.notifier).startDownload();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updaterControllerProvider);
    final theme = Theme.of(context);
    final release = state.release;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Actualizar app'),
        actions: const [ThemeModeIconButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.system_update,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              release == null
                  ? 'Sin información de versión'
                  : 'Nueva versión ${release.androidLatestVersion}',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (release?.androidReleaseNotes != null &&
                release!.androidReleaseNotes!.isNotEmpty)
              Text(
                release.androidReleaseNotes!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 32),
            _PhaseBlock(state: state),
            const Spacer(),
            if (state.phase == UpdaterPhase.downloaded)
              FilledButton.icon(
                onPressed: () =>
                    ref.read(updaterControllerProvider.notifier).install(),
                icon: const Icon(Icons.download_done),
                label: const Text('Instalar ahora'),
              ),
            if (state.phase == UpdaterPhase.error)
              FilledButton.icon(
                onPressed: () => ref
                    .read(updaterControllerProvider.notifier)
                    .startDownload(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar descarga'),
              ),
            const SizedBox(height: 12),
            if (!state.isMandatory)
              TextButton(
                onPressed: () {
                  if (state.phase == UpdaterPhase.downloading) {
                    ref
                        .read(updaterControllerProvider.notifier)
                        .cancelDownload();
                  }
                  context.pop();
                },
                child: Text(
                  state.phase == UpdaterPhase.downloading
                      ? 'Cancelar y volver'
                      : 'Volver',
                ),
              ),
            if (state.isMandatory)
              Text(
                'Esta actualización es obligatoria — no se puede omitir.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

class _PhaseBlock extends StatelessWidget {
  const _PhaseBlock({required this.state});

  final UpdaterState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (state.phase) {
      case UpdaterPhase.downloading:
        return Column(
          children: [
            LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              minHeight: 6,
            ),
            const SizedBox(height: 8),
            Text(
              'Descargando… ${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
      case UpdaterPhase.downloaded:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Descargado, listo para instalar',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
      case UpdaterPhase.error:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            state.errorMessage ?? 'Error desconocido',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        );
      case UpdaterPhase.installing:
        return Text(
          'Abriendo el instalador del sistema…',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
