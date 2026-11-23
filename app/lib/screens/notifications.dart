import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
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
                        if (!context.mounted) return;
                        // The summary of the month opens its page; alarms the history of the
                        // owner, arrivals the live map
                        if (n.deviceId == null) return context.go('/account/summary?month=${n.data.month}');
                        final tab = device?.isOwner == true && !n.kind.startsWith('geofence') ? 1 : 0;
                        context.go('/devices/${n.deviceId}?tab=$tab');
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
