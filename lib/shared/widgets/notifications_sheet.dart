import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/roles.dart';
import '../../core/utils/clock.dart';
import '../../features/auth/data/auth_repository.dart';
import '../models/app_notification.dart';
import '../services/notifications_repository.dart';
import 'empty_state.dart';

/// Bottom sheet con la lista de notificaciones del usuario actual.
///
/// Diseño:
///   - Filtro "Todas / No leídas" (default no leídas).
///   - Botón "Marcar todas como leídas" cuando hay no leídas.
///   - Agrupación visual: notifs consecutivas del mismo type + target
///     dentro de un bucket de 1h se colapsan en un solo item expandible.
///     Cada notif individual se persiste en backend; el bucket es solo UI.
///   - Tap en item / sub-item → marca como leído + navega al recurso
///     asociado (saleId → según el rol del usuario, va a la pantalla
///     correspondiente).
///
/// El recorte a 30 días vive en el repo (filtro cliente-side del stream).
class NotificationsSheet extends ConsumerStatefulWidget {
  const NotificationsSheet({super.key});

  @override
  ConsumerState<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends ConsumerState<NotificationsSheet> {
  bool _onlyUnread = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final notifsAsync = ref.watch(myNotificationsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            _SheetHeader(
              onlyUnread: _onlyUnread,
              onToggle: (v) => setState(() => _onlyUnread = v),
              onMarkAllAsRead: profile == null
                  ? null
                  : () => _markAllAsRead(profile.uid),
              unreadCount: _countUnread(
                notifsAsync.valueOrNull ?? const [],
                profile?.uid,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: notifsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No se pudieron cargar las notificaciones.\n$e',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                data: (notifs) {
                  if (profile == null) {
                    return const SizedBox.shrink();
                  }
                  final visible = _onlyUnread
                      ? notifs
                          .where((n) => !n.isReadBy(profile.uid))
                          .toList()
                      : notifs;
                  if (visible.isEmpty) {
                    return EmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: _onlyUnread
                          ? 'Sin notificaciones nuevas'
                          : 'Sin notificaciones',
                      message: _onlyUnread
                          ? 'Los avisos sobre tus solicitudes aparecen aquí.'
                          : 'Se muestran los últimos 30 días.',
                    );
                  }
                  final groups = _groupNotifications(visible);
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, i) => _NotificationGroupTile(
                      group: groups[i],
                      currentUid: profile.uid,
                      currentRole: profile.role,
                      onTapNotification: _onTap,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  int _countUnread(List<AppNotification> notifs, String? uid) {
    if (uid == null) return 0;
    return notifs.where((n) => !n.isReadBy(uid)).length;
  }

  Future<void> _markAllAsRead(String uid) async {
    final notifs = ref.read(myNotificationsProvider).valueOrNull ?? const [];
    final unreadIds = notifs
        .where((n) => !n.isReadBy(uid))
        .map((n) => n.id)
        .toList();
    if (unreadIds.isEmpty) return;
    await ref
        .read(notificationsRepositoryProvider)
        .markAllAsRead(ids: unreadIds, uid: uid);
  }

  /// Marca una notif como leída + navega al recurso asociado. Llamado
  /// desde el sub-tile dentro de un grupo expandido o desde el tile
  /// si el grupo es de uno solo.
  Future<void> _onTap(
    AppNotification notif,
    String uid,
    AppRole role,
  ) async {
    if (!notif.isReadBy(uid)) {
      await ref
          .read(notificationsRepositoryProvider)
          .markAsRead(id: notif.id, uid: uid);
    }
    if (!mounted) return;
    final saleId = notif.saleId;
    if (saleId == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop();
    // Cada rol abre la venta en su pantalla:
    //   sales / auditor → detalle público.
    //   cajero / admin → la vista de pagos (admin también accede al
    //     detail desde ahí), porque cuando una notif es de proceso /
    //     cancelación / pérdida lo más útil es ver el ledger.
    final target = switch (role) {
      AppRole.cajero => '/cashier/$saleId',
      AppRole.admin => switch (notif.type) {
          NotificationType.saleProcessed ||
          NotificationType.saleCanceled ||
          NotificationType.saleMarkedLoss =>
            '/cashier/$saleId/payments',
          _ => '/cashier/$saleId',
        },
      _ => '/sales/$saleId',
    };
    context.push(target);
  }

  /// Agrupa notifs consecutivas del mismo tipo dentro de buckets de 1h.
  /// Mantiene el orden de la lista de entrada (la lista ya viene
  /// ordenada desc por createdAt). Si dos notifs del mismo tipo están
  /// dentro de la misma hora del bucket anterior, se unen.
  List<_NotificationGroup> _groupNotifications(
    List<AppNotification> notifs,
  ) {
    final groups = <_NotificationGroup>[];
    for (final n in notifs) {
      final last = groups.isEmpty ? null : groups.last;
      if (last != null &&
          last.type == n.type &&
          last.startedAt.difference(n.createdAt).inMinutes.abs() <= 60) {
        last.items.add(n);
      } else {
        groups.add(_NotificationGroup(type: n.type, items: [n]));
      }
    }
    return groups;
  }
}

class _NotificationGroup {
  _NotificationGroup({required this.type, required this.items});
  final NotificationType type;
  final List<AppNotification> items;

  AppNotification get latest => items.first;
  DateTime get startedAt => latest.createdAt;

  bool unreadFor(String uid) => items.any((n) => !n.isReadBy(uid));
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.onlyUnread,
    required this.onToggle,
    required this.onMarkAllAsRead,
    required this.unreadCount,
  });

  final bool onlyUnread;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onMarkAllAsRead;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Notificaciones',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Todas'),
                selected: !onlyUnread,
                onSelected: (_) => onToggle(false),
              ),
              ChoiceChip(
                label: Text(
                  unreadCount > 0 ? 'No leídas ($unreadCount)' : 'No leídas',
                ),
                selected: onlyUnread,
                onSelected: (_) => onToggle(true),
              ),
              if (unreadCount > 0 && onMarkAllAsRead != null)
                TextButton.icon(
                  onPressed: onMarkAllAsRead,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Marcar todas'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationGroupTile extends StatefulWidget {
  const _NotificationGroupTile({
    required this.group,
    required this.currentUid,
    required this.currentRole,
    required this.onTapNotification,
  });

  final _NotificationGroup group;
  final String currentUid;
  final AppRole currentRole;
  final Future<void> Function(AppNotification, String, AppRole)
      onTapNotification;

  @override
  State<_NotificationGroupTile> createState() => _NotificationGroupTileState();
}

class _NotificationGroupTileState extends State<_NotificationGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    final isCollapsedBucket = group.items.length > 1;
    final hasUnread = group.unreadFor(widget.currentUid);
    final accent = group.type.accentFor(theme.colorScheme);
    if (!isCollapsedBucket) {
      return _NotificationTile(
        notif: group.latest,
        currentUid: widget.currentUid,
        currentRole: widget.currentRole,
        onTap: widget.onTapNotification,
        accent: accent,
      );
    }
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Icon(group.type.icon, color: accent, size: 20),
          ),
          title: Text(
            _summaryTitle(group),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          subtitle: Text(
            _summaryBody(group),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          ...group.items.map(
            (n) => Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _NotificationTile(
                notif: n,
                currentUid: widget.currentUid,
                currentRole: widget.currentRole,
                onTap: widget.onTapNotification,
                accent: accent,
                dense: true,
              ),
            ),
          ),
      ],
    );
  }

  String _summaryTitle(_NotificationGroup g) {
    final n = g.items.length;
    return switch (g.type) {
      NotificationType.saleCreated => '$n solicitudes nuevas',
      NotificationType.saleProcessed => '$n solicitudes procesadas',
      NotificationType.saleCanceled => '$n solicitudes canceladas',
      NotificationType.saleMarkedLoss => '$n saldos marcados como pérdida',
      NotificationType.unknown => '$n notificaciones',
    };
  }

  String _summaryBody(_NotificationGroup g) {
    final first = g.latest;
    final rest = g.items.length - 1;
    final time = _relativeTime(first.createdAt);
    if (rest == 0) return first.body;
    return '${first.body} · y $rest más · $time';
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notif,
    required this.currentUid,
    required this.currentRole,
    required this.onTap,
    required this.accent,
    this.dense = false,
  });

  final AppNotification notif;
  final String currentUid;
  final AppRole currentRole;
  final Future<void> Function(AppNotification, String, AppRole) onTap;
  final Color accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final read = notif.isReadBy(currentUid);
    return ListTile(
      dense: dense,
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: read ? 0.08 : 0.18),
        child: Icon(notif.type.icon, color: accent, size: 20),
      ),
      title: Text(
        notif.title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: read ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notif.body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                _relativeTime(notif.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              if (notif.createdByName.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '·',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    notif.createdByName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: read
          ? null
          : Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                shape: BoxShape.circle,
              ),
            ),
      onTap: () => onTap(notif, currentUid, currentRole),
    );
  }
}

/// "hace X" sin intl — el formato custom es más natural en español que
/// `intl.timeago` y evita sumar una dependencia.
String _relativeTime(DateTime when) {
  final now = AppClock.now();
  final diff = now.difference(when);
  if (diff.inSeconds < 60) return 'hace instantes';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'hace $h h';
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return 'hace $d d';
  }
  return 'el ${when.day.toString().padLeft(2, '0')}/'
      '${when.month.toString().padLeft(2, '0')}';
}
