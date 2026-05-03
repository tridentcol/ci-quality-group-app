import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../data/master_lists_repository.dart';

class MasterListsScreen extends ConsumerStatefulWidget {
  const MasterListsScreen({super.key});

  @override
  ConsumerState<MasterListsScreen> createState() => _MasterListsScreenState();
}

class _MasterListsScreenState extends ConsumerState<MasterListsScreen> {
  @override
  void initState() {
    super.initState();
    // El repository tiene una bandera estática `_didSeed` para que el seed
    // solo corra una vez por sesión sin reescribir las listas en cada visita.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(masterListsRepositoryProvider).seedDefaults();
      } catch (_) {
        // Si falla (permission-denied al arrancar) no es bloqueante.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(masterListsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Listas maestras')),
      body: RefreshIndicator(
        // Solo invalida el stream — sin escribir a Firestore. Para forzar
        // el seed (rara vez necesario) está el botón "Crear listas por
        // defecto" en el empty state.
        onRefresh: () async => ref.invalidate(masterListsProvider),
        child: listsAsync.when(
          loading: () => const SkeletonList(),
          error: (e, _) => AppErrorView(
            error: e,
            onRetry: () => ref.invalidate(masterListsProvider),
          ),
          data: (data) {
            if (data.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  EmptyState(
                    icon: Icons.list_alt_outlined,
                    title: 'No hay listas todavía',
                    message:
                        'Las listas base se crean automáticamente. Desliza '
                        'hacia abajo para reintentar.',
                    actionLabel: 'Crear listas por defecto',
                    onAction: () async {
                      await ref
                          .read(masterListsRepositoryProvider)
                          .seedDefaults(force: true);
                    },
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: data.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final list = data[i];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push('/admin/master-lists/${list.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.list_alt_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  list.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  list.description ??
                                      (list.allowFreeText
                                          ? 'Permite captura libre'
                                          : 'Solo opciones predefinidas'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
