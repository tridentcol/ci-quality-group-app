import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/dates.dart';
import '../../cashier/data/cash_shift_repository.dart';
import '../../cashier/domain/cash_register.dart';
import '../data/sales_delegation_repository.dart';
import '../domain/sales_delegation.dart';
import 'admin_shell.dart';

/// Índice de "Configuración" en el admin. Agrupa los ajustes operativos
/// (hoy: jornada laboral y delegación caja) en una pantalla con cards
/// grandes y descripción breve.
class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delegation = ref.watch(salesDelegationProvider).valueOrNull ??
        SalesDelegation.inactive();
    final register = ref.watch(cashRegisterProvider).valueOrNull ??
        CashRegister.closed();

    return Scaffold(
      drawer: adminDrawerOrNull(context, '/admin/settings'),
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SettingsCard(
            icon: Icons.tune_outlined,
            title: 'Jornada laboral',
            description:
                'Horarios de entrada/salida, almuerzo y franjas diurna/nocturna que usa el cálculo legal de horas.',
            onTap: () => context.push('/admin/settings/schedule'),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: delegation.isCurrentlyActive
                ? Icons.lock_open_outlined
                : Icons.lock_outline,
            title: 'Delegación caja',
            description:
                'Permite excepcionalmente al rol Ventas registrar el pago de una venta cuando no hay alguien en caja.',
            trailing: _DelegationStatusChip(delegation: delegation),
            onTap: () => context.push('/admin/settings/delegation'),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: register.isOpen
                ? Icons.lock_open_outlined
                : Icons.point_of_sale_outlined,
            title: 'Cierre de caja',
            description:
                'Abre y cierra la caja del turno, cuenta el efectivo y cuadra '
                'contra lo que registró el sistema.',
            trailing: _CashRegisterStatusChip(register: register),
            onTap: () => context.push('/admin/settings/cierre'),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.list_alt_outlined,
            title: 'Listas maestras',
            description:
                'Catálogos editables: clientes, materiales, tipos, métodos de pago, destinos de transferencia y más.',
            onTap: () => context.push('/admin/master-lists'),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.manage_accounts_outlined,
            title: 'Usuarios',
            description:
                'Altas, bajas y roles de las personas que usan la app (admin, ventas, caja, horas, auditor).',
            onTap: () => context.push('/admin/users'),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.engineering_outlined,
            title: 'Trabajadores',
            description:
                'Personal operativo cuyas horas se registran (no son usuarios de la app).',
            onTap: () => context.push('/admin/workers'),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DelegationStatusChip extends StatelessWidget {
  const _DelegationStatusChip({required this.delegation});
  final SalesDelegation delegation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, Color bg, Color fg, IconData icon) =
        _styleFor(theme, delegation);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  (String, Color, Color, IconData) _styleFor(
    ThemeData theme,
    SalesDelegation d,
  ) {
    final scheme = theme.colorScheme;
    if (d.isCurrentlyActive) {
      final until = d.expiresAt;
      final label = until == null
          ? 'Activa'
          : 'Activa · vence ${formatTime(until)}';
      return (label, scheme.primary.withValues(alpha: 0.15), scheme.primary,
          Icons.lock_open_outlined,);
    }
    if (d.isScheduled) {
      return (
        'Programada ${formatDateTime(d.startsAt!)}',
        scheme.tertiary.withValues(alpha: 0.15),
        scheme.tertiary,
        Icons.schedule_outlined,
      );
    }
    if (d.hasExpired) {
      return (
        'Expiró ${formatTime(d.expiresAt!)}',
        scheme.error.withValues(alpha: 0.12),
        scheme.error,
        Icons.timer_off_outlined,
      );
    }
    return (
      'Inactiva',
      scheme.surfaceContainerHighest,
      scheme.onSurface.withValues(alpha: 0.65),
      Icons.lock_outline,
    );
  }
}

class _CashRegisterStatusChip extends StatelessWidget {
  const _CashRegisterStatusChip({required this.register});
  final CashRegister register;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (String label, Color bg, Color fg, IconData icon) = register.isOpen
        ? (
            register.openedAt != null
                ? 'Abierta · ${formatTime(register.openedAt!)}'
                : 'Abierta',
            scheme.primary.withValues(alpha: 0.15),
            scheme.primary,
            Icons.lock_open_outlined,
          )
        : (
            'Cerrada',
            scheme.surfaceContainerHighest,
            scheme.onSurface.withValues(alpha: 0.65),
            Icons.point_of_sale_outlined,
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
