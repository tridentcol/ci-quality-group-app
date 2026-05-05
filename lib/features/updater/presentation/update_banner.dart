import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/updater_controller.dart';

/// Banner pequeño que aparece arriba de cada home screen cuando hay un
/// APK más nuevo publicado. Estados:
///  - `available`     → "v1.0.1 disponible" + botón "Actualizar"
///  - `downloading`   → barra de progreso
///  - `downloaded`    → "Listo para instalar" + botón "Instalar"
///  - `error`         → mensaje + "Reintentar"
///  - resto           → no se renderiza nada (el widget queda como
///                      SizedBox.shrink, no ocupa espacio).
///
/// Tap en "Actualizar" navega a `/update` que muestra la pantalla
/// completa con barra de progreso. La descarga sigue corriendo si el
/// usuario navega fuera; el banner refleja el estado en cada home.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updaterControllerProvider);
    final theme = Theme.of(context);

    if (state.phase == UpdaterPhase.idle ||
        state.phase == UpdaterPhase.upToDate ||
        state.phase == UpdaterPhase.installing) {
      return const SizedBox.shrink();
    }

    final release = state.release;
    final colors = theme.colorScheme;
    final mandatory = state.isMandatory;

    Widget content;
    switch (state.phase) {
      case UpdaterPhase.available:
        content = Row(
          children: [
            Icon(Icons.system_update_outlined, color: colors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Versión ${release?.androidLatestVersion ?? 'nueva'} disponible',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (release?.androidReleaseNotes != null &&
                      release!.androidReleaseNotes!.isNotEmpty)
                    Text(
                      release.androidReleaseNotes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: () => context.push('/update'),
              child: const Text('Actualizar'),
            ),
            if (!mandatory)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Ocultar hasta el próximo arranque',
                onPressed: () =>
                    ref.read(updaterControllerProvider.notifier).dismiss(),
              ),
          ],
        );
        break;
      case UpdaterPhase.downloading:
        content = Row(
          children: [
            Icon(Icons.download, color: colors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Descargando v${release?.androidLatestVersion ?? ''}…',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: state.progress > 0 ? state.progress : null,
                    minHeight: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
        break;
      case UpdaterPhase.downloaded:
        content = Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: colors.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Listo para instalar v${release?.androidLatestVersion ?? ''}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              onPressed: () =>
                  ref.read(updaterControllerProvider.notifier).install(),
              child: const Text('Instalar'),
            ),
          ],
        );
        break;
      case UpdaterPhase.error:
        content = Row(
          children: [
            Icon(Icons.error_outline, color: colors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.errorMessage ?? 'Error en la actualización',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.error),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(updaterControllerProvider.notifier).startDownload(),
              child: const Text('Reintentar'),
            ),
          ],
        );
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: state.phase == UpdaterPhase.error
            ? colors.error.withValues(alpha: 0.08)
            : colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (state.phase == UpdaterPhase.error
                  ? colors.error
                  : colors.primary)
              .withValues(alpha: 0.3),
        ),
      ),
      child: content,
    );
  }
}
