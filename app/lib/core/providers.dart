import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'format.dart';
import 'live.dart';
import 'models.dart';
import 'open_url.dart';
import 'phone_tracker.dart';
import 'save_file.dart';
import 'session.dart';

/// Automatic retries of the providers: only network failures, a few times. An answer
/// of the backend (403, 404, 429...) would be the same at every retry.
Duration? retryNetwork(int count, Object error) =>
    error is ApiException && error.status == 0 && count < 3 ? Duration(seconds: 2 << count) : null;

// Services created in main() and injected with overrides
final apiProvider = Provider<ApiClient>((ref) => throw UnimplementedError());
final liveProvider = Provider<LiveChannel>((ref) => throw UnimplementedError());
final sessionProvider = Provider<Session>((ref) => throw UnimplementedError());
final phoneTrackerProvider = Provider<PhoneTracker>((ref) => throw UnimplementedError());

/// Realtime events of all the devices
final liveEventsProvider = StreamProvider<Map<String, dynamic>>((ref) => ref.watch(liveProvider).events);

final devicesProvider = FutureProvider.autoDispose<List<Device>>((ref) async {
  final list = await ref.watch(apiProvider).get('/api/devices') as List;
  return list.map((item) => Device.fromJson(item as Map<String, dynamic>)).toList();
});

final deviceProvider = FutureProvider.autoDispose.family<Device, int>((ref, id) async {
  return Device.fromJson(await ref.watch(apiProvider).get('/api/devices/$id') as Map<String, dynamic>);
});

/// Period of the history and analysis screens
typedef Period = ({int deviceId, DateTime from, DateTime to});

/// Saves a file made by the app (exports): shared on Android, downloaded by the browser
typedef FileSaver = Future<void> Function(String name, String mimeType, Uint8List bytes);
final fileSaverProvider = Provider<FileSaver>((ref) => saveFile);

/// Opens a link in another app (maps, browser): false when nothing can open it
typedef UrlOpener = Future<bool> Function(Uri uri);
final urlOpenerProvider = Provider<UrlOpener>((ref) => openUrl);

/// Version of this build (--dart-define=APP_VERSION, set from the tag by the release
/// workflow) and whether it can be updated from the releases: the Android app, not the
/// web app (served by the backend, always current)
typedef AppBuild = ({String version, bool updatable});
final appBuildProvider = Provider<AppBuild>((ref) => (
      version: const String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0'),
      updatable: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    ));

/// Numeric comparison of dotted versions: 2.10.0 is newer than 2.9.1
bool isNewerVersion(String candidate, String current) {
  List<int> parts(String value) => value.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final a = parts(candidate), b = parts(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final delta = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
    if (delta != 0) return delta > 0;
  }
  return false;
}

/// Opens a link, with a message when it fails
Future<void> openLink(BuildContext context, WidgetRef ref, Uri uri) async {
  final opened = await ref.read(urlOpenerProvider)(uri).catchError((Object _) => false);
  if (!opened && context.mounted) showMessage(context, context.l10n.openFailed);
}

/// Downloads a file of the server and saves it
Future<void> downloadFile(WidgetRef ref, String path, String mimeType, [Map<String, String>? query]) async {
  final file = await ref.read(apiProvider).download(path, query);
  await ref.read(fileSaverProvider)(file.name, mimeType, file.bytes);
}

Map<String, String> periodQuery(Period period) => {
      'from': period.from.toUtc().toIso8601String(),
      'to': period.to.toUtc().toIso8601String(),
    };

final positionsProvider = FutureProvider.autoDispose.family<({List<Position> positions, bool truncated}), Period>(
  (ref, period) async {
    final data = await ref.watch(apiProvider).get('/api/devices/${period.deviceId}/positions', periodQuery(period))
        as Map<String, dynamic>;
    return (
      positions: (data['positions'] as List).map((item) => Position.fromJson(item as Map<String, dynamic>)).toList(),
      truncated: data['truncated'] == true,
    );
  },
);

/// Analysis endpoints: stats, trips, distribution, coverage, traffic
final analysisProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (String, Period)>(
  (ref, key) async {
    final (endpoint, period) = key;
    return await ref.watch(apiProvider).get('/api/devices/${period.deviceId}/$endpoint', periodQuery(period))
        as Map<String, dynamic>;
  },
);

final notificationsProvider = FutureProvider.autoDispose<({List<AppNotification> items, int unread})>((ref) async {
  final data = await ref.watch(apiProvider).get('/api/notifications') as Map<String, dynamic>;
  return (
    items: (data['notifications'] as List)
        .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
        .toList(),
    unread: data['unread'] as int? ?? 0,
  );
});

/// Viewers of a device (owner only)
final sharesProvider = FutureProvider.autoDispose.family<List<Share>, int>((ref, deviceId) async {
  final list = await ref.watch(apiProvider).get('/api/devices/$deviceId/shares') as List;
  return list.map((item) => Share.fromJson(item as Map<String, dynamic>)).toList();
});

/// Personal code and friends of the user
final friendsProvider = FutureProvider.autoDispose<Friends>((ref) async {
  return Friends.fromJson(await ref.watch(apiProvider).get('/api/friends') as Map<String, dynamic>);
});

/// Arrival areas of the user on a device
final geofencesProvider = FutureProvider.autoDispose.family<List<Geofence>, int>((ref, deviceId) async {
  final list = await ref.watch(apiProvider).get('/api/devices/$deviceId/geofences') as List;
  return list.map((item) => Geofence.fromJson(item as Map<String, dynamic>)).toList();
});
