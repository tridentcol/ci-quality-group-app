import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/notifications_bell.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../data/material_entries_repository.dart';
import '../domain/material_entry.dart';
import 'widgets/material_entry_card.dart';

/// Pantalla operativa del control de material: lista de movimientos
/// recientes (ingreso Y salida) + registrar uno nuevo. Mismo rol que ve
/// `/hours` (más admin) — ver `docs/data-model.md` → tabla de roles.
class MaterialHomeScreen extends ConsumerWidget {
  const MaterialHomeScreen({super.key});

  Future<void> _openRegisterSheet(BuildContext context) async {
    final type = await showModalBottomSheet<MaterialMovementType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_received_outlined),
              title: const Text('Registrar ingreso'),
              subtitle: const Text('Material que llega de un proveedor'),
              onTap: () => Navigator.pop(ctx, MaterialMovementType.ingreso),
            ),
            ListTile(
              leading: const Icon(Icons.call_made_outlined),
              title: const Text('Registrar salida'),
              subtitle: const Text('Material que sale hacia un cliente'),
              onTap: () => Navigator.pop(ctx, MaterialMovementType.salida),
            ),
          ],
        ),
      ),
    );
    if (type != null && context.mounted) {
      context.push('/material/new', extra: type);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(recentMaterialEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de material'),
        actions: [
          IconButton(
            tooltip: 'Control de horas',
            icon: const Icon(Icons.schedule_outlined),
            onPressed: () => context.push('/hours'),
          ),
          const NotificationsBell(),
          const ThemeModeIconButton(),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRegisterSheet(context),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Registrar movimiento'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentMaterialEntriesProvider),
        child: entriesAsync.when(
          loading: () => const SkeletonList(),
          error: (e, _) => AppErrorView(
            error: e,
            onRetry: () => ref.invalidate(recentMaterialEntriesProvider),
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Sin movimientos registrados',
                    message:
                        'Toca "Registrar movimiento" para cargar el primero.',
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => MaterialEntryCard(
                entry: entries[i],
                onTap: () => context.push('/material/${entries[i].id}'),
              ),
            );
          },
        ),
      ),
    );
  }
}
