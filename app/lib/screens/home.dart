import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/push.dart';
import 'dashboards/sharing.dart';

/// Shell of the platform: navigation bar (rail on wide screens), realtime toasts for
/// the notifications, devices granted or revoked, push registration on Android.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  StreamSubscription<Map<String, dynamic>>? _events;

  @override
  void initState() {
    super.initState();
    _events = ref.read(liveProvider).events.listen(_onEvent);
    Push.register(ref.read(apiProvider)).ignore();
    _checkAppUpdate();
  }

  /// Android app older than the latest release: a banner to download it, once per version
  Future<void> _checkAppUpdate() async {
    final build = ref.read(appBuildProvider);
    if (!build.updatable) return;
    final Map<String, dynamic>? release;
    try {
      release = (await ref.read(apiProvider).get('/api/app/release') as Map<String, dynamic>)['release'] as Map<String, dynamic>?;
    } on ApiException {
      return;
    }
    if (release == null || !isNewerVersion(release['version'] as String, build.version)) return;
    final version = release['version'] as String;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('appUpdateDismissed') == version || !mounted) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(MaterialBanner(
      key: const Key('appUpdate'),
      leading: const Icon(Icons.system_update),
      content: Text(l.appUpdateAvailable(version)),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setString('appUpdateDismissed', version).ignore();
            messenger.hideCurrentMaterialBanner();
          },
          child: Text(l.later),
        ),
        FilledButton(
          key: const Key('appUpdateDownload'),
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            openLink(context, ref, Uri.parse(release!['apkUrl'] as String));
          },
          child: Text(l.download),
        ),
      ],
    ));
  }

  void _onEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    switch (event['type']) {
      case 'notification':
        final notification = AppNotification.fromJson(event['notification'] as Map<String, dynamic>);
        ref.invalidate(notificationsProvider);
        final text = notificationText(context.l10n, notification.kind, notification.data);
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${text.title} · ${text.body}'),
              action: SnackBarAction(
                label: context.l10n.open,
                onPressed: () => context.go('/devices/${notification.deviceId}'),
              ),
            ),
          );
      case 'access':
        // Share granted, revoked or ended: the device screen closes by itself
        ref.invalidate(devicesProvider);
        final id = event['deviceId'] as int;
        ref.invalidate(deviceProvider(id));
        if (event['revoked'] == true) {
          final device = ref.read(devicesProvider).value?.where((item) => item.id == id).firstOrNull;
          final location = GoRouterState.of(context).uri.path;
          if (location.startsWith('/devices/$id')) context.go('/devices');
          showMessage(context, context.l10n.accessRevoked(device?.name ?? ''));
        }
      case 'dashboardShare':
        // A dashboard layout sent by a friend: used or declined in the dashboards
        ref.invalidate(sharedDashboardsProvider);
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(context.l10n.dashboardReceived(event['name'] as String, event['dashboard'] as String)),
            action: SnackBarAction(label: context.l10n.open, onPressed: () => context.go('/dashboards')),
          ));
      case 'registered' || 'device':
        ref.invalidate(devicesProvider);
      case 'friends':
        ref.invalidate(friendsProvider);
        // A request received, or a request of the user accepted (the screen of the friends
        // has its own messages)
        final name = event['name'] as String?;
        if (name == null || GoRouterState.of(context).uri.path.startsWith('/account/friends')) return;
        if (event['request'] == true) {
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(context.l10n.friendRequestReceived(name)),
              action: SnackBarAction(label: context.l10n.open, onPressed: () => context.go('/account/friends')),
            ));
        } else if (event['added'] == true) {
          showMessage(context, context.l10n.friendAddedYou(name));
        }
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final destinations = [
      (icon: Icons.map_outlined, selected: Icons.map, label: l.navMap),
      (icon: Icons.directions_car_outlined, selected: Icons.directions_car, label: l.navDevices),
      (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: l.navDashboards),
      (icon: Icons.notifications_outlined, selected: Icons.notifications, label: l.navNotifications),
      (icon: Icons.person_outline, selected: Icons.person, label: l.navAccount),
    ];
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    Widget icon(int index, bool selected) {
      final item = destinations[index];
      final widget = Icon(selected ? item.selected : item.icon);
      return index == 3 && unread > 0 ? Badge(label: Text('$unread'), child: widget) : widget;
    }

    void select(int index) => widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: widget.shell.currentIndex,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (var i = 0; i < destinations.length; i++)
                  NavigationRailDestination(
                    icon: icon(i, false),
                    selectedIcon: icon(i, true),
                    label: Text(destinations[i].label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: widget.shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: select,
        destinations: [
          for (var i = 0; i < destinations.length; i++)
            NavigationDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: destinations[i].label),
        ],
      ),
    );
  }
}
