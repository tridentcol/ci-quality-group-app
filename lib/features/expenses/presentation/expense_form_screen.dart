import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/errors.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../auth/data/auth_repository.dart';
import '../../material/presentation/widgets/photo_picker_field.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';

/// Alta y edición de un gasto de bodega. Con [editingExpense] pasa a
/// modo edición: muestra la foto existente con "Quitar foto" (se aplica
/// al guardar) y, si no hay foto, deja agregar una nueva.
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.editingExpense});

  final Expense? editingExpense;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _date;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  String? _category;
  String? _paidBy;

  Uint8List? _photo;
  bool _removeExistingPhoto = false;

  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.editingExpense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editingExpense;
    _date = e?.date ?? AppClock.now();
    _descriptionCtrl = TextEditingController(text: e?.description ?? '');
    _amountCtrl = TextEditingController(text: e == null ? '' : '${e.amount}');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _category = e?.category;
    _paidBy = e?.paidBy;
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 1)),
      helpText: 'Selecciona la fecha del gasto',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _submitting = true);
    try {
      final repo = ref.read(expensesRepositoryProvider);
      final amount = num.parse(_amountCtrl.text.trim());
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      final editing = widget.editingExpense;
      if (editing != null) {
        ({String url, String storagePath})? uploaded;
        if (_photo != null) {
          uploaded = await repo.uploadPhoto(
            expenseId: editing.id,
            bytes: _photo!,
          );
        }
        await repo.updateExpense(
          editing.id,
          date: _date,
          description: _descriptionCtrl.text.trim(),
          amount: amount,
          category: _category,
          paidBy: _paidBy,
          notes: notes,
          photoUrl: uploaded?.url,
          photoStoragePath: uploaded?.storagePath,
          // Si se subió una foto nueva, el archivo viejo ya se
          // sobrescribió (path fijo); limpiar ahora lo borraría.
          clearPhoto: _removeExistingPhoto && uploaded == null,
        );
        if (mounted) context.pop();
        return;
      }

      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) {
        setState(() => _error = 'No se pudo identificar tu sesión.');
        return;
      }
      final expenseRef = repo.newExpenseRef();
      ({String url, String storagePath})? uploaded;
      if (_photo != null) {
        uploaded = await repo.uploadPhoto(
          expenseId: expenseRef.id,
          bytes: _photo!,
        );
      }
      await repo.createExpense(
        expenseRef: expenseRef,
        date: _date,
        description: _descriptionCtrl.text.trim(),
        amount: amount,
        category: _category,
        paidBy: _paidBy!,
        photoUrl: uploaded?.url,
        photoStoragePath: uploaded?.storagePath,
        notes: notes,
        createdBy: profile.uid,
        createdByName: profile.fullName,
      );
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildPhotoSection(BuildContext context) {
    final theme = Theme.of(context);
    final existingUrl = widget.editingExpense?.photoUrl;
    final showExisting =
        existingUrl != null && existingUrl.isNotEmpty && !_removeExistingPhoto;

    if (showExisting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Foto del soporte', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              existingUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _removeExistingPhoto = true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Quitar foto'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PhotoPickerField(
          label: 'Foto de la factura / soporte (opcional)',
          onChanged: (bytes) => setState(() => _photo = bytes),
        ),
        if (_removeExistingPhoto && _photo == null) ...[
          const SizedBox(height: 8),
          Text(
            'La foto actual se borrará al guardar.',
            style: theme.textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: () => setState(() => _removeExistingPhoto = false),
            icon: const Icon(Icons.undo),
            label: const Text('Deshacer'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar gasto' : 'Nuevo gasto'),
      ),
      body: AbsorbPointer(
        absorbing: _submitting,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(formatDate(_date)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Ej. Arreglo de llantas camión',
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escribe una descripción.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: r'$ ',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = num.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Ingresa un monto mayor a 0.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              MasterListField(
                listId: 'expense_categories',
                label: 'Categoría (opcional)',
                initialValue: _category,
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 16),
              MasterListField(
                listId: 'expense_payers',
                label: 'Quién pagó',
                required: true,
                initialValue: _paidBy,
                onChanged: (v) => setState(() => _paidBy = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 24),
              _buildPhotoSection(context),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(_isEditing ? 'Guardar cambios' : 'Registrar gasto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
