import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/notifications_bell.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../data/material_entries_repository.dart';
import '../domain/material_entry.dart';

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
              itemBuilder: (context, i) => _EntryCard(
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap});

  final MaterialEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      entry.materialPhotoUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.inventory_2_outlined),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: entry.type == MaterialMovementType.ingreso
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE6A100),
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.surface, width: 2),
                      ),
                      child: Icon(
                        entry.type == MaterialMovementType.ingreso
                            ? Icons.call_received_outlined
                            : Icons.call_made_outlined,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.consecutive} · ${entry.counterpartyName}',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.displayLabel} · ${formatQuantity(entry.quantity)} ${entry.unit}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDateTime(entry.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
