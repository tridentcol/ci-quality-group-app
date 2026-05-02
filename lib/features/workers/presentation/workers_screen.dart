import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/workers_repository.dart';
import '../domain/worker.dart';

class WorkersScreen extends ConsumerStatefulWidget {
  const WorkersScreen({super.key});

  @override
  ConsumerState<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends ConsumerState<WorkersScreen> {
  String _query = '';
  bool _showInactive = false;
  bool _seedTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedIfEmpty());
  }

  Future<void> _seedIfEmpty() async {
    if (_seedTried) return;
    _seedTried = true;
    try {
      final loaded =
          await ref.read(workersRepositoryProvider).seedFromAssetsIfEmpty();
      if (loaded > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se cargaron $loaded trabajadores iniciales.'),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _confirmDeactivate(Worker w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar trabajador'),
        content: Text(
          '${w.fullName} dejará de aparecer en el listado de control de horas. '
          'Su histórico de horas registradas se conserva. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(workersRepositoryProvider).deactivate(w.id);
  }

  Future<void> _reactivate(Worker w) async {
    await ref.read(workersRepositoryProvider).reactivate(w.id);
  }

  @override
  Widget build(BuildContext context) {
    final workers =
        _showInactive ? ref.watch(allWorkersProvider) : ref.watch(activeWorkersProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trabajadores'),
        actions: [
          IconButton(
            tooltip: _showInactive ? 'Ver solo activos' : 'Ver todos',
            icon: Icon(_showInactive
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/workers/new'),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Nuevo trabajador'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, cédula o cargo…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: workers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (data) {
                final filtered = _query.isEmpty
                    ? data
                    : data
                        .where((w) =>
                            w.fullName.toLowerCase().contains(_query) ||
                            w.idNumber.toLowerCase().contains(_query) ||
                            w.role.toLowerCase().contains(_query))
                        .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        data.isEmpty
                            ? 'Aún no hay trabajadores. Usa el botón Nuevo trabajador.'
                            : 'No hay coincidencias para tu búsqueda.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final w = filtered[i];
                    return _WorkerCard(
                      worker: w,
                      onEdit: () => context.push('/admin/workers/${w.id}/edit'),
                      onDeactivate: () => _confirmDeactivate(w),
                      onReactivate: () => _reactivate(w),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.worker,
    required this.onEdit,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final Worker worker;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: worker.active ? 0.15 : 0.05),
              child: Text(
                _initials(worker.fullName),
                style: TextStyle(
                  color: worker.active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          worker.fullName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: worker.active
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      if (!worker.active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Inactivo',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${worker.role} · CC ${worker.idNumber}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    onEdit();
                    break;
                  case 'deactivate':
                    onDeactivate();
                    break;
                  case 'reactivate':
                    onReactivate();
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                if (worker.active)
                  const PopupMenuItem(
                      value: 'deactivate', child: Text('Desactivar'))
                else
                  const PopupMenuItem(
                      value: 'reactivate', child: Text('Reactivar')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
