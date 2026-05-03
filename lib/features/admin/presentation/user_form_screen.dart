import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await ref.read(usersRepositoryProvider).updateProfile(
              widget.editing!.uid,
              fullName: _fullName.text,
              role: _role,
              active: _active,
            );
      } else {
        await ref.read(usersRepositoryProvider).createUser(
              username: _username.text.trim(),
              password: _password.text,
              fullName: _fullName.text,
              role: _role,
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
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _translateAuth(e.code));
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _translateAuth(String code) {
    return switch (code) {
      'email-already-in-use' || 'email-already-exists' =>
        'Ya existe un usuario con ese username.',
      'invalid-email' => 'El username contiene caracteres inválidos.',
      'weak-password' =>
        'La contraseña es muy débil. Usa al menos 6 caracteres.',
      _ => 'Error de Firebase Auth ($code).',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentProfileProvider).valueOrNull;
    final isSelf = _isEdit && me?.uid == widget.editing!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar usuario' : 'Nuevo usuario'),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (isSelf)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 18, color: theme.colorScheme.primary),
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
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
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
                value: _role,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  prefixIcon: Icon(Icons.security_outlined),
                ),
                items: AppRole.values
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.label),
                        ))
                    .toList(),
                onChanged: isSelf
                    ? null
                    : (r) => setState(() => _role = r ?? _role),
              ),
              const SizedBox(height: 8),
              if (_isEdit)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cuenta activa'),
                  subtitle: const Text(
                    'Si está apagada, el usuario no puede entrar a la app.',
                  ),
                  value: _active,
                  onChanged:
                      isSelf ? null : (v) => setState(() => _active = v),
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.4),
                      )
                    : Text(_isEdit ? 'Guardar cambios' : 'Crear usuario'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
