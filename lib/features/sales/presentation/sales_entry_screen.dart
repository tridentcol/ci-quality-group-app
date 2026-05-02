import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

class SalesEntryScreen extends ConsumerWidget {
  const SalesEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de ventas'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'Hola, ${profile?.fullName ?? 'usuario'}.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'En la próxima entrega aquí va el formulario de registro de venta '
                'con consecutivo automático CQG-XXX.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
