import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/master_list_field.dart';
import '../data/workers_repository.dart';
import '../domain/worker.dart';

class WorkerFormScreen extends ConsumerStatefulWidget {
  const WorkerFormScreen({super.key, this.editing});

  final Worker? editing;

  @override
  ConsumerState<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends ConsumerState<WorkerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _idNumber;
  late final TextEditingController _address;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _bank;
  String? _role;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final w = widget.editing;
    _fullName = TextEditingController(text: w?.fullName ?? '');
    _idNumber = TextEditingController(text: w?.idNumber ?? '');
    _address = TextEditingController(text: w?.address ?? '');
    _email = TextEditingController(text: w?.email ?? '');
    _phone = TextEditingController(text: w?.phone ?? '');
    _bank = TextEditingController(text: w?.bank ?? '');
    _role = w?.role;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _idNumber.dispose();
    _address.dispose();
    _email.dispose();
    _phone.dispose();
    _bank.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(workersRepositoryProvider);
      if (_isEdit) {
        await repo.update(
          widget.editing!.id,
          fullName: _fullName.text,
          idNumber: _idNumber.text,
          role: _role!,
          address: _address.text,
          email: _email.text,
          phone: _phone.text,
          bank: _bank.text,
        );
      } else {
        await repo.create(
          fullName: _fullName.text,
          idNumber: _idNumber.text,
          role: _role!,
          address: _address.text,
          email: _email.text,
          phone: _phone.text,
          bank: _bank.text,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_isEdit
                  ? 'Trabajador actualizado.'
                  : 'Trabajador creado.')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar trabajador' : 'Nuevo trabajador'),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextFormField(
                controller: _fullName,
                decoration:
                    const InputDecoration(labelText: 'Nombre completo'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatorio.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idNumber,
                decoration: const InputDecoration(labelText: 'Cédula'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatorio.' : null,
              ),
              const SizedBox(height: 12),
              MasterListField(
                listId: 'worker_roles',
                label: 'Cargo',
                initialValue: _role,
                required: true,
                onChanged: (v) => setState(() => _role = v),
                helperText: 'Si no existe, escríbelo y se guarda.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Dirección'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Correo'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bank,
                decoration: const InputDecoration(labelText: 'Banco'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.4),
                      )
                    : Text(_isEdit ? 'Guardar cambios' : 'Crear trabajador'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
