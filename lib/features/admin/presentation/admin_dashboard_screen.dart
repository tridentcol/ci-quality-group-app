import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/app_logo.dart';
import '../../auth/data/auth_repository.dart';

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
          const SizedBox(height: 20),
          Text('VENTAS', style: _sectionStyle(context)),
          const SizedBox(height: 8),
          _AdminTile(
            title: 'Ver ventas y exportar',
            subtitle: 'Movimientos en tiempo real, filtros por fecha, export xlsx.',
            icon: Icons.receipt_long_outlined,
            onTap: () => context.push('/admin/sales'),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            title: 'Registrar nueva venta',
            subtitle: 'Genera el siguiente consecutivo CQG-XXX automáticamente.',
            icon: Icons.add_circle_outline,
            onTap: () => context.push('/sales/new'),
          ),
          const SizedBox(height: 24),
          Text('CONFIGURACIÓN', style: _sectionStyle(context)),
          const SizedBox(height: 8),
          _AdminTile(
            title: 'Listas maestras',
            subtitle: 'Proveedores, pagadores, materiales, métodos de pago.',
            icon: Icons.list_alt_outlined,
            onTap: () => context.push('/admin/master-lists'),
          ),
          const SizedBox(height: 24),
          Text('HORAS', style: _sectionStyle(context)),
          const SizedBox(height: 8),
          _AdminTile(
            title: 'Horas laboradas',
            subtitle:
                'Registros por trabajador, totales por categoría y export xlsx.',
            icon: Icons.schedule_outlined,
            onTap: () => context.push('/admin/hours'),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            title: 'Marcar entrada/salida',
            subtitle: 'Acceso rápido a la pantalla del encargado de horas.',
            icon: Icons.fact_check_outlined,
            onTap: () => context.push('/hours'),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            title: 'Trabajadores',
            subtitle: 'Lista activa, edición y desactivación con histórico.',
            icon: Icons.engineering_outlined,
            onTap: () => context.push('/admin/workers'),
          ),
          const SizedBox(height: 24),
          Text('PRÓXIMAMENTE', style: _sectionStyle(context)),
          const SizedBox(height: 8),
          const _AdminTile(
            title: 'Constructor de formularios',
            subtitle: 'Agrega o reordena campos del formulario de ventas.',
            icon: Icons.dynamic_form_outlined,
            onTap: null,
          ),
          const SizedBox(height: 10),
          const _AdminTile(
            title: 'Usuarios de la app',
            subtitle: 'Crea, edita y resetea contraseñas.',
            icon: Icons.manage_accounts_outlined,
            onTap: null,
          ),
          const SizedBox(height: 10),
          const _AdminTile(
            title: 'Configuración de jornada',
            subtitle: 'Horario ordinario, almuerzo y franja diurna/nocturna.',
            icon: Icons.tune_outlined,
            onTap: null,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          );
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
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
                Icon(
                  disabled ? Icons.lock_outline : Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
