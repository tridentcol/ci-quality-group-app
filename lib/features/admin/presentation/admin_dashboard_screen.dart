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
          _AdminTile(
            title: 'Métricas y gráficas',
            subtitle:
                'KPIs, totales por método, top clientes y desglose de horas.',
            icon: Icons.insights_outlined,
            onTap: () => context.push('/admin/metrics'),
          ),
          const SizedBox(height: 24),
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
            subtitle: 'Clientes, quién recibe, materiales, métodos de pago.',
            icon: Icons.list_alt_outlined,
            onTap: () => context.push('/admin/master-lists'),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            title: 'Configuración de jornada',
            subtitle:
                'Horarios ordinarios, almuerzo y franjas diurna / nocturna.',
            icon: Icons.tune_outlined,
            onTap: () => context.push('/admin/settings/schedule'),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            title: 'Usuarios de la app',
            subtitle: 'Crea, edita y activa/desactiva cuentas.',
            icon: Icons.manage_accounts_outlined,
            onTap: () => context.push('/admin/users'),
          ),
          const SizedBox(height: 24),
          Text('HORAS', style: _sectionStyle(context)),
          const SizedBox(height: 8),
          _AdminTile(
            title: 'Horas laboradas',
            subtitle:
                'Registros, edición retroactiva, entrada manual y export xlsx.',
            icon: Icons.schedule_outlined,
            onTap: () => context.push('/admin/hours'),
          ),
          const SizedBox(height: 10),
          _AdminTile(
            title: 'Marcar entrada / salida del día',
            subtitle:
                'Atajo al flujo en vivo del encargado para el día corriente.',
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
