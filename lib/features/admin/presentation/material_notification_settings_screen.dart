import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../material/data/material_notification_settings_repository.dart';
import 'admin_shell.dart';

/// Configuración de a quién le llega el correo de "nuevo ingreso de
/// material". Lista simple de emails — se guarda completa cada vez que
/// se agrega/quita uno (bajo volumen, no amerita más).
class MaterialNotificationSettingsScreen extends ConsumerStatefulWidget {
  const MaterialNotificationSettingsScreen({super.key});

  @override
  ConsumerState<MaterialNotificationSettingsScreen> createState() =>
      _MaterialNotificationSettingsScreenState();
}

class _MaterialNotificationSettingsScreenState
    extends ConsumerState<MaterialNotificationSettingsScreen> {
  final _controller = TextEditingController();
  List<String>? _draft;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initFrom(List<String> emails) {
    _draft ??= [...emails];
  }

  Future<void> _save() async {
    if (_draft == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(materialNotificationSettingsRepositoryProvider)
          .save(_draft!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada.')),
        );
      }
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _add() {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    if (_draft!.contains(email)) {
      _controller.clear();
      return;
    }
    setState(() {
      _draft = [..._draft!, email];
      _controller.clear();
      _error = null;
    });
  }

  void _remove(String email) {
    setState(() => _draft = _draft!.where((e) => e != email).toList());
  }

  @override
  Widget build(BuildContext context) {
    final emailsAsync = ref.watch(materialNotificationEmailsProvider);

    return Scaffold(
      drawer: adminDrawerOrNull(
        context,
        '/admin/settings/material-notifications',
      ),
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const BackButton() : null,
        title: const Text('Notificaciones de material'),
      ),
      body: emailsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (emails) {
          _initFrom(emails);
          final draft = _draft!;
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Cada vez que se registra un ingreso de material, se '
                    'envía un correo con el resumen y las fotos a estos '
                    'destinatarios. Si la lista está vacía, no se envía '
                    'ningún correo (el aviso in-app sigue funcionando '
                    'igual).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Agregar correo',
                          hintText: 'gerencia@empresa.com',
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _add,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,),
                  ),
                ],
                const SizedBox(height: 16),
                if (draft.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Sin destinatarios configurados.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final email in draft)
                        Chip(
                          label: Text(email),
                          onDeleted: () => _remove(email),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('Guardar cambios'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
