import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../../shared/widgets/app_logo.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del administrador'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const AppLogo(size: 56, showWordmark: false),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, ${profile?.fullName ?? '...'}',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Estás conectado como administrador.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AdminTile(
            title: 'Ventas',
            subtitle: 'Movimientos en tiempo real, totales y export xlsx.',
            icon: Icons.receipt_long_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _AdminTile(
            title: 'Horas laboradas',
            subtitle: 'Registros por trabajador con desglose por categoría.',
            icon: Icons.schedule_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _AdminTile(
            title: 'Trabajadores',
            subtitle: 'Lista activa, edición y desactivación con histórico.',
            icon: Icons.engineering_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _AdminTile(
            title: 'Listas maestras',
            subtitle: 'Proveedores, pagadores, materiales, métodos de pago.',
            icon: Icons.list_alt_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _AdminTile(
            title: 'Constructor de formularios',
            subtitle: 'Agrega o reordena campos del formulario de ventas.',
            icon: Icons.dynamic_form_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _AdminTile(
            title: 'Usuarios de la app',
            subtitle: 'Crea, edita y resetea contraseñas.',
            icon: Icons.manage_accounts_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _AdminTile(
            title: 'Configuración de jornada',
            subtitle: 'Horario ordinario, almuerzo y franja diurna/nocturna.',
            icon: Icons.tune_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Próxima entrega: cada tarjeta llevará a su pantalla.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
