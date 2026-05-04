import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_controller.dart';

/// Botón compacto para AppBars: ícono que cambia con animación según el
/// modo activo, tap abre menú con las tres opciones (Sistema / Claro /
/// Oscuro). Tooltip muestra el modo actual para que sea descubrible.
class ThemeModeIconButton extends ConsumerWidget {
  const ThemeModeIconButton({super.key, this.color});

  /// Override del color del ícono. Por defecto hereda del IconTheme/AppBar.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return _ThemeModePopupMenu(
      mode: mode,
      onSelected: (m) => ref.read(themeModeProvider.notifier).set(m),
      iconColor: color,
    );
  }
}

class _ThemeModePopupMenu extends StatelessWidget {
  const _ThemeModePopupMenu({
    required this.mode,
    required this.onSelected,
    this.iconColor,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onSelected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Tema: ${themeModeLabel(mode)}',
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween<double>(begin: 0.85, end: 1).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Icon(
          themeModeIcon(mode),
          key: ValueKey(mode),
          color: iconColor,
        ),
      ),
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final m in ThemeMode.values)
          PopupMenuItem<ThemeMode>(
            value: m,
            child: Row(
              children: [
                Icon(themeModeIcon(m), size: 18),
                const SizedBox(width: 12),
                Expanded(child: Text(themeModeLabel(m))),
                if (m == mode) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// ListTile para drawers / paneles laterales. Muestra el modo actual y
/// abre el mismo menú que el icon button al tap.
class ThemeModeListTile extends ConsumerWidget {
  const ThemeModeListTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return ListTile(
      leading: Icon(themeModeIcon(mode)),
      title: const Text('Tema'),
      subtitle: Text(themeModeLabel(mode)),
      trailing: const Icon(Icons.unfold_more_rounded, size: 18),
      onTap: () async {
        final selected = await _pickModeSheet(context, mode);
        if (selected != null) {
          await ref.read(themeModeProvider.notifier).set(selected);
        }
      },
    );
  }
}

/// Botón compacto para la NavigationRail del admin: respeta el ancho
/// (icono solo cuando colapsada, icono + label cuando extended). Cicla
/// los tres estados con cada tap; long-press abre el bottom sheet.
class ThemeModeRailButton extends ConsumerWidget {
  const ThemeModeRailButton({super.key, required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final color = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => ref.read(themeModeProvider.notifier).cycle(),
          onLongPress: () async {
            final selected = await _pickModeSheet(context, mode);
            if (selected != null) {
              await ref.read(themeModeProvider.notifier).set(selected);
            }
          },
          child: Tooltip(
            message: 'Tema: ${themeModeLabel(mode)} (toca para cambiar)',
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: extended ? 12 : 8,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: Tween<double>(begin: 0.85, end: 1).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      themeModeIcon(mode),
                      key: ValueKey(mode),
                      color: color,
                      size: 22,
                    ),
                  ),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tema · ${themeModeLabel(mode)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<ThemeMode?> _pickModeSheet(BuildContext context, ThemeMode current) {
  // RadioGroup ancestor: el patrón nuevo de Material reemplaza
  // groupValue/onChanged en cada Radio* por un único RadioGroup que
  // gestiona el grupo. Aquí el "valor" es la opción presionada y al
  // pop devolvemos esa opción al caller.
  return showModalBottomSheet<ThemeMode>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (v) => Navigator.of(sheetContext).pop(v),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tema',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            for (final m in ThemeMode.values)
              RadioListTile<ThemeMode>(
                value: m,
                title: Row(
                  children: [
                    Icon(themeModeIcon(m), size: 20),
                    const SizedBox(width: 12),
                    Text(themeModeLabel(m)),
                  ],
                ),
                subtitle: Text(themeModeDescription(m)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

IconData themeModeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'Sistema',
      ThemeMode.light => 'Claro',
      ThemeMode.dark => 'Oscuro',
    };

String themeModeDescription(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'Sigue la configuración del dispositivo.',
      ThemeMode.light => 'Fondo claro, ideal de día.',
      ThemeMode.dark => 'Fondo oscuro, descansa la vista de noche.',
    };
