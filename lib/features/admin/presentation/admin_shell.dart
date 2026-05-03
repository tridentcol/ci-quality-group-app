import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/app_logo.dart';
import '../../auth/data/auth_repository.dart';

/// Wrapper responsive para todas las rutas `/admin/*`.
///
///   - **Desktop (≥ 1024 px)**: NavigationRail permanente a la izquierda
///     con todos los módulos del admin. El contenido del child queda
///     en la zona derecha. La nav siempre está visible mientras el admin
///     navega entre métricas, ventas, horas, etc.
///   - **Tablet (700-1023 px)**: NavigationRail compacta sin labels.
///   - **Mobile (< 700 px)**: el shell es transparente; cada pantalla
///     mantiene su propio Scaffold con AppBar y un Drawer extra que
///     se abre con el ícono de menú en el AppBar.
///
/// La idea es que en mobile la experiencia es la misma a la que ya están
/// acostumbrados (cada pantalla es una pantalla), pero en web/desktop el
/// admin tiene navegación persistente.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child, required this.location});

  final Widget child;

  /// Path actual (ej. `/admin/sales`). Sirve para resaltar el item
  /// activo en la rail/drawer.
  final String location;

  static const _navItems = <_AdminNavItem>[
    _AdminNavItem(
      label: 'Métricas',
      icon: Icons.insights_outlined,
      route: '/admin',
    ),
    _AdminNavItem(
      label: 'Ventas',
      icon: Icons.receipt_long_outlined,
      route: '/admin/sales',
    ),
    _AdminNavItem(
      label: 'Horas',
      icon: Icons.schedule_outlined,
      route: '/admin/hours',
    ),
    _AdminNavItem(
      label: 'Trabajadores',
      icon: Icons.engineering_outlined,
      route: '/admin/workers',
    ),
    _AdminNavItem(
      label: 'Usuarios',
      icon: Icons.manage_accounts_outlined,
      route: '/admin/users',
    ),
    _AdminNavItem(
      label: 'Listas maestras',
      icon: Icons.list_alt_outlined,
      route: '/admin/master-lists',
    ),
    _AdminNavItem(
      label: 'Jornada',
      icon: Icons.tune_outlined,
      route: '/admin/settings/schedule',
    ),
    _AdminNavItem(
      label: 'Constructor',
      icon: Icons.dynamic_form_outlined,
      route: '/admin/form-builder',
    ),
  ];

  /// Índice del item activo en `_navItems` según el `location`. Usa el
  /// match más específico (más caracteres) para que `/admin/sales/123`
  /// también marque "Ventas".
  int get _selectedIndex {
    var bestIdx = 0;
    var bestLen = 0;
    for (var i = 0; i < _navItems.length; i++) {
      final route = _navItems[i].route;
      if (location == route ||
          location.startsWith('$route/') ||
          (route == '/admin' && location == '/admin')) {
        if (route.length > bestLen) {
          bestIdx = i;
          bestLen = route.length;
        }
      }
    }
    return bestIdx;
  }

  void _go(BuildContext context, int index) {
    final route = _navItems[index].route;
    if (location == route) return;
    context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          // Wide o tablet: rail persistente a la izquierda.
          final extended = constraints.maxWidth >= 1100;
          return Scaffold(
            body: Row(
              children: [
                _AdminRail(
                  items: _navItems,
                  selectedIndex: _selectedIndex,
                  onSelected: (i) => _go(context, i),
                  extended: extended,
                  onSignOut: () => ref.read(authRepositoryProvider).signOut(),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: child),
              ],
            ),
          );
        }
        // Mobile: el shell es transparente. Cada pantalla muestra su
        // propio Scaffold/AppBar como antes, y el drawer se obtiene
        // via `AdminNavigationDrawer` si la pantalla decide ofrecerlo.
        return child;
      },
    );
  }
}

/// Devuelve el `AdminNavigationDrawer` cuando la pantalla es estrecha
/// (< 700 px), o `null` cuando es wide. En wide, la `NavigationRail`
/// del `AdminShell` ya provee la nav y el drawer extra solo agregaría
/// un botón hamburguesa redundante en cada AppBar.
///
/// Cada Scaffold de pantalla admin lo usa en su slot `drawer:`:
/// ```dart
/// Scaffold(
///   drawer: adminDrawerOrNull(context, '/admin/users'),
///   appBar: AppBar(title: const Text('Usuarios')),
///   ...
/// )
/// ```
Widget? adminDrawerOrNull(BuildContext context, String location) {
  if (MediaQuery.sizeOf(context).width >= 700) return null;
  return AdminNavigationDrawer(location: location);
}

/// Drawer reusable para mobile. Las pantallas que quieran exponer la
/// navegación admin pueden usarlo como `Scaffold.drawer`.
class AdminNavigationDrawer extends ConsumerWidget {
  const AdminNavigationDrawer({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.primary),
              child: Row(
                children: [
                  const AppLogo(size: 48, showWordmark: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Panel admin',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in AdminShell._navItems)
                    ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      selected: _matches(location, item.route),
                      selectedTileColor:
                          theme.colorScheme.primary.withValues(alpha: 0.1),
                      onTap: () {
                        Navigator.pop(context);
                        if (location != item.route) {
                          context.go(item.route);
                        }
                      },
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: const Text('Cerrar sesión'),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static bool _matches(String location, String route) {
    if (route == '/admin') return location == '/admin';
    return location == route || location.startsWith('$route/');
  }
}

class _AdminNavItem {
  const _AdminNavItem({
    required this.label,
    required this.icon,
    required this.route,
  });
  final String label;
  final IconData icon;
  final String route;
}

class _AdminRail extends StatelessWidget {
  const _AdminRail({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.extended,
    required this.onSignOut,
  });

  final List<_AdminNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        color: theme.colorScheme.surface,
        width: extended ? 220 : 80,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 36, showWordmark: false),
                  if (extended) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'CI Quality',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final selected = i == selectedIndex;
                  return _RailItem(
                    item: item,
                    selected: selected,
                    extended: extended,
                    onTap: () => onSelected(i),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            _RailItem(
              item: const _AdminNavItem(
                label: 'Cerrar sesión',
                icon: Icons.logout_outlined,
                route: '__signout__',
              ),
              selected: false,
              extended: extended,
              onTap: onSignOut,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final _AdminNavItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
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
                Icon(item.icon, color: color, size: 22),
                if (extended) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
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
    );
  }
}
