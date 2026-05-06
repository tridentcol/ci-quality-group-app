import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/errors.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/master_list_field.dart';
import '../../../shared/widgets/theme_mode_toggle.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/users_repository.dart';
import '../../auth/domain/app_user.dart';

/// Formulario para crear o editar un usuario de la app.
///
/// En **creación** captura username, contraseña, nombre completo y rol;
/// crea la cuenta en Firebase Auth (vía app secundaria, sin tocar la
/// sesión del admin) y el doc del perfil en Firestore.
///
/// En **edición** solo permite modificar nombre completo, rol y activo.
/// Para cambios de contraseña o borrado total se delega a la consola
/// de Firebase.
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key, this.editing});

  final AppUser? editing;

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _fullName;
  AppRole _role = AppRole.sales;
  bool _active = true;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  /// Campo del documento `sales` que filtra la vista del auditor (solo
  /// se usa cuando _role == auditor). Default: `materialVariant` que
  /// es el caso típico (socio de un material/marca).
  String _auditField = 'materialVariant';

  /// Valor exacto a filtrar (ej. "PEDRO"). Lo escoge el admin desde el
  /// MasterListField que se carga según _auditField.
  String? _auditValue;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final u = widget.editing;
    _username = TextEditingController(text: u?.username ?? '');
    _password = TextEditingController();
    _fullName = TextEditingController(text: u?.fullName ?? '');
    if (u != null) {
      _role = u.role;
      _active = u.active;
      if (u.auditFilter != null) {
        _auditField = u.auditFilter!.field;
        _auditValue = u.auditFilter!.value;
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validación específica de auditor: si el rol es auditor, debe
    // tener un value seleccionado, sino el dashboard sale vacío.
    if (_role == AppRole.auditor &&
        (_auditValue == null || _auditValue!.isEmpty)) {
      setState(() => _error =
          'Un auditor necesita un valor de filtro asignado para que su '
          'dashboard tenga datos.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auditFilter = _role == AppRole.auditor
          ? AuditFilter(field: _auditField, value: _auditValue!)
          : null;
      if (_isEdit) {
        await ref.read(usersRepositoryProvider).updateProfile(
              widget.editing!.uid,
              fullName: _fullName.text,
              role: _role,
              active: _active,
              auditFilter: auditFilter,
              clearAuditFilter: _role != AppRole.auditor,
            );
      } else {
        await ref.read(usersRepositoryProvider).createUser(
              username: _username.text.trim(),
              password: _password.text,
              fullName: _fullName.text,
              role: _role,
              auditFilter: auditFilter,
            );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Usuario actualizado.' : 'Usuario creado.'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mapeo del campo de auditoría al listId de la lista maestra que
  /// provee los valores válidos. Si en el futuro se agregan más campos
  /// de filtro, basta con extender este map.
  String _listIdForField(String field) => switch (field) {
        'materialVariant' => 'lamina_brands',
        'material' => 'materials',
        'providerName' => 'providers',
        'payerName' => 'payers',
        'paymentMethod' => 'payment_methods',
        _ => 'providers',
      };

  String _labelForField(String field) => switch (field) {
        'materialVariant' => 'Tipo de material',
        'material' => 'Material',
        'providerName' => 'Cliente',
        'payerName' => 'Quién recibe',
        'paymentMethod' => 'Método de pago',
        _ => field,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myUid = ref.watch(currentProfileProvider.select(
      (a) => a.valueOrNull?.uid,
    ),);
    final isSelf = _isEdit && myUid == widget.editing!.uid;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar usuario' : 'Nuevo usuario'),
        actions: const [ThemeModeIconButton()],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + keyboardInset),
            children: [
              if (isSelf)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 18, color: theme.colorScheme.primary,),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Estás editando tu propia cuenta. Por seguridad no '
                          'puedes cambiar tu rol ni desactivarte.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              TextFormField(
                controller: _username,
                enabled: !_isEdit,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  prefixIcon: Icon(Icons.person_outline),
                  helperText:
                      'Lo que el usuario digita en el login. Sin espacios.',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
                ],
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                validator: (v) {
                  if (_isEdit) return null;
                  if (v == null || v.trim().isEmpty) return 'Obligatorio.';
                  if (v.trim().length < 3) {
                    return 'Mínimo 3 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatorio.' : null,
              ),
              const SizedBox(height: 12),
              if (!_isEdit)
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: 'Mínimo 6 caracteres.',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 6) {
                      return 'La contraseña debe tener al menos 6 caracteres.';
                    }
                    return null;
                  },
                ),
              if (!_isEdit) const SizedBox(height: 12),
              DropdownButtonFormField<AppRole>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  prefixIcon: Icon(Icons.security_outlined),
                ),
                items: AppRole.values
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.label),
                        ),)
                    .toList(),
                onChanged: isSelf
                    ? null
                    : (r) => setState(() {
                          _role = r ?? _role;
                          // Al cambiar de auditor a otro rol, limpiamos
                          // el filtro para no guardar datos colgados.
                          if (_role != AppRole.auditor) {
                            _auditValue = null;
                          }
                        }),
              ),
              if (_role == AppRole.auditor) ...[
                const SizedBox(height: 16),
                _AuditorFilterCard(
                  field: _auditField,
                  value: _auditValue,
                  onFieldChanged: (f) => setState(() {
                    _auditField = f;
                    // Al cambiar de campo, el value anterior deja de
                    // tener sentido (es de otra lista maestra).
                    _auditValue = null;
                  }),
                  onValueChanged: (v) => setState(() => _auditValue = v),
                  listIdForField: _listIdForField,
                  labelForField: _labelForField,
                ),
              ],
              const SizedBox(height: 8),
              if (_isEdit)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cuenta activa'),
                  subtitle: const Text(
                    'Si está apagada, el usuario no puede entrar a la app.',
                  ),
                  value: _active,
                  onChanged: isSelf ? null : (v) => setState(() => _active = v),
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorBanner(message: _error!),
              ],
              const SizedBox(height: 24),
              LoadingButton(
                onPressed: _submit,
                loading: _busy,
                label: _isEdit ? 'Guardar cambios' : 'Crear usuario',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card mostrada cuando el rol seleccionado es auditor: dos campos —
/// "campo a filtrar" y "valor del filtro". El admin escoge a qué subset
/// de ventas tiene acceso este auditor (ej. socio Pedro: campo
/// `materialVariant`, valor `PEDRO`).
class _AuditorFilterCard extends StatelessWidget {
  const _AuditorFilterCard({
    required this.field,
    required this.value,
    required this.onFieldChanged,
    required this.onValueChanged,
    required this.listIdForField,
    required this.labelForField,
  });

  final String field;
  final String? value;
  final ValueChanged<String> onFieldChanged;
  final ValueChanged<String?> onValueChanged;
  final String Function(String) listIdForField;
  final String Function(String) labelForField;

  static const _fieldOptions = [
    'materialVariant',
    'material',
    'providerName',
    'payerName',
    'paymentMethod',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Filtro de auditoría',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'El auditor solo verá las ventas que matcheen el campo + valor '
            'que escojas abajo. Ejemplo: para un socio que provee láminas '
            'tipo PEDRO, el campo es "Tipo de material" y el valor es '
            '"PEDRO".',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: field,
            decoration: const InputDecoration(
              labelText: 'Campo a filtrar',
              prefixIcon: Icon(Icons.tune_outlined),
            ),
            items: [
              for (final f in _fieldOptions)
                DropdownMenuItem(value: f, child: Text(labelForField(f))),
            ],
            onChanged: (v) => v != null ? onFieldChanged(v) : null,
          ),
          const SizedBox(height: 12),
          MasterListField(
            key: ValueKey('audit-value-$field'),
            listId: listIdForField(field),
            label: 'Valor del filtro',
            initialValue: value,
            onChanged: onValueChanged,
            required: true,
            allowSuggestions: false,
            helperText:
                'Escoge de la lista. Si no aparece la opción, créala '
                'primero en la lista maestra correspondiente.',
          ),
        ],
      ),
    );
  }
}
