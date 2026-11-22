import 'package:car_tracking/screens/add_device.dart';
import 'package:car_tracking/screens/device/device_screen.dart';
import 'package:car_tracking/screens/devices.dart';
import 'package:car_tracking/widgets/base_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'support.dart';

void main() {
  setUpAll(initFormats);

  group('map overview', () {
    testWidgets('markers, card of the device, realtime positions', (tester) async {
      final app = TestApp(fullBackend());
      await app.start(tester);
      expect(find.byType(DeviceMarker), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget); // unread notifications

      await tapAndSettle(tester, find.byType(DeviceMarker).first);
      expect(find.text('Panda'), findsOneWidget);
      expect(find.textContaining('48 km/h'), findsOneWidget);

      app.socket.emit({'type': 'hello'});
      app.socket.emit({'type': 'position', 'deviceId': 1, 'position': positionJson(status: 2)});
      app.socket.emit({'type': 'position', 'deviceId': 99, 'position': positionJson()});
      app.socket.emit({'type': 'device', 'deviceId': 1});
      await settle(tester);
      expect(find.textContaining(it.statusParked), findsOneWidget);

      await tapAndSettle(tester, find.byIcon(Icons.close));
      expect(find.text('Panda'), findsNothing);

      await tapAndSettle(tester, find.byType(DeviceMarker).last);
      expect(find.textContaining(it.fromCell), findsOneWidget);
      await tapAndSettle(tester, find.text('Golf'));
      expect(find.byType(DeviceScreen), findsOneWidget);
    });

    testWidgets('no devices', (tester) async {
      // Android app: tracker or this phone
      final app = TestApp(fullBackend()..on('GET', '/api/devices', (_) => []), web: false);
      await app.start(tester);
      expect(find.text(it.noDevicesShort), findsOneWidget);
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.addChooseTitle), findsOneWidget);
      await tapAndSettle(tester, find.text(it.addTrackerOption));
      expect(find.byType(AddDeviceScreen), findsOneWidget);
    });

    testWidgets('errors, then retry', (tester) async {
      final backend = fullBackend()..on('GET', '/api/devices', (_) => Reply.error(500, 'boom'));
      final app = TestApp(backend);
      await app.start(tester);
      expect(find.text(it.errGeneric(500)), findsOneWidget);
      backend.on('GET', '/api/devices', (_) => [ownerDevice()]);
      await tapAndSettle(tester, find.text(it.retry));
      expect(find.byType(DeviceMarker), findsOneWidget);
    });

    testWidgets('a single device is centered, stale positions are marked', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => [
              {...ownerDevice(), 'lastPosition': positionJson(stale: true, status: 2)},
              {...viewerDevice(), 'lastPosition': null},
            ]);
      final app = TestApp(backend);
      await app.start(tester);
      await tapAndSettle(tester, find.byType(DeviceMarker));
      expect(find.textContaining(it.lastKnown), findsOneWidget);
    });
  });

  group('devices', () {
    testWidgets('owned and shared devices', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => [
              ownerDevice(),
              viewerDevice(),
              {...ownerDevice(registered: false), 'id': 3, 'name': 'Nuova'},
              {...ownerDevice(), 'id': 4, 'name': 'Ferma', 'lastPosition': null, 'connected': false},
              {...ownerDevice(), 'id': 5, 'name': 'Vuota', 'lastPosition': {'time': iso(DateTime.now())}},
            ]);
      final app = TestApp(backend);
      await app.start(tester);
      await tapAndSettle(tester, find.text(it.navDevices));
      expect(find.byType(DeviceTile), findsNWidgets(5));
      expect(find.textContaining(it.sharedBy('Mario')), findsOneWidget);
      expect(find.text(it.waitingFirstContact), findsOneWidget);
      expect(find.textContaining(it.noPosition), findsOneWidget);
      expect(find.byTooltip(it.signalTooltip('${it.qualityGood} (-80 dBm)')), findsWidgets);
      expect(find.byTooltip(it.signalTooltip(it.notAvailable)), findsOneWidget);

      await tester.drag(find.byType(DeviceTile).first, const Offset(0, 300));
      await settle(tester);
      await tapAndSettle(tester, find.text('Golf'));
      expect(find.byType(DeviceScreen), findsOneWidget);

      // Browser: tracker or vehicle (the phone sharing is in the Android app)
      app.go(tester, '/devices');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.add));
      await tapAndSettle(tester, find.text(it.addTrackerOption));
      expect(find.byType(AddDeviceScreen), findsOneWidget);
    });

    testWidgets('empty list', (tester) async {
      final app = TestApp(fullBackend()..on('GET', '/api/devices', (_) => []));
      await app.start(tester);
      app.go(tester, '/devices');
      await settle(tester);
      expect(find.text(it.noDevices), findsOneWidget);
    });

    testWidgets('error', (tester) async {
      final app = TestApp(fullBackend()..on('GET', '/api/devices', (_) => Reply.error(503, 'down')));
      await app.start(tester);
      app.go(tester, '/devices');
      await settle(tester);
      expect(find.text(it.errGeneric(503)), findsWidgets);
    });
  });

  group('notifications', () {
    testWidgets('list, read, open the device', (tester) async {
      final app = TestApp(fullBackend());
      await app.start(tester);
      await tapAndSettle(tester, find.text(it.navNotifications));
      expect(find.text(it.kindTilt), findsOneWidget);
      expect(find.text(it.kindGeofenceEnter('Golf')), findsOneWidget);
      expect(find.textContaining(it.notificationBodyExit('Casa', '')), findsOneWidget);

      await tapAndSettle(tester, find.text(it.markAllRead));
      expect(app.backend.calls('/api/notifications/read'), hasLength(1));

      await tapAndSettle(tester, find.text(it.kindTilt));
      expect(app.backend.lastBody('/api/notifications/read'), {'ids': [1]});
      expect(find.byType(DeviceScreen), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);

      app.go(tester, '/notifications');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.kindGeofenceExit('Golf')));
      expect(app.backend.calls('/api/notifications/read'), hasLength(2));
      expect(find.byType(DeviceScreen), findsOneWidget);
    });

    testWidgets('empty list', (tester) async {
      final app = TestApp(fullBackend()..on('GET', '/api/notifications', (_) => {'notifications': []}));
      await app.start(tester);
      app.go(tester, '/notifications');
      await settle(tester);
      expect(find.text(it.noNotifications), findsOneWidget);
      expect(find.text(it.markAllRead), findsNothing);
      await tester.drag(find.text(it.noNotifications), const Offset(0, 300));
      await settle(tester);
    });

    testWidgets('failing list', (tester) async {
      final app = TestApp(fullBackend()..on('GET', '/api/notifications', (_) => Reply.error(500, 'x')));
      await app.start(tester);
      app.go(tester, '/notifications');
      await settle(tester);
      expect(find.text(it.errGeneric(500)), findsOneWidget);
    });
  });

  group('shell', () {
    testWidgets('realtime notification toast opens the device', (tester) async {
      final app = TestApp(fullBackend());
      await app.start(tester);
      app.socket.emit({'type': 'notification', 'notification': notificationJson(9, 'geofence_enter', deviceId: 2, area: 'Casa')});
      await settle(tester);
      expect(find.textContaining(it.kindGeofenceEnter('Golf')), findsOneWidget);
      await tapAndSettle(tester, find.text(it.open));
      expect(find.byType(DeviceScreen), findsOneWidget);
    });

    testWidgets('a revoked share closes the device, granted ones appear', (tester) async {
      final app = TestApp(fullBackend());
      await app.start(tester);
      app.go(tester, '/devices/2');
      await settle(tester);
      expect(find.byType(DeviceScreen), findsOneWidget);

      app.socket.emit({'type': 'access', 'deviceId': 2, 'revoked': true});
      await settle(tester);
      expect(find.byType(DeviceScreen), findsNothing);
      expect(find.text(it.accessRevoked('Golf')), findsOneWidget);

      app.socket.emit({'type': 'access', 'deviceId': 7, 'revoked': true});
      app.socket.emit({'type': 'access', 'deviceId': 2, 'revoked': false});
      app.socket.emit({'type': 'registered', 'deviceId': 1});
      app.socket.emit({'type': 'other'});
      await settle(tester);
      expect(find.text(it.accessRevoked('')), findsOneWidget);
    });

    testWidgets('navigation rail on wide screens', (tester) async {
      final app = TestApp(fullBackend());
      await app.start(tester, size: const Size(1100, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      await tapAndSettle(tester, find.text(it.navAccount));
      expect(find.text(it.accountTitle), findsWidgets);
      await tapAndSettle(tester, find.text(it.navAccount));
      await tapAndSettle(tester, find.text(it.navMap));
      expect(find.byType(DeviceMarker), findsWidgets);
    });

    testWidgets('English users get the English app', (tester) async {
      final app = TestApp(fullBackend(locale: 'en'));
      await app.start(tester);
      expect(find.text(en.navMap), findsOneWidget);
    });
  });

  group('add device', () {
    FakeBackend claimBackend({Object? check, Object? claim}) => fullBackend()
      ..on('POST', '/api/devices/claim/check', (_) => check ?? {'available': true, 'registered': false})
      ..on('POST', '/api/devices/claim', (_) => claim ?? {'id': 1, 'registered': false});

    Future<void> enterLabel(WidgetTester tester, [String imei = '863820040182648']) async {
      await tester.enterText(find.byKey(const Key('imei')), imei);
      await tester.enterText(find.byKey(const Key('pairing')), '6MDF-SV3C');
    }

    testWidgets('label checks', (tester) async {
      final backend = claimBackend(check: {'mine': true});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/add');
      await settle(tester);

      await enterLabel(tester, '123');
      await tapAndSettle(tester, find.text(it.verify));
      expect(find.text(it.imeiInvalid), findsOneWidget);

      await enterLabel(tester);
      await tapAndSettle(tester, find.text(it.verify));
      expect(find.text(it.alreadyMine), findsOneWidget);

      backend.on('POST', '/api/devices/claim/check', (_) => {'available': false});
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text(it.ownedByOther), findsOneWidget);

      backend.on('POST', '/api/devices/claim/check', (_) => Reply.error(400, 'invalid_pairing'));
      await tapAndSettle(tester, find.text(it.verify));
      expect(find.text(it.errInvalidPairing), findsOneWidget);
      expect(backend.lastBody('/api/devices/claim/check'), {'imei': '863820040182648', 'code': '6MDF-SV3C'});
    });

    testWidgets('name, first contact in realtime, open the device', (tester) async {
      final backend = claimBackend();
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/add');
      await settle(tester);
      await enterLabel(tester);
      await tapAndSettle(tester, find.text(it.verify));
      expect(find.text(it.defaultDeviceName), findsOneWidget);

      await tapAndSettle(tester, find.text(it.back));
      await tapAndSettle(tester, find.text(it.verify));

      await tester.enterText(find.byKey(const Key('name')), '');
      await tapAndSettle(tester, find.text(it.addToAccount));
      expect(backend.calls('/api/devices/claim'), isEmpty);

      backend.on('POST', '/api/devices/claim', (_) => Reply.error(409, 'already_claimed'));
      await tester.enterText(find.byKey(const Key('name')), 'Panda');
      await tapAndSettle(tester, find.byType(CircleAvatar).at(1));
      await tapAndSettle(tester, find.text(it.addToAccount));
      expect(find.text(it.errAlreadyClaimed), findsOneWidget);

      backend.on('POST', '/api/devices/claim', (_) => {'id': 1, 'registered': false});
      await tapAndSettle(tester, find.text(it.addToAccount));
      expect(backend.lastBody('/api/devices/claim')['color'], '#E53935');
      expect(find.text(it.waitingTracker), findsOneWidget);

      app.socket.emit({'type': 'device', 'deviceId': 1, 'online': false});
      await settle(tester);
      expect(find.text(it.waitingTracker), findsOneWidget);
      app.socket.emit({'type': 'registered', 'deviceId': 1});
      await settle(tester);
      expect(find.text(it.trackerConnected), findsOneWidget);
      await tapAndSettle(tester, find.text(it.openDevice));
      expect(find.byType(DeviceScreen), findsOneWidget);
    });

    testWidgets('first contact found by the slow poll, or later', (tester) async {
      var registered = false;
      final backend = claimBackend()
        ..on('GET', '/api/devices/1', (_) => registered ? ownerDevice() : ownerDevice(registered: false));
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/add');
      await settle(tester);
      await enterLabel(tester);
      await tapAndSettle(tester, find.text(it.verify));
      await tapAndSettle(tester, find.text(it.addToAccount));

      backend.offline = true;
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);
      backend.offline = false;
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);
      expect(find.text(it.waitingTracker), findsOneWidget);
      registered = true;
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);
      expect(find.text(it.trackerConnected), findsOneWidget);

      app.go(tester, '/devices');
      await settle(tester);
      app.go(tester, '/devices/add');
      await settle(tester);
      await enterLabel(tester);
      await tapAndSettle(tester, find.text(it.verify));
      backend.on('GET', '/api/devices/1', (_) => ownerDevice(registered: false));
      await tapAndSettle(tester, find.text(it.addToAccount));
      await tapAndSettle(tester, find.text(it.continueLater));
      expect(find.byType(DeviceScreen), findsOneWidget);
    });

    testWidgets('QR code of the label', (tester) async {
      final backend = claimBackend();
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/add');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.scanQr));
      expect(find.text(it.scanTitle), findsOneWidget);
      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(const BarcodeCapture(barcodes: [Barcode(rawValue: 'https://example.com')]));
      await settle(tester);
      expect(find.text(it.scanTitle), findsOneWidget);
      scanner.onDetect!(const BarcodeCapture(barcodes: [Barcode(rawValue: 'CT1:863820040182648:6MDFSV3C')]));
      await settle(tester);
      expect(backend.lastBody('/api/devices/claim/check'), {'imei': '863820040182648', 'code': '6MDFSV3C'});
      expect(find.text(it.defaultDeviceName), findsOneWidget);

      await tapAndSettle(tester, find.text(it.back));
      await tapAndSettle(tester, find.text(it.scanQr));
      await tapAndSettle(tester, find.byIcon(Icons.close));
      expect(find.text(it.scanTitle), findsNothing);
    });

    testWidgets('tracker already registered skips the power step', (tester) async {
      final app = TestApp(claimBackend(claim: {'id': 1, 'registered': true}));
      await app.start(tester);
      app.go(tester, '/devices/add');
      await settle(tester);
      await enterLabel(tester);
      await tapAndSettle(tester, find.text(it.verify));
      await tapAndSettle(tester, find.text(it.addToAccount));
      expect(find.text(it.trackerConnected), findsOneWidget);
    });
  });
}
