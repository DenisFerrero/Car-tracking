import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final data = ref.watch(notificationsProvider);
    final devices = {for (final d in ref.watch(devicesProvider).value ?? const []) d.id: d};

    Future<void> markAll() async {
      await ref.read(apiProvider).post('/api/notifications/read');
      ref.invalidate(notificationsProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.notificationsTitle),
        actions: [
          if ((data.value?.unread ?? 0) > 0) TextButton(onPressed: markAll, child: Text(l.markAllRead)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(notificationsProvider.future),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(errorText(l, error)))]),
          data: (result) => result.items.isEmpty
              ? ListView(children: [
                  Padding(padding: const EdgeInsets.all(32), child: Text(l.noNotifications, textAlign: TextAlign.center)),
                ])
              : ListView.separated(
                  padding: readable(context),
                  itemCount: result.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final n = result.items[index];
                    final device = devices[n.deviceId];
                    final unread = n.readAt == null;
                    final text = notificationText(l, n.kind, n.data);
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: device?.color ?? Colors.grey, child: Icon(n.icon, color: Colors.white)),
                      title: Text(text.title, style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text('${text.body} · ${formatAgo(l, n.createdAt)}'),
                      trailing: unread ? const Icon(Icons.circle, size: 10, color: Colors.blue) : null,
                      onTap: () async {
                        if (unread) {
                          await ref.read(apiProvider).post('/api/notifications/read', {'ids': [n.id]});
                          ref.invalidate(notificationsProvider);
                        }
                        if (context.mounted) context.go(notificationTarget(n, owner: device?.isOwner == true));
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Page of a notification: the summary of the month, the log for the errors of the platform,
/// the live map for arrivals and parkings (and for viewers), the history for the alarms of the
/// owner
String notificationTarget(AppNotification n, {required bool owner}) {
  if (n.kind == 'platform_error') return '/account/admin/logs';
  if (n.deviceId == null) return '/account/summary?month=${n.data.month}';
  final live = !owner || n.kind.startsWith('geofence') || n.kind.startsWith('parking');
  return '/devices/${n.deviceId}?tab=${live ? 0 : 1}';
}
