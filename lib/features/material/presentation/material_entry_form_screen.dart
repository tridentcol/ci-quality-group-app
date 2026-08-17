import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../auth/data/auth_repository.dart';
import '../data/material_entries_repository.dart';
import '../domain/material_entry.dart';
import 'widgets/photo_picker_field.dart';

/// Formulario de registro de un movimiento de material (ingreso o
/// salida, totalmente independientes de `sales`): foto del material,
/// cuánto y de qué material, foto de procedencia/destino y la empresa
/// contraparte (proveedor en ingreso, cliente en salida).
///
/// Con [editingEntry] pasa a modo edición: no se piden fotos nuevas
/// (las existentes se muestran de solo lectura — reemplazarlas no está
/// soportado en esta fase, ver `docs/data-model.md`) y el submit llama
/// `updateEntry` en vez de `createEntry`. Sin [editingEntry], [type]
/// decide si el formulario arranca en modo ingreso o salida.
class MaterialEntryFormScreen extends ConsumerStatefulWidget {
  const MaterialEntryFormScreen({
    super.key,
    this.editingEntry,
    this.type = MaterialMovementType.ingreso,
  });

  final MaterialEntry? editingEntry;
  final MaterialMovementType type;

  @override
  ConsumerState<MaterialEntryFormScreen> createState() =>
      _MaterialEntryFormScreenState();
}

