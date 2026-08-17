import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/data/auth_repository.dart';
import '../data/material_entries_repository.dart';
import '../domain/material_entry.dart';

class MaterialEntryDetailScreen extends ConsumerWidget {
  const MaterialEntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(materialEntryByIdProvider(entryId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          entryAsync.valueOrNull?.type == MaterialMovementType.salida
              ? 'Salida de material'
              : 'Ingreso de material',
        ),
      ),
      body: entryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entry) {
          if (entry == null) {
            return const Center(child: Text('Movimiento no encontrado.'));
          }
          final profile = ref.watch(currentProfileProvider).valueOrNull;
          // Admin no tiene ventana de tiempo (igual que en sales/hours) —
          // solo el creador (rol hours) está limitado a las 24h.
          final canEdit = profile != null &&
              (profile.role == AppRole.admin ||
                  (profile.uid == entry.createdBy && entry.isEditable));
          final canDelete = profile?.role == AppRole.admin;

          // En desktop (pantalla ancha), sin este límite las fotos —
          // que están en un Row con Expanded + AspectRatio 1:1 — crecen
          // con el ancho de la ventana y se ven gigantes. 640px es un
          // ancho de lectura razonable, igual que un form/detail typical.
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Row(
                    children: [
                      Text(
                        entry.consecutive,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        formatDateTime(entry.date),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _PhotoCard(
                          label: 'Material',
                          url: entry.materialPhotoUrl,
                        ),
                      ),
                      if (entry.originPhotoUrl != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PhotoCard(
                            label: entry.type == MaterialMovementType.ingreso
                                ? 'Procedencia'
                                : 'Destino',
                            url: entry.originPhotoUrl!,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(
                            label: entry.type.counterpartyLabel,
                            value: entry.counterpartyName,
                          ),
                          _DetailRow(
                            label: 'Material',
                            value: entry.displayLabel,
                          ),
                          _DetailRow(
                            label: 'Cantidad',
                            value:
                                '${formatQuantity(entry.quantity)} ${entry.unit}',
                          ),
                          if (entry.originDescription != null)
                            _DetailRow(
                              label: entry.type == MaterialMovementType.ingreso
                                  ? 'Origen'
                                  : 'Destino',
                              value: entry.originDescription!,
                            ),
                          if (entry.vehicleRef != null)
                            _DetailRow(
                              label: 'Vehículo / vagón',
                              value: entry.vehicleRef!,
                            ),
                          if (entry.notes != null)
                            _DetailRow(label: 'Notas', value: entry.notes!),
                          _DetailRow(
                            label: 'Registrado por',
                            value: entry.createdByName,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (canEdit || canDelete) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (canEdit)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/material/${entry.id}/edit',
                                extra: entry,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar'),
                            ),
                          ),
                        if (canEdit && canDelete) const SizedBox(width: 12),
                        if (canDelete)
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.error,
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              onPressed: () async {
                                final ok = await showConfirmDialog(
                                  context,
                                  title:
                                      'Borrar ${entry.type.label.toLowerCase()}',
                                  message:
                                      'Se borra ${entry.consecutive} de forma '
                                      'permanente, incluidas sus fotos. No se '
                                      'puede deshacer.',
                                  confirmLabel: 'Borrar',
                                  destructive: true,
                                  icon: Icons.delete_outline,
                                );
                                if (!ok) return;
                                await ref
                                    .read(materialEntriesRepositoryProvider)
                                    .deleteEntry(entry.id);
                                if (context.mounted) context.pop();
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Borrar'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _PhotoViewerPage(url: url)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PhotoViewerPage extends StatelessWidget {
  const _PhotoViewerPage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(url),
        ),
      ),
    );
  }
}
