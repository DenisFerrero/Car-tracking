import 'dart:convert';

import 'package:car_tracking/core/format.dart';
import 'package:car_tracking/core/models.dart';
import 'package:car_tracking/screens/notifications.dart';
import 'package:car_tracking/screens/public_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Parking of a vehicle (live panel, settings), temporary links to the position and their
// page without an account, notifications of the parking and of the errors of the platform

Map<String, dynamic> parkingJson({DateTime? end, double? lat = 45.07, String note = ''}) => {
      'id': 3,
      'lat': lat,
      'lon': lat == null ? null : 7.68,
      'startedAt': iso(ago(const Duration(minutes: 20))),
      'expiresAt': end == null ? null : iso(end),
      'remindMinutes': 10,
      'note': note,
      'userId': 1,
    };

/// The parking of the tracker 1 and of the vehicle 4, kept by the fake backend
FakeBackend parkingBackend() {
  final parked = <int, Map<String, dynamic>?>{1: null, 4: null};
  final prompt = <int, bool>{1: false, 4: false};
  Map<String, dynamic> state(int id) => {
        'parking': parked[id],
        'position': id == 1 ? {'lat': 45.07, 'lon': 7.68, 'time': iso(ago(const Duration(minutes: 2)))} : null,
        'prompt': prompt[id],
      };
  final backend = fullBackend()
    ..on('GET', '/api/devices', (_) => [ownerDevice(), vehicleDevice()])
    ..on('GET', '/api/devices/4', (_) => vehicleDevice())
    ..on('GET', '/api/devices/4/positions', (_) => {'positions': [], 'truncated': false})
    ..on('GET', '/api/devices/1/links', (_) => {'links': [], 'max': 5});
  for (final id in [1, 4]) {
    backend
      ..on('GET', '/api/devices/$id/parking', (_) => state(id))
      ..on('PUT', '/api/devices/$id/parking', (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final end = body['expiresAt'] as String?;
        parked[id] = {
          ...parkingJson(end: end == null ? null : DateTime.parse(end), lat: id == 1 ? 45.07 : null, note: body['note'] as String),
          'remindMinutes': body['remindMinutes'],
        };
        return state(id);
      })
      ..on('DELETE', '/api/devices/$id/parking', (_) {
        parked[id] = null;
        return state(id);
      })
      ..on('PUT', '/api/devices/$id/parking/prompt', (request) {
        prompt[id] = (jsonDecode(request.body) as Map<String, dynamic>)['enabled'] as bool;
        return state(id);
      });
  }
  return backend;
}

