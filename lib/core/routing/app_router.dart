import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/hours/presentation/hours_entry_screen.dart';
import '../../features/sales/presentation/sales_entry_screen.dart';
import '../constants/roles.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  final profile = ref.watch(currentProfileProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final loggedIn = auth.valueOrNull != null;
      final loadingProfile = loggedIn && profile.isLoading;
      final atLogin = state.matchedLocation == '/login';
      final atSplash = state.matchedLocation == '/';

      if (!loggedIn) {
        return atLogin ? null : '/login';
      }

      if (loadingProfile) {
        return atSplash ? null : '/';
      }

      final user = profile.valueOrNull;
      if (user == null || !user.active) {
        // Logged in pero sin perfil válido → mantenemos en splash mostrando aviso.
        return atSplash ? null : '/';
      }

      final home = switch (user.role) {
        AppRole.admin => '/admin',
        AppRole.sales => '/sales',
        AppRole.hours => '/hours',
      };

      if (atLogin || atSplash) return home;

      // Evita que un rol entre a una sección que no le corresponde.
      if (state.matchedLocation.startsWith('/admin') && user.role != AppRole.admin) {
        return home;
      }
      if (state.matchedLocation.startsWith('/sales') && user.role != AppRole.sales) {
        return home;
      }
      if (state.matchedLocation.startsWith('/hours') && user.role != AppRole.hours) {
        return home;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(path: '/sales', builder: (_, __) => const SalesEntryScreen()),
      GoRoute(path: '/hours', builder: (_, __) => const HoursEntryScreen()),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(currentProfileProvider, (_, __) => notifyListeners());
  }
}

class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: profile.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'No se pudo cargar tu perfil.\n$e',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
          data: (user) {
            if (user == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'Tu cuenta no tiene un perfil asignado. Contacta al administrador.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.read(authRepositoryProvider).signOut(),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      ),
    );
  }
}