class _MaterialEntryFormScreenState
    extends ConsumerState<MaterialEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final MaterialMovementType _type;
  late DateTime _date;
  String? _material;
  String? _materialVariant;
  late final TextEditingController _quantityCtrl;
  String? _unit;
  String? _providerName;
  String? _clientName;
  late final TextEditingController _originDescriptionCtrl;
  late final TextEditingController _vehicleRefCtrl;
  late final TextEditingController _notesCtrl;

  Uint8List? _materialPhoto;
  Uint8List? _originPhoto;

  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.editingEntry != null;
  bool get _isIngreso => _type == MaterialMovementType.ingreso;

  /// Mismo criterio que `sale_form_screen.dart`: en es_CO se escribe la
  /// coma como separador decimal.
  static num? _parseQuantity(String text) =>
      num.tryParse(text.trim().replaceAll(',', '.'));

  @override
  void initState() {
    super.initState();
    final e = widget.editingEntry;
    _type = e?.type ?? widget.type;
    _date = e?.date ?? AppClock.now();
    _material = e?.material;
    _materialVariant = e?.materialVariant;
    _quantityCtrl = TextEditingController(text: e == null ? '' : '${e.quantity}');
    _unit = e?.unit;
    _providerName = e?.providerName;
    _clientName = e?.clientName;
    _originDescriptionCtrl =
        TextEditingController(text: e?.originDescription ?? '');
    _vehicleRefCtrl = TextEditingController(text: e?.vehicleRef ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _originDescriptionCtrl.dispose();
    _vehicleRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 1)),
      helpText: _isIngreso
          ? 'Selecciona la fecha del ingreso'
          : 'Selecciona la fecha de la salida',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (!_isEditing && _materialPhoto == null) {
      setState(() => _error = 'Falta la foto del material.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(materialEntriesRepositoryProvider);
      if (_isEditing) {
        await repo.updateEntry(
          widget.editingEntry!.id,
          date: _date,
          material: _material,
          materialVariant: _materialVariant,
          quantity: _parseQuantity(_quantityCtrl.text)!,
          unit: _unit,
          providerName: _isIngreso ? _providerName : null,
          clientName: _isIngreso ? null : _clientName,
          originDescription: _originDescriptionCtrl.text.trim().isEmpty
              ? null
              : _originDescriptionCtrl.text.trim(),
          vehicleRef: _vehicleRefCtrl.text.trim().isEmpty
              ? null
              : _vehicleRefCtrl.text.trim(),
          notes:
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
        if (mounted) context.pop();
        return;
      }

      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) {
        setState(() => _error = 'No se pudo identificar tu sesión.');
        return;
      }
      final entryRef = repo.newEntryRef();
      final materialUrl = await repo.uploadPhoto(
        entryId: entryRef.id,
        kind: 'material',
        bytes: _materialPhoto!,
      );
      String? originUrl;
      if (_originPhoto != null) {
        originUrl = await repo.uploadPhoto(
          entryId: entryRef.id,
          kind: 'origin',
          bytes: _originPhoto!,
        );
      }

      await repo.createEntry(
        entryRef: entryRef,
        type: _type,
        date: _date,
        material: _material!,
        materialVariant: _materialVariant,
        quantity: _parseQuantity(_quantityCtrl.text)!,
        unit: _unit!,
        providerName: _isIngreso ? _providerName! : null,
        clientName: _isIngreso ? null : _clientName!,
        originDescription: _originDescriptionCtrl.text.trim().isEmpty
            ? null
            : _originDescriptionCtrl.text.trim(),
        vehicleRef: _vehicleRefCtrl.text.trim().isEmpty
            ? null
            : _vehicleRefCtrl.text.trim(),
        materialPhotoUrl: materialUrl,
        originPhotoUrl: originUrl,
        notes:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdBy: profile.uid,
        createdByName: profile.fullName,
      );

      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Editar ${_isIngreso ? 'ingreso' : 'salida'}'
              : 'Registrar ${_isIngreso ? 'ingreso' : 'salida'}',
        ),
      ),
      body: AbsorbPointer(
        absorbing: _submitting,
        child: Form(
          key: _formKey,
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
              if (_isIngreso)
                MasterListField(
                  listId: 'material_providers',
                  label: 'Proveedor',
                  required: true,
                  initialValue: _providerName,
                  onChanged: (v) => setState(() => _providerName = v),
                )
              else
                MasterListField(
                  listId: 'providers',
                  label: 'Cliente',
                  required: true,
                  initialValue: _clientName,
                  onChanged: (v) => setState(() => _clientName = v),
                ),
              const SizedBox(height: 16),
              MasterListField(
                listId: 'materials',
                label: 'Material',
                required: true,
                initialValue: _material,
                onChanged: (v) => setState(() {
                  _material = v;
                  _materialVariant = null;
                }),
              ),
              const SizedBox(height: 16),
              MasterListField(
                listId: 'lamina_brands',
                label: 'Tipo (opcional)',
                parent: _material,
                initialValue: _materialVariant,
                onChanged: (v) => setState(() => _materialVariant = v),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantityCtrl,
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final n = _parseQuantity(v ?? '');
                        if (n == null || n <= 0) return 'Valor inválido.';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: MasterListField(
                      listId: 'units',
                      label: 'Unidad',
                      required: true,
                      initialValue: _unit,
                      onChanged: (v) => setState(() => _unit = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _originDescriptionCtrl,
                decoration: InputDecoration(
                  labelText: _isIngreso ? 'Origen (opcional)' : 'Destino (opcional)',
                  hintText: _isIngreso
                      ? 'Ej. Barranquilla — Recicladora XYZ'
                      : 'Ej. Cartagena — Recicladora XYZ',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vehicleRefCtrl,
                decoration: const InputDecoration(
                  labelText: 'Vehículo / vagón (opcional)',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              if (_isEditing) ...[
                Text(
                  'Fotos',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Las fotos no se pueden reemplazar desde acá. Si hay que '
                  'corregirlas, borra este ingreso y regístralo de nuevo.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ExistingPhotoThumb(url: widget.editingEntry!.materialPhotoUrl),
                    if (widget.editingEntry!.originPhotoUrl != null) ...[
                      const SizedBox(width: 8),
                      _ExistingPhotoThumb(
                        url: widget.editingEntry!.originPhotoUrl!,
                      ),
                    ],
                  ],
                ),
              ] else ...[
                PhotoPickerField(
                  label: 'Foto del material',
                  required: true,
                  onChanged: (bytes) => setState(() => _materialPhoto = bytes),
                ),
                const SizedBox(height: 16),
                PhotoPickerField(
                  label: _isIngreso
                      ? 'Foto de procedencia (opcional)'
                      : 'Foto de destino (opcional)',
                  onChanged: (bytes) => setState(() => _originPhoto = bytes),
                ),
              ],
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
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
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
                    : Text(
                        _isEditing
                            ? 'Guardar cambios'
                            : 'Registrar ${_isIngreso ? 'ingreso' : 'salida'}',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingPhotoThumb extends StatelessWidget {
  const _ExistingPhotoThumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 96,
          height: 96,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