void main() {
  setUpAll(initFormats);

  test('texts and pages of the new notifications', () {
    final data = NotificationData(device: 'Panda', time: DateTime(2026, 11, 20, 9, 5), minutes: 8, source: 'backup', message: 'Disk full', others: 2);
    expect(notificationText(it, 'parking_prompt', data), (title: it.parkingPromptTitle('Panda'), body: it.parkingPromptBody('09:05')));
    expect(notificationText(it, 'parking_reminder', data).title, it.parkingReminderTitle(8));
    expect(notificationText(en, 'parking_expired', data), (title: en.parkingExpiredTitle, body: en.parkingExpiredBody('Panda', '09:05')));
    expect(notificationText(it, 'platform_error', data), (title: it.platformErrorTitle(3), body: 'backup: Disk full'));
    expect(kindLabel(it, 'platform_error'), it.kindPlatformError);
    expect(kindLabel(it, 'parking_expired'), it.kindParking);
    final km = NotificationData(device: 'Panda', time: DateTime(2026, 11, 20), maintenance: 'service', due: 'soon', km: 900, expected: '2026-12-04');
    expect(notificationText(it, 'maintenance', km).body, contains(it.expectedAround('')));

    AppNotification notification(String kind, {int? deviceId = 1}) =>
        AppNotification(id: 1, deviceId: deviceId, kind: kind, data: data, createdAt: DateTime(2026, 11, 20));
    expect(notificationTarget(notification('platform_error', deviceId: null), owner: false), '/account/admin/logs');
    expect(notificationTarget(notification('parking_reminder'), owner: true), '/devices/1?tab=0');
    expect(notificationTarget(notification('tilt'), owner: true), '/devices/1?tab=1');
    expect(notificationTarget(notification('tilt'), owner: false), '/devices/1?tab=0');
    for (final kind in ['platform_error', 'parking_prompt', 'parking_reminder', 'parking_expired']) {
      expect(notification(kind).icon, isNot(Icons.directions_car));
    }
  });

  testWidgets('parking from the live panel: with the end of the ticket, changed, without end, ended, errors', (tester) async {
    final backend = parkingBackend();
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1?tab=0');
    await settle(tester);

    await tapAndSettle(tester, find.text(it.parkHere));
    expect(find.text(it.parkingTitle), findsOneWidget);
    expect(find.byKey(const Key('parkingNoPlace')), findsNothing);
    // The end chosen with the pickers, a reminder 15 minutes before
    await tapAndSettle(tester, find.byKey(const Key('parkingEnd')));
    await tapAndSettle(tester, find.text('OK'));
    await tapAndSettle(tester, find.text('OK'));
    await tapAndSettle(tester, find.byKey(const Key('parkingRemind')));
    await tapAndSettle(tester, find.text(it.parkingRemindBefore(15)).last);
    await tester.enterText(find.byKey(const Key('parkingNote')), ' Piano -2 ');
    await tapAndSettle(tester, find.byKey(const Key('parkingSave')));
    final body = backend.lastBody('/api/devices/1/parking', 'PUT');
    expect((body['remindMinutes'], body['note']), (15, 'Piano -2'));
    final end = DateTime.parse(body['expiresAt'] as String);
    expect(end.difference(DateTime.now()).inMinutes, inInclusiveRange(59, 75));
    expect(find.text(it.parkingSaved), findsOneWidget);
    expect(find.text(it.parkingUntil(formatTime(end.toLocal()))), findsOneWidget);
    expect(find.byKey(const Key('parkingMarker')), findsOneWidget);

    // Paid by the minute: no end
    await clearSnackbars(tester);
    await tapAndSettle(tester, find.byKey(const Key('parkingChip')));
    expect(find.text('Piano -2'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('parkingHasEnd')));
    expect(find.byKey(const Key('parkingRemind')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('parkingSave')));
    expect(backend.lastBody('/api/devices/1/parking', 'PUT')['expiresAt'], isNull);
    expect(find.textContaining(it.parkingActive('')), findsOneWidget);

    // Ended by hand; an error of the backend; cancelled
    await clearSnackbars(tester);
    await tapAndSettle(tester, find.byKey(const Key('parkingChip')));
    await tapAndSettle(tester, find.byKey(const Key('parkingStop')));
    expect(find.text(it.parkingStopped), findsOneWidget);
    expect(find.text(it.parkHere), findsOneWidget);
    await clearSnackbars(tester);
    backend.on('PUT', '/api/devices/1/parking', (_) => Reply.error(400, 'parking_past'));
    await tapAndSettle(tester, find.text(it.parkHere));
    await tapAndSettle(tester, find.byKey(const Key('parkingSave')));
    expect(find.text(it.errParkingPast), findsOneWidget);
    await clearSnackbars(tester);
    await tapAndSettle(tester, find.text(it.parkHere));
    await tapAndSettle(tester, find.text(it.cancel).last);
    expect(backend.calls('/api/devices/1/parking', 'PUT'), hasLength(3));
  });

  testWidgets('parking ended in the past; vehicle without a place', (tester) async {
    final backend = parkingBackend()
      ..on('GET', '/api/devices/1/parking', (_) => {
            'parking': parkingJson(end: ago(const Duration(minutes: 5))),
            'position': null,
            'prompt': false,
          });
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1?tab=0');
    await settle(tester);
    expect(find.textContaining(it.parkingExpired('')), findsOneWidget);

    app.go(tester, '/devices/4?tab=0');
    await settle(tester);
    await tapAndSettle(tester, find.text(it.parkHere));
    expect(find.byKey(const Key('parkingNoPlace')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('parkingSave')));
    expect(backend.calls('/api/devices/4/parking', 'PUT'), hasLength(1));
    expect(find.byKey(const Key('parkingMarker')), findsNothing);
  });

  testWidgets('settings: proposal of the parking, temporary links created, copied, revoked', (tester) async {
    final links = <Map<String, dynamic>>[
      {'id': 3, 'label': 'Mamma', 'expiresAt': iso(DateTime.now().add(const Duration(hours: 2))), 'createdAt': iso(ago(const Duration(minutes: 5))), 'lastViewedAt': iso(ago(const Duration(minutes: 1)))},
      {'id': 2, 'label': '', 'expiresAt': iso(DateTime.now().add(const Duration(hours: 20))), 'createdAt': iso(ago(const Duration(hours: 4))), 'lastViewedAt': null},
    ];
    final backend = parkingBackend()
      ..on('GET', '/api/devices/1/links', (_) => {'links': links, 'max': 3})
      ..on('POST', '/api/devices/1/links', (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final link = {'id': 4, 'label': body['label'], 'expiresAt': iso(DateTime.now().add(Duration(hours: body['hours'] as int))), 'createdAt': iso(DateTime.now()), 'lastViewedAt': null};
        links.insert(0, link);
        return {'id': 4, 'url': 'https://tracker.example/#/l/${'t' * 43}', 'expiresAt': link['expiresAt'], 'links': links};
      })
      ..on('DELETE', '/api/links/3', (_) {
        links.removeWhere((link) => link['id'] == 3);
        return {'links': links};
      });
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/devices/1?tab=4');
    await settle(tester);

    await reveal(tester, find.byKey(const Key('parkingPrompt')));
    await tapAndSettle(tester, find.byKey(const Key('parkingPrompt')));
    expect(backend.lastBody('/api/devices/1/parking/prompt', 'PUT'), {'enabled': true});
    backend.on('PUT', '/api/devices/1/parking/prompt', (_) => Reply.error(403, 'owner_only'));
    await tapAndSettle(tester, find.byKey(const Key('parkingPrompt')));
    expect(find.text(it.errOwnerOnly), findsOneWidget);

    await reveal(tester, find.byKey(const Key('liveLinkNew')));
    expect(find.text('Mamma'), findsOneWidget);
    expect(find.textContaining(it.liveLinkNotViewed), findsOneWidget);
    expect(find.textContaining(it.liveLinkViewed('')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('liveLinkNew')));
    await tester.enterText(find.byKey(const Key('liveLinkLabel')), ' Luca ');
    await tapAndSettle(tester, find.byKey(const Key('liveLinkHours')));
    await tapAndSettle(tester, find.text(it.liveLinkDuration(4)).last);
    await tapAndSettle(tester, find.byKey(const Key('liveLinkCreate')));
    expect(backend.lastBody('/api/devices/1/links', 'POST'), {'hours': 4, 'label': 'Luca'});
    expect(find.text(it.liveLinkCreated), findsOneWidget);
    expect(find.text('https://tracker.example/#/l/${'t' * 43}'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('liveLinkCopy')));
    expect(find.text(it.liveLinkCopied), findsOneWidget);
    await tapAndSettle(tester, find.text(it.close));
    // The maximum reached: no new links
    expect(find.byKey(const Key('liveLinkNew')), findsNothing);

    await clearSnackbars(tester);
    await tapAndSettle(tester, find.byKey(const Key('liveLinkRevoke_3')));
    expect(find.text(it.liveLinkRevoked), findsOneWidget);
    expect(find.text('Mamma'), findsNothing);
    backend.on('DELETE', '/api/links/2', (_) => Reply.error(404, 'not_found'));
    await tapAndSettle(tester, find.byKey(const Key('liveLinkRevoke_2')));
    expect(find.text(it.errNotFound), findsOneWidget);
    // Database down on the server: a message to try again, not an internal error
    await clearSnackbars(tester);
    backend.on('DELETE', '/api/links/2', (_) => Reply.error(503, 'unavailable'));
    await tapAndSettle(tester, find.byKey(const Key('liveLinkRevoke_2')));
    expect(find.text(it.errUnavailable), findsOneWidget);
    backend.on('POST', '/api/devices/1/links', (_) => Reply.error(400, 'too_many_links'));
    await reveal(tester, find.byKey(const Key('liveLinkNew')));
    await tapAndSettle(tester, find.byKey(const Key('liveLinkNew')));
    await tapAndSettle(tester, find.byKey(const Key('liveLinkCreate')));
    expect(find.text(it.errTooManyLinks), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('liveLinkNew')));
    await tapAndSettle(tester, find.text(it.cancel).last);
    expect(backend.calls('/api/devices/1/links', 'POST'), hasLength(2));
  });

  testWidgets('page of a temporary link without an account: position, refreshed, then ended', (tester) async {
    final token = 'a' * 43;
    var position = <String, dynamic>{'lat': 45.1, 'lon': 7.7, 'time': iso(ago(const Duration(minutes: 1))), 'speed': 52};
    final backend = fullBackend(stage: 'none')
      ..on('GET', '/api/public/links/$token', (_) => {
            'name': 'Panda',
            'color': '#FF5722',
            'kind': 'vehicle',
            'expiresAt': iso(DateTime.now().add(const Duration(hours: 2))),
            'position': position,
          });
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/l/$token');
    await settle(tester);
    expect(find.text('Panda'), findsOneWidget);
    expect(find.textContaining(it.publicLinkMoving('52')), findsOneWidget);
    expect(find.textContaining(it.publicLinkUntil('')), findsOneWidget);

    position = {...position, 'lat': 45.2, 'speed': null};
    await tester.pump(publicLinkRefresh);
    await settle(tester);
    expect(find.textContaining(it.publicLinkMoving('52')), findsNothing);
    expect(backend.calls('/api/public/links/$token'), hasLength(2));

    backend.on('GET', '/api/public/links/$token', (_) => Reply.error(500, 'internal'));
    await tester.pump(publicLinkRefresh);
    await settle(tester);
    expect(find.text('Panda'), findsOneWidget);
    backend.on('GET', '/api/public/links/$token', (_) => Reply.error(404, 'not_found'));
    await tester.pump(publicLinkRefresh);
    await settle(tester);
    expect(find.byKey(const Key('publicLinkGone')), findsOneWidget);
    // Ended: not read again
    await tester.pump(publicLinkRefresh * 2);
    expect(backend.calls('/api/public/links/$token'), hasLength(4));
  });

  testWidgets('page of a temporary link: no position yet, error first', (tester) async {
    final token = 'b' * 43;
    final backend = fullBackend(stage: 'none')
      ..on('GET', '/api/public/links/$token', (_) => Reply.error(500, 'internal'));
    final app = TestApp(backend);
    await app.start(tester);
    app.go(tester, '/l/$token');
    await settle(tester);
    expect(find.text(it.errGeneric(500)), findsOneWidget);
    backend.on('GET', '/api/public/links/$token', (_) => {
          'name': 'Pixel',
          'color': '#43A047',
          'kind': 'phone',
          'expiresAt': iso(DateTime.now().add(const Duration(hours: 1))),
          'position': null,
        });
    await tester.pump(publicLinkRefresh);
    await settle(tester);
    expect(find.text(it.publicLinkNoPosition), findsOneWidget);
  });
}
