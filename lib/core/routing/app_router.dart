import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/master_list_detail_screen.dart';
import '../../features/admin/presentation/master_lists_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/hours/presentation/hours_entry_screen.dart';
import '../../features/sales/presentation/sale_detail_screen.dart';
import '../../features/sales/presentation/sale_form_screen.dart';
import '../../features/sales/presentation/sales_home_screen.dart';
import '../../features/sales/presentation/sales_list_screen.dart';
import '../constants/roles.dart';

/// Notifier que GoRouter escucha. Lo creamos UNA sola vez y lo reusamos
/// para evitar acumular listeners cada vez que cambia el estado de auth.
final _routerRefreshProvider = Provider<ChangeNotifier>((ref) {
  final notifier = ChangeNotifier();
  ref.listen(authStateProvider, (_, __) {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    notifier.notifyListeners();
  });
  ref.listen(currentProfileProvider, (_, __) {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    notifier.notifyListeners();
  });
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      // Leemos los estados con `read` para no rebuiildear el provider del
      // router cuando cambia auth o profile (de eso se encarga el listenable).
      final auth = ref.read(authStateProvider);
      final profile = ref.read(currentProfileProvider);

      final loggedIn = auth.valueOrNull != null;
      final loadingProfile = loggedIn && profile.isLoading;
      final atLogin = state.matchedLocation == '/login';
      final atSplash = state.matchedLocation == '/';

      if (!loggedIn) return atLogin ? null : '/login';
      if (loadingProfile) return atSplash ? null : '/';

      final user = profile.valueOrNull;
      if (user == null || !user.active) return atSplash ? null : '/';

      final home = switch (user.role) {
        AppRole.admin => '/admin',
        AppRole.sales => '/sales',
        AppRole.hours => '/hours',
      };

      if (atLogin || atSplash) return home;

      final loc = state.matchedLocation;
      if (loc.startsWith('/admin') && user.role != AppRole.admin) return home;
      if (loc.startsWith('/sales') &&
          user.role != AppRole.admin &&
          user.role != AppRole.sales) {
        return home;
      }
      if (loc.startsWith('/hours') &&
          user.role != AppRole.admin &&
          user.role != AppRole.hours) {
        return home;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

      // Admin
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'master-lists',
            builder: (_, __) => const MasterListsScreen(),
            routes: [
              GoRoute(
                path: ':listId',
                builder: (_, state) =>
                    MasterListDetailScreen(listId: state.pathParameters['listId']!),
              ),
            ],
          ),
          GoRoute(
            path: 'sales',
            builder: (_, __) => const SalesListScreen(),
          ),
        ],
      ),

      // Sales (admin + sales)
      GoRoute(
        path: '/sales',
        builder: (_, __) => const SalesHomeScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, __) => const SaleFormScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                SaleDetailScreen(saleId: state.pathParameters['id']!),
          ),
        ],
      ),

      // Hours (admin + hours)
      GoRoute(
        path: '/hours',
        builder: (_, __) => const HoursEntryScreen(),
      ),
    ],
  );
});

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
