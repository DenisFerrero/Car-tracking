import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'screens/account.dart';
import 'screens/add_device.dart';
import 'screens/admin.dart';
import 'screens/auth.dart';
import 'screens/dashboards/dashboards_screen.dart';
import 'screens/device/device_screen.dart';
import 'screens/device/costs_screen.dart';
import 'screens/device/extra_screen.dart';
import 'screens/device/maintenance_screen.dart';
import 'screens/device/refuels_screen.dart';
import 'screens/device/trends_screen.dart';
import 'screens/devices.dart';
import 'screens/friends.dart';
import 'screens/home.dart';
import 'screens/map_overview.dart';
import 'screens/notifications.dart';
import 'screens/phone.dart';
import 'screens/platform_log.dart';
import 'screens/public_link.dart';
import 'screens/server_setup.dart';
import 'screens/summary_screen.dart';

/// Routes. The session decides where the user can go: server address (mobile),
/// login and second factor, TOTP enrollment, then the platform.
GoRouter buildRouter(Session session) {
  const public = ['/splash', '/server', '/login', '/login/mfa', '/enroll', '/recovery-codes'];
  // Page asked before the login (deep link, notification): opened once inside
  String? wanted;
  String? hold(GoRouterState state, String to) {
    if (!public.contains(state.matchedLocation) && state.matchedLocation != '/') wanted = state.uri.toString();
    return state.matchedLocation == to ? null : to;
  }

  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!session.ready) return hold(state, '/splash');
      // Invites and temporary links to a position need no login
      bool open(String? path) => path != null && (path.startsWith('/invite/') || path.startsWith('/l/'));
      if (open(location)) return null;
      // Opened before the session was ready
      if (open(wanted)) {
        final page = wanted;
        wanted = null;
        return page;
      }
      if (!session.api.web && !session.api.hasServer) return hold(state, '/server');

      final auth = switch (session.stage) {
        Stage.none => '/login',
        Stage.mfaPending => '/login/mfa',
        Stage.enroll => '/enroll',
        Stage.full => null,
      };
      // Recovery codes are shown once after the enrollment, before entering
      if (session.stage == Stage.full && session.pendingRecoveryCodes != null) {
        return location == '/recovery-codes' ? null : '/recovery-codes';
      }
      if (auth != null) return hold(state, auth);
      if (!public.contains(location)) return null;
      final target = wanted ?? '/';
      wanted = null;
      return target;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/server', builder: (context, state) => const ServerSetupScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/login/mfa', builder: (context, state) => const MfaScreen()),
      GoRoute(path: '/enroll', builder: (context, state) => const EnrollScreen()),
      GoRoute(path: '/recovery-codes', builder: (context, state) => const RecoveryCodesScreen()),
      GoRoute(
        path: '/invite/:token',
        builder: (context, state) => InviteScreen(token: state.pathParameters['token']!),
      ),
      GoRoute(path: '/l/:token', builder: (context, state) => PublicLinkScreen(token: state.pathParameters['token']!)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (context, state) => const MapOverviewScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/devices',
              builder: (context, state) => const DevicesScreen(),
              routes: [
                GoRoute(path: 'add', builder: (context, state) => const AddDeviceScreen()),
                GoRoute(path: 'phone', builder: (context, state) => const PhoneScreen()),
                GoRoute(
                  path: ':id',
                  builder: (context, state) => DeviceScreen(
                    deviceId: int.parse(state.pathParameters['id']!),
                    initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
                  ),
                  routes: [
                    GoRoute(
                      path: 'trends',
                      builder: (context, state) => TrendsScreen(deviceId: int.parse(state.pathParameters['id']!)),
                    ),
                    GoRoute(
                      path: 'maintenance',
                      builder: (context, state) => MaintenanceScreen(deviceId: int.parse(state.pathParameters['id']!)),
                    ),
                    GoRoute(
                      path: 'costs',
                      builder: (context, state) => CostsScreen(deviceId: int.parse(state.pathParameters['id']!)),
                    ),
                    GoRoute(
                      path: 'refuels',
                      builder: (context, state) => RefuelsScreen(deviceId: int.parse(state.pathParameters['id']!)),
                    ),
                    GoRoute(
                      path: 'extra',
                      builder: (context, state) => ExtraScreen(deviceId: int.parse(state.pathParameters['id']!)),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/dashboards', builder: (context, state) => const DashboardsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/account',
              builder: (context, state) => const AccountScreen(),
              routes: [
                GoRoute(
                  path: 'admin',
                  builder: (context, state) => const AdminScreen(),
                  routes: [GoRoute(path: 'logs', builder: (context, state) => const PlatformLogScreen())],
                ),
                GoRoute(path: 'friends', builder: (context, state) => const FriendsScreen()),
                GoRoute(path: 'summary', builder: (context, state) => SummaryScreen(month: state.uri.queryParameters['month'])),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
}
