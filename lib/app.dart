import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/utils/dates.dart';
import 'features/admin/data/sales_delegation_repository.dart';
import 'features/admin/domain/sales_delegation.dart';
import 'features/auth/data/auth_repository.dart';

class CIQualityGroupApp extends ConsumerWidget {
  const CIQualityGroupApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'CI Quality Group',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Forzamos el formato 12h (AM/PM) en todos los TimePickers de la app
      // independiente de la configuración del dispositivo. Sin esto, Flutter
      // respeta el ajuste del SO y muestra 24h en celulares configurados así.
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: _DelegationGlobalBannerHost(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// Inserta un banner naranja persistente arriba del Navigator cuando el
/// modo "delegación caja" está vigente. Visible en todos los roles
/// autenticados — al sales le confirma que puede registrar pago en el
/// form, y a cajero/admin les recuerda que sales puede crear payments
/// mientras el banner siga ahí.
///
/// Antes de auth no se monta nada: leer `settings/sales_delegation` sin
/// estar firmado dispara permission-denied en las rules, y de todas
/// formas el splash/login no tendrían a quién mostrarle el banner.
class _DelegationGlobalBannerHost extends ConsumerWidget {
  const _DelegationGlobalBannerHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSignedIn =
        ref.watch(authStateProvider).valueOrNull != null;
    if (!isSignedIn) return child;
    final delegation = ref.watch(salesDelegationProvider).valueOrNull;
    if (delegation == null || !delegation.isCurrentlyActive) return child;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        _DelegationGlobalBanner(delegation: delegation),
        Expanded(child: child),
      ],
    );
  }
}

class _DelegationGlobalBanner extends StatelessWidget {
  const _DelegationGlobalBanner({required this.delegation});

  final SalesDelegation delegation;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE6A100);
    final expiresAt = delegation.expiresAt;
    final label = expiresAt == null
        ? 'Modo delegación caja activo — sin vencimiento'
        : 'Modo delegación caja activo — expira ${formatDateTime(expiresAt)}';
    return Material(
      // Material wrapper para que el shadow del AppBar de abajo no se
      // recorte y el banner respete el sistema de elevación de M3.
      color: accent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 18,),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
