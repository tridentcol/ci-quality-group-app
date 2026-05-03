import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/admin_metrics_screen.dart';
import '../../features/admin/presentation/master_list_detail_screen.dart';
import '../../features/admin/presentation/master_lists_screen.dart';
import '../../features/admin/presentation/user_form_screen.dart';
import '../../features/admin/presentation/users_screen.dart';
import '../../features/admin/presentation/work_schedule_settings_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/users_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/form_builder/presentation/form_builder_screen.dart';
import '../../features/hours/presentation/hours_admin_screen.dart';
import '../../features/hours/presentation/hours_home_screen.dart';
import '../../features/hours/presentation/manual_hours_entry_screen.dart';
import '../../features/hours/presentation/worker_day_screen.dart';
import '../../features/sales/data/sales_repository.dart';
import '../../features/sales/domain/sale.dart';
import '../../features/sales/presentation/sale_detail_screen.dart';
import '../../features/sales/presentation/sale_form_screen.dart';
import '../../features/sales/presentation/sales_home_screen.dart';
import '../../features/sales/presentation/sales_list_screen.dart';
import '../../features/workers/data/workers_repository.dart';
import '../../features/workers/presentation/worker_form_screen.dart';
import '../../features/workers/presentation/workers_screen.dart';
import '../constants/roles.dart';

/// Notifier que GoRouter escucha. Lo creamos UNA sola vez y lo reusamos
/// para evitar acumular listeners cada vez que cambia el estado de auth.
final _routerRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => notifier.value++);
  ref.listen(currentProfileProvider, (_, __) => notifier.value++);
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
          GoRoute(
            path: 'hours',
            builder: (_, __) => const HoursAdminScreen(),
            routes: [
              GoRoute(
                path: 'manual',
                builder: (_, __) => const ManualHoursEntryScreen(),
                routes: [
                  GoRoute(
                    path: ':entryId',
                    builder: (_, state) => ManualHoursEntryScreen(
                      entryId: state.pathParameters['entryId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'metrics',
            builder: (_, __) => const AdminMetricsScreen(),
          ),
          GoRoute(
            path: 'settings/schedule',
            builder: (_, __) => const WorkScheduleSettingsScreen(),
          ),
          GoRoute(
            path: 'form-builder',
            builder: (_, __) => const FormBuilderScreen(module: 'sales'),
          ),
          GoRoute(
            path: 'users',
            builder: (_, __) => const UsersScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const UserFormScreen(),
              ),
              GoRoute(
                path: ':uid',
                builder: (_, state) =>
                    _EditUserRoute(uid: state.pathParameters['uid']!),
              ),
            ],
          ),
          GoRoute(
            path: 'workers',
            builder: (_, __) => const WorkersScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const WorkerFormScreen(),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (_, state) => _EditWorkerRoute(
                    workerId: state.pathParameters['id']!),
              ),
            ],
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
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) {
                  final extra = state.extra;
                  if (extra is Sale) {
                    return SaleFormScreen(editingSale: extra);
                  }
                  // Fallback: si llegó por deep link sin `extra`, carga vía
                  // provider para no romper.
                  return _EditSaleRoute(saleId: state.pathParameters['id']!);
                },
              ),
            ],
          ),
        ],
      ),

      // Hours (admin + hours)
      GoRoute(
        path: '/hours',
        builder: (_, __) => const HoursHomeScreen(),
        routes: [
          GoRoute(
            path: ':workerId',
            builder: (_, state) =>
                WorkerDayScreen(workerId: state.pathParameters['workerId']!),
          ),
        ],
      ),
    ],
  );
});

/// Helper que envuelve un `AsyncValue` para mostrar loading/error/no-data
/// con el mismo Scaffold que las pantallas de edición usan tres veces.
Widget _asyncEntityScreen<T>({
  required AsyncValue<T?> async,
  required String notFoundLabel,
  required Widget Function(T value) onData,
}) {
  return async.when(
    loading: () => const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    error: (e, _) => Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Error: $e')),
      ),
    ),
    data: (value) {
      if (value == null) {
        return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(notFoundLabel)),
        );
      }
      return onData(value);
    },
  );
}

class _EditUserRoute extends ConsumerWidget {
  const _EditUserRoute({required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _asyncEntityScreen(
      async: ref.watch(userByIdProvider(uid)),
      notFoundLabel: 'Usuario no encontrado.',
      onData: (u) => UserFormScreen(editing: u),
    );
  }
}

class _EditWorkerRoute extends ConsumerWidget {
  const _EditWorkerRoute({required this.workerId});
  final String workerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _asyncEntityScreen(
      async: ref.watch(workerByIdProvider(workerId)),
      notFoundLabel: 'Trabajador no encontrado.',
      onData: (w) => WorkerFormScreen(editing: w),
    );
  }
}

class _EditSaleRoute extends ConsumerWidget {
  const _EditSaleRoute({required this.saleId});
  final String saleId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _asyncEntityScreen(
      async: ref.watch(saleByIdProvider(saleId)),
      notFoundLabel: 'Venta no encontrada.',
      onData: (s) => SaleFormScreen(editingSale: s),
    );
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
          error: (e, _) => _AuthErrorView(
            icon: Icons.error_outline,
            message: 'No se pudo cargar tu perfil.\n$e',
            onSignOut: () => ref.read(authRepositoryProvider).signOut(),
            theme: theme,
          ),
          data: (user) {
            if (user == null) {
              return _AuthErrorView(
                icon: Icons.lock_outline,
                message:
                    'Tu cuenta no tiene un perfil asignado. Contacta al administrador.',
                onSignOut: () => ref.read(authRepositoryProvider).signOut(),
                theme: theme,
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      ),
    );
  }
}

class _AuthErrorView extends StatelessWidget {
  const _AuthErrorView({
    required this.icon,
    required this.message,
    required this.onSignOut,
    required this.theme,
  });

  final IconData icon;
  final String message;
  final VoidCallback onSignOut;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onSignOut,
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
