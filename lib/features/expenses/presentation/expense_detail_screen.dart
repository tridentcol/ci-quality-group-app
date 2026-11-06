import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/data/auth_repository.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});

  final String expenseId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Borrar gasto',
      message: 'Se borra este gasto de forma permanente, incluida su foto. '
          'No se puede deshacer.',
      confirmLabel: 'Borrar',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    try {
      await ref.read(expensesRepositoryProvider).deleteExpense(expense.id);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo borrar: ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseAsync = ref.watch(expenseByIdProvider(expenseId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Gasto de bodega')),
      body: expenseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: ${friendlyError(e)}')),
        data: (expense) {
          if (expense == null) {
            return const Center(child: Text('Gasto no encontrado.'));
          }
          final profile = ref.watch(currentProfileProvider).valueOrNull;
          final isAdmin = profile?.role == AppRole.admin;
          // Admin edita sin ventana de tiempo; cajero/hours solo lo suyo
          // dentro de las 24h.
          final canEdit = profile != null &&
              (isAdmin ||
                  (profile.uid == expense.createdBy && expense.isEditable));

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    expense.description,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatCop(expense.amount),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (expense.hasPhoto) ...[
                    const SizedBox(height: 16),
                    _ReceiptPhoto(url: expense.photoUrl!),
                  ],
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(
                            label: 'Fecha',
                            value: formatDate(expense.date),
                          ),
                          if (expense.category != null)
                            _DetailRow(
                              label: 'Categoría',
                              value: expense.category!,
                            ),
                          _DetailRow(label: 'Quién pagó', value: expense.paidBy),
                          if (expense.notes != null)
                            _DetailRow(label: 'Notas', value: expense.notes!),
                          _DetailRow(
                            label: 'Registrado por',
                            value: expense.createdByName,
                          ),
                          _DetailRow(
                            label: 'Registrado el',
                            value: formatDateTime(expense.createdAt),
                          ),
                          if (expense.updatedAt != null)
                            _DetailRow(
                              label: 'Última edición',
                              value: formatDateTime(expense.updatedAt!),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (canEdit || isAdmin) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (canEdit)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/expenses/${expense.id}/edit',
                                extra: expense,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar'),
                            ),
                          ),
                        if (canEdit && isAdmin) const SizedBox(width: 12),
                        if (isAdmin)
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                side: BorderSide(
                                  color: theme.colorScheme.error
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              onPressed: () => _delete(context, ref, expense),
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
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ReceiptPhoto extends StatelessWidget {
  const _ReceiptPhoto({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _PhotoViewerPage(url: url)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: Image.network(
            url,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 160,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
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
      body: Center(child: InteractiveViewer(child: Image.network(url))),
    );
  }
}
