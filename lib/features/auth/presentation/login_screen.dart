import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_logo.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(
            username: _usernameCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _translate(e.code));
    } catch (_) {
      setState(() => _error = 'No fue posible iniciar sesión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _translate(String code) {
    return switch (code) {
      'invalid-credential' || 'invalid-login-credentials' || 'wrong-password' =>
        'Usuario o contraseña incorrectos.',
      'user-not-found' => 'Ese usuario no existe.',
      'user-disabled' => 'Tu usuario está deshabilitado. Contacta al admin.',
      'network-request-failed' =>
        'Sin conexión. Revisa tu internet e intenta otra vez.',
      'too-many-requests' =>
        'Demasiados intentos. Espera un minuto e intenta de nuevo.',
      _ => 'Error de autenticación ($code).',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppLogo(size: 88),
                    const SizedBox(height: 32),
                    Text(
                      'Iniciar sesión',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ingresa con tu usuario corporativo.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Ingresa tu usuario'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Ingresa tu contraseña'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 18, color: theme.colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '¿Olvidaste tu contraseña? Contacta al administrador.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
