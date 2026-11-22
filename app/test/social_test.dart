import 'dart:async';
import 'dart:convert';

import 'package:car_tracking/core/models.dart';
import 'package:car_tracking/core/phone_uploader.dart';
import 'package:car_tracking/screens/device/device_screen.dart';
import 'package:car_tracking/screens/friends.dart';
import 'package:car_tracking/screens/map_overview.dart';
import 'package:car_tracking/widgets/base_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// Owned tracker driving, shared tracker parked, own phone, shared phone that stopped
FakeBackend mapBackend() => fullBackend()
  ..on('GET', '/api/devices', (_) => [
        {...ownerDevice(), 'lastPosition': positionJson(age: const Duration(minutes: 1), lat: 45.07)},
        {...viewerDevice(), 'lastSeenAt': iso(ago(const Duration(hours: 1))), 'lastPosition': positionJson(status: 1, lat: 45.2, full: false)},
        phoneDevice(),
        {...phoneDevice(id: 4, owner: false, connected: false), 'name': 'iPhone Mario', 'lastPosition': {...positionJson(lat: 45.3, full: false), 'accuracy': 30}},
        {...viewerDevice(), 'id': 5, 'name': 'Furgone', 'ownerName': 'Sara', 'lastSeenAt': iso(ago(const Duration(days: 2)))},
      ]);

/// Distinct fixes sent (requests that failed offline are recorded too)
int positionsSent(FakeBackend backend) => {
      for (final request in backend.calls('/api/phones/positions', 'POST'))
        for (final fix in jsonDecode(request.body)['positions'] as List) (fix as Map)['time'],
    }.length;

void main() {
  setUpAll(initFormats);

  test('codes of friends from QR codes and typed text', () {
    expect(parseFriendCode('CTF1:ABCDE12345'), 'ABCDE12345');
    expect(parseFriendCode(' abcde-12345 '), 'ABCDE12345');
    expect(parseFriendCode('CT1:863820040182648:6MDFSV3C'), isNull);
    expect(parseFriendCode('short'), isNull);
    final friends = Friends(code: 'ABCDE12345', friends: []);
    expect(friends.formattedCode, 'ABCDE-12345');
    expect(friends.qr, 'CTF1:ABCDE12345');
    expect(Friends(code: 'X', friends: []).formattedCode, 'X');
  });

  test('state of the devices for the filters', () {
    final now = DateTime.now();
    const offline = Duration(hours: 9);
    final moving = Device.fromJson(ownerDevice());
    expect(moving.stateAt(now, offline), DeviceState.moving);
    expect(moving.stateAt(now.add(const Duration(minutes: 30)), offline), DeviceState.parked);
    expect(moving.stateAt(now.add(const Duration(hours: 10)), offline), DeviceState.offline);
    expect(Device.fromJson({...ownerDevice(), 'lastSeenAt': null}).stateAt(now, offline), DeviceState.offline);
    expect(Device.fromJson(phoneDevice()).stateAt(now, offline), DeviceState.parked);
    expect(Device.fromJson(phoneDevice(connected: false)).stateAt(now, offline), DeviceState.offline);
    // A vehicle without the phone on board is parked, not unreachable
    expect(Device.fromJson(vehicleDevice()).stateAt(now.add(const Duration(days: 3)), offline), DeviceState.parked);
  });

  group('vehicles', () {
    testWidgets('new vehicle from the list: limit, created, its pages, removed', (tester) async {
      var devices = [ownerDevice(), viewerDevice()];
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => devices)
        ..on('GET', '/api/devices/4', (_) => vehicleDevice(connected: true))
        ..on('GET', '/api/devices/4/shares', (_) => [])
        ..on('GET', '/api/devices/4/positions', (_) => {'positions': [], 'truncated': false})
        ..on('POST', '/api/vehicles', (_) => Reply.error(400, 'too_many_vehicles'))
        ..on('DELETE', '/api/devices/4', (_) {
          devices = [ownerDevice(), viewerDevice()];
          return {'ok': true};
        });
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices');
      await settle(tester);
      // In the browser: tracker or vehicle, no phone
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.phoneOption), findsNothing);
      await tapAndSettle(tester, find.byKey(const Key('addVehicle')));
      await tapAndSettle(tester, find.byKey(const Key('vehicleCreate')));
      expect(backend.calls('/api/vehicles'), isEmpty);
      await tester.enterText(find.byKey(const Key('vehicleName')), ' Punto ');
      await tester.enterText(find.byKey(const Key('newVehicleModel')), 'Fiat Punto 1.4');
      await tapAndSettle(tester, find.byKey(const Key('newVehicleFuel')));
      await tapAndSettle(tester, find.text(it.fuelLpg).last);
      await tapAndSettle(tester, find.byKey(const Key('vehicleCreate')));
      expect(find.text(it.errTooManyVehicles), findsOneWidget);

      backend.on('POST', '/api/vehicles', (_) {
        devices = [...devices, vehicleDevice(connected: true)];
        return {'id': 4};
      });
      await tapAndSettle(tester, find.byKey(const Key('vehicleCreate')));
      await settle(tester);
      expect(backend.lastBody('/api/vehicles'), {'name': 'Punto', 'model': 'Fiat Punto 1.4', 'fuelType': 'lpg', 'color': '#FB8C00'});
      expect(find.byType(DeviceScreen), findsOneWidget);
      // Car pages without the modem ones
      expect(find.byKey(const Key('openMaintenance')), findsOneWidget);
      expect(find.byKey(const Key('openCosts')), findsOneWidget);
      expect(find.byKey(const Key('openExtra')), findsNothing);

      app.go(tester, '/devices/4?tab=0');
      await settle(tester);
      expect(find.textContaining(it.vehicleDriving), findsOneWidget);
      expect(find.textContaining(it.accuracyMeters('9')), findsOneWidget);
      expect(find.byKey(const Key('walkTo')), findsOneWidget);
      expect(find.text(it.live30), findsNothing);

      app.go(tester, '/devices/4?tab=4');
      await settle(tester);
      expect(find.text('${it.vehicleKind} · ${it.tapToRename}'), findsOneWidget);
      expect(find.text(it.imei), findsNothing);
      await app.phone.drive(4);
      await reveal(tester, find.text(it.removeVehicle));
      await tapAndSettle(tester, find.text(it.removeVehicle));
      expect(find.text(it.removeVehicleBody), findsOneWidget);
      await tapAndSettle(tester, find.text(it.confirm));
      expect(backend.calls('/api/devices/4', 'DELETE'), hasLength(1));
      expect(app.phone.vehicleId, isNull);
    });

    testWidgets('the phone shares as a vehicle or as the person', (tester) async {
      var devices = [ownerDevice(), viewerDevice(), vehicleDevice()];
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => devices)
        ..on('POST', '/api/phones', (_) => {'id': 3, 'uploadToken': 'upload-1'})
        ..on('POST', '/api/phones/positions', (_) => {'accepted': 1})
        ..on('POST', '/api/vehicles', (_) {
          devices = [...devices, {...vehicleDevice(id: 5), 'name': 'Furgone'}];
          return {'id': 5};
        });
      final app = TestApp(backend, web: false);
      final service = app.phoneService;
      await app.start(tester);
      app.go(tester, '/devices/phone');
      await settle(tester);
      Future<void> show(Finder finder) async {
        await reveal(tester, finder);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      await show(find.byKey(const Key('shareAs_4')));
      expect(find.byKey(const Key('shareAs_4')), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(const Key('shareAsPerson'))).selected, isTrue);

      // Chosen before the start: the service starts from the vehicle
      await tapAndSettle(tester, find.byKey(const Key('shareAs_4')));
      expect(app.phone.vehicleId, 4);
      await show(find.byKey(const Key('phoneStart')));
      await tapAndSettle(tester, find.byKey(const Key('phoneStart')));
      expect(service.stored!.toJson(), {'server': 'https://tracking.test', 'userId': 1, 'deviceId': 3, 'token': 'upload-1', 'vehicleId': 4});
      service.emit();
      await settle(tester);
      expect((backend.lastBody('/api/phones/positions')['positions'] as List).single, containsPair('vehicleId', 4));

      // Back to the person while sharing; offline fixes keep the choice made when taken
      backend.offline = true;
      service.emit(time: DateTime.now().subtract(const Duration(seconds: 30)));
      await settle(tester);
      await show(find.byKey(const Key('shareAsPerson')));
      await tapAndSettle(tester, find.byKey(const Key('shareAsPerson')));
      expect(find.text(it.shareAsChanged(it.shareAsPerson)), findsOneWidget);
      expect(service.stored!.vehicleId, isNull);
      backend.offline = false;
      service.emit();
      await settle(tester);
      final positions = backend.lastBody('/api/phones/positions')['positions'] as List;
      expect(positions, hasLength(2));
      expect(positions.first, containsPair('vehicleId', 4));
      expect((positions.last as Map).containsKey('vehicleId'), isFalse);
      expect((await SharedPreferences.getInstance()).getInt('phone.1.vehicle'), isNull);

      // A new vehicle from here is chosen at once
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
      await settle(tester);
      await show(find.byKey(const Key('phoneAddVehicle')));
      await tapAndSettle(tester, find.byKey(const Key('phoneAddVehicle')));
      await tester.enterText(find.byKey(const Key('vehicleName')), 'Furgone');
      await tapAndSettle(tester, find.byKey(const Key('vehicleCreate')));
      await settle(tester);
      expect(app.phone.vehicleId, 5);
      expect(tester.widget<ListTile>(find.byKey(const Key('shareAs_5'))).selected, isTrue);
      expect((await SharedPreferences.getInstance()).getInt('phone.1.vehicle'), 5);
      expect(PhoneStatus.fromJson(service.uploader!.status.toJson()).vehicleId, 5);
    });
  });

  group('friends', () {
    testWidgets('code, QR code, new code, add by code and scan, remove', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/account', (_) => {'user': userJson(), 'passkeys': [], 'sessions': [], 'recoveryCodesLeft': 10, 'pushEnabled': true})
        ..on('POST', '/api/friends/code', (_) => {'code': 'ZZZZZ99999'})
        ..on('POST', '/api/friends', (_) => {'id': 8, 'name': 'Bea'})
        ..on('DELETE', '/api/friends/7', (_) => {'ok': true, 'sharesEnded': 1});
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/account');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.friends));
      expect(find.byType(FriendsScreen), findsOneWidget);
      expect(find.text('ABCDE-12345'), findsOneWidget);
      await reveal(tester, find.text('Mario'));
      expect(find.text('Luca'), findsOneWidget);

      await tapAndSettle(tester, find.text(it.copy));
      expect(find.text(it.codeCopied), findsOneWidget);

      await tapAndSettle(tester, find.text(it.newCode));
      await tapAndSettle(tester, find.text(it.cancel));
      expect(backend.calls('/api/friends/code'), isEmpty);
      await tapAndSettle(tester, find.text(it.newCode));
      await tapAndSettle(tester, find.text(it.newCode).last);
      expect(backend.calls('/api/friends/code', 'POST').length, 1);

      // Not a code: nothing is sent
      await tester.enterText(find.byKey(const Key('friendCode')), 'nope');
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.friendCodeUnknown), findsOneWidget);
      expect(backend.calls('/api/friends', 'POST'), isEmpty);

      await tester.enterText(find.byKey(const Key('friendCode')), 'fghjk-23456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(backend.lastBody('/api/friends', 'POST'), {'code': 'FGHJK23456'});
      expect(find.text(it.friendAdded('Bea')), findsOneWidget);

      backend.on('POST', '/api/friends', (_) => Reply.error(404, 'not_found'));
      await tester.enterText(find.byKey(const Key('friendCode')), 'FGHJK23456');
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.friendCodeUnknown), findsOneWidget);
      backend.on('POST', '/api/friends', (_) => Reply.error(400, 'friend_self'));
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.errFriendSelf), findsOneWidget);

      // QR code of the friend: other codes are ignored
      backend.on('POST', '/api/friends', (_) => {'id': 9, 'name': 'Carlo'});
      await tapAndSettle(tester, find.byTooltip(it.scanFriend));
      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(const BarcodeCapture(barcodes: [Barcode(rawValue: 'CT1:863820040182648:6MDFSV3C')]));
      await settle(tester);
      expect(find.byType(MobileScanner), findsOneWidget);
      scanner.onDetect!(const BarcodeCapture(barcodes: [Barcode(rawValue: 'CTF1:QRQRQ55555')]));
      await settle(tester);
      expect(find.byType(MobileScanner), findsNothing);
      expect(backend.lastBody('/api/friends', 'POST'), {'code': 'QRQRQ55555'});
      await tapAndSettle(tester, find.byTooltip(it.scanFriend));
      await tapAndSettle(tester, find.byIcon(Icons.close));
      expect(find.byType(MobileScanner), findsNothing);

      await clearSnackbars(tester);
      await reveal(tester, find.text('Mario'));
      await tapAndSettle(tester, find.byTooltip(it.removeFriend).last);
      expect(find.text(it.removeFriendTitle('Mario')), findsOneWidget);
      await tapAndSettle(tester, find.text(it.removeFriend).last);
      expect(backend.calls('/api/friends/7', 'DELETE').length, 1);
      expect(find.text(it.friendRemoved), findsOneWidget);

      backend.on('DELETE', '/api/friends/5', (_) => Reply.error(404, 'not_found'));
      await clearSnackbars(tester);
      await tapAndSettle(tester, find.byTooltip(it.removeFriend).first);
      await tapAndSettle(tester, find.text(it.removeFriend).last);
      expect(find.text(it.errNotFound), findsOneWidget);
      backend.on('POST', '/api/friends/code', (_) => Reply.error(429, 'rate_limited'));
      await tapAndSettle(tester, find.text(it.newCode));
      await tapAndSettle(tester, find.text(it.newCode).last);
      expect(find.text(it.errRateLimited), findsOneWidget);
    });

    testWidgets('no friends, loading error and retry', (tester) async {
      final backend = fullBackend()..on('GET', '/api/friends', (_) => Reply.error(500, 'x'));
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/account/friends');
      await settle(tester);
      expect(find.text(it.errGeneric(500)), findsOneWidget);
      backend.on('GET', '/api/friends', (_) => {'code': 'ABCDE12345', 'friends': []});
      await tapAndSettle(tester, find.text(it.retry));
      expect(find.text(it.noFriends), findsOneWidget);
    });

    testWidgets('realtime: added by another user', (tester) async {
      final app = TestApp(fullBackend());
      await app.start(tester);
      app.socket.emit({'type': 'friends', 'userId': 8, 'name': 'Bea', 'added': true});
      await settle(tester);
      expect(find.text(it.friendAddedYou('Bea')), findsOneWidget);
      await clearSnackbars(tester);
      // Removed, or on the friends page: no message
      app.socket.emit({'type': 'friends', 'userId': 8, 'added': false});
      app.go(tester, '/account/friends');
      await settle(tester);
      app.socket.emit({'type': 'friends', 'userId': 9, 'name': 'Carlo', 'added': true});
      await settle(tester);
      expect(find.text(it.friendAddedYou('Carlo')), findsNothing);
    });

    testWidgets('sharing needs a friend', (tester) async {
      final backend = fullBackend()..on('GET', '/api/friends', (_) => Reply.error(500, 'x'));
      final app = TestApp(backend);
      await app.start(tester);
      app.go(tester, '/devices/1?tab=4');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.shareWith));
      expect(find.text(it.errGeneric(500)), findsOneWidget);

      backend.on('GET', '/api/friends', (_) => {'code': 'ABCDE12345', 'friends': []});
      await clearSnackbars(tester);
      await tapAndSettle(tester, find.text(it.shareWith));
      expect(find.text(it.noFriendsToShare), findsOneWidget);
      await tapAndSettle(tester, find.text(it.cancel));
      await tapAndSettle(tester, find.text(it.shareWith));
      await tapAndSettle(tester, find.text(it.goToFriends));
      expect(find.byType(FriendsScreen), findsOneWidget);
    });
  });

  group('phone', () {
    testWidgets('permission, start, positions, offline queue, stop, resume, deleted', (tester) async {
      final backend = fullBackend()
        ..on('POST', '/api/phones', (_) => Reply.error(400, 'too_many_phones'))
        ..on('POST', '/api/phones/3/token', (_) => Reply.error(500, 'internal'))
        ..on('POST', '/api/phones/positions', (_) => {'accepted': 1});
      final app = TestApp(backend, web: false);
      final service = app.phoneService;
      await app.start(tester);
      app.go(tester, '/devices');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.add));
      await tapAndSettle(tester, find.text(it.phoneOption));
      expect(find.text(it.phoneDefaultName('Anna')), findsOneWidget);
      expect(find.text(it.phoneAndroidHint), findsOneWidget);

      for (final (reason, text) in [('disabled', it.phoneLocationOff), ('denied', it.phoneDenied), ('deniedForever', it.phoneDeniedForever)]) {
        service.refuse = reason;
        await tapAndSettle(tester, find.byKey(const Key('phoneStart')));
        expect(find.text(text), findsOneWidget);
      }
      expect(backend.calls('/api/phones'), isEmpty);

      service.refuse = null;
      await tester.enterText(find.byKey(const Key('phoneName')), '');
      await tapAndSettle(tester, find.byKey(const Key('phoneStart')));
      expect(backend.calls('/api/phones'), isEmpty);
      await tester.enterText(find.byKey(const Key('phoneName')), 'Pixel');
      await tapAndSettle(tester, find.byIcon(Icons.check).hitTestable().first);
      await tapAndSettle(tester, find.byKey(const Key('phoneStart')));
      expect(find.text(it.errTooManyPhones), findsOneWidget);

      backend.on('POST', '/api/phones', (_) => {'id': 3, 'uploadToken': 'upload-1'});
      await tapAndSettle(tester, find.byKey(const Key('phoneStart')));
      expect(backend.lastBody('/api/phones'), {'name': 'Pixel', 'color': '#43A047'});
      expect(find.text(it.phoneSharing), findsOneWidget);
      expect(find.textContaining(it.phoneWaitingFix), findsOneWidget);
      expect(service.titles, [it.phoneNotificationTitle]);
      expect(service.stored!.toJson(), {'server': 'https://tracking.test', 'userId': 1, 'deviceId': 3, 'token': 'upload-1'});

      // "All the time" for the restart after a reboot, granted in the settings
      expect(find.text(it.phoneBackgroundHint), findsOneWidget);
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
      await settle(tester);
      await tapAndSettle(tester, find.text(it.phoneBackgroundAllow));
      expect(find.text(it.phoneBackgroundHint), findsNothing);
      service.always = false;
      await app.phone.checkBackground();
      await settle(tester);
      expect(find.text(it.phoneBackgroundHint), findsOneWidget);
      service.always = true;
      await app.phone.checkBackground();
      await settle(tester);
      expect(find.text(it.phoneBackgroundHint), findsNothing);

      // The positions go with the upload token, not with the session
      service.emit(speed: null);
      await settle(tester);
      final request = backend.calls('/api/phones/positions', 'POST').last;
      expect(request.headers['authorization'], 'Bearer upload-1');
      final body = backend.lastBody('/api/phones/positions');
      expect(body['positions'], hasLength(1));
      expect((body['positions'] as List).first, containsPair('accuracy', 8.0));
      expect(find.textContaining('±8 m'), findsOneWidget);

      // Offline: queued, sent with the next fix
      backend.offline = true;
      service.emit();
      await settle(tester);
      expect(find.textContaining(it.phoneQueued(1)), findsOneWidget);
      backend.offline = false;
      service.emit();
      await settle(tester);
      expect(positionsSent(backend), 3);
      expect(find.textContaining(it.phoneQueued(1)), findsNothing);

      // A long queue goes in batches of 100
      backend.offline = true;
      for (var i = 0; i < 150; i++) {
        service.emit(time: DateTime.now().subtract(Duration(seconds: 200 - i)));
      }
      await settle(tester);
      backend.offline = false;
      await service.uploader!.flush();
      await settle(tester);
      expect(positionsSent(backend), 153);

      await tapAndSettle(tester, find.text(it.phoneOpenDevice));
      expect(find.byType(DeviceScreen), findsOneWidget);
      app.go(tester, '/devices/phone');
      await settle(tester);
      await tapAndSettle(tester, find.text(it.phoneStop));
      expect(app.phone.sharing, isFalse);
      expect(service.stored, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('phone.1.sharing'), isFalse);
      expect(prefs.getInt('phone.1.device'), 3);

      // The same phone again: no new device, a new upload token
      expect(find.byKey(const Key('phoneName')), findsNothing);
      await tapAndSettle(tester, find.byKey(const Key('phoneStart')));
      expect(find.text(it.errGeneric(500)), findsOneWidget);
      expect(app.phone.sharing, isFalse);
      backend.on('POST', '/api/phones/3/token', (_) => {'uploadToken': 'upload-2'});
      await tapAndSettle(tester, find.byKey(const Key('phoneStart')));
      expect(backend.calls('/api/phones', 'POST').length, 2);
      expect(app.phone.sharing, isTrue);
      expect(service.stored!.token, 'upload-2');

      // Deleted from another device: the token is refused, the service stops
      backend.on('POST', '/api/phones/positions', (_) => Reply.error(401, 'invalid_token'));
      service.emit();
      await settle(tester);
      expect(app.phone.sharing, isFalse);
      expect(app.phone.deviceId, isNull);
      expect(await service.running(), isFalse);
      expect(find.text(it.phoneGone), findsOneWidget);
      expect(find.byKey(const Key('phoneName')), findsOneWidget);
    });

    testWidgets('running service: shown at the login, stopped at the logout', (tester) async {
      final app = TestApp(fullBackend(), web: false);
      app.phoneService.always = true;
      await app.phoneService.start(const PhoneConfig(server: 'https://tracking.test', userId: 1, deviceId: 3, token: 'upload-1'), labels: {'title': ''});
      app.phoneService.emit();
      await app.start(tester, prefs: {'phone.1.device': 3, 'phone.1.sharing': true});
      expect(app.phone.sharing, isTrue);
      expect(app.phone.deviceId, 3);
      expect(app.backend.calls('/api/phones/3/token'), isEmpty);
      app.go(tester, '/devices/phone');
      await settle(tester);
      // The state of the service, asked at the login
      expect(find.textContaining('±8 m'), findsOneWidget);
      expect(find.text(it.phoneBackgroundHint), findsNothing);
      await app.session.logout();
      await settle(tester);
      expect(app.phone.sharing, isFalse);
      expect(app.phone.deviceId, isNull);
      expect(await app.phoneService.running(), isFalse);
    });

    testWidgets('killed service resumed at the login with a new token', (tester) async {
      final backend = fullBackend()..on('POST', '/api/phones/3/token', (_) => {'uploadToken': 'upload-2'});
      final app = TestApp(backend, web: false);
      await app.start(tester, prefs: {'phone.1.device': 3, 'phone.1.sharing': true});
      expect(app.phone.sharing, isTrue);
      expect(app.phoneService.stored!.token, 'upload-2');
    });

    testWidgets('service of another user stopped, deleted phone forgotten at the login', (tester) async {
      final backend = fullBackend()..on('POST', '/api/phones/3/token', (_) => Reply.error(404, 'not_found'));
      final app = TestApp(backend, web: false);
      await app.phoneService.start(const PhoneConfig(server: 'https://tracking.test', userId: 9, deviceId: 5, token: 'other'), labels: {'title': ''});
      await app.start(tester, prefs: {'phone.1.device': 3, 'phone.1.sharing': true});
      expect(await app.phoneService.running(), isFalse);
      expect(app.phone.gone, isTrue);
      expect(app.phone.deviceId, isNull);
      expect((await SharedPreferences.getInstance()).getInt('phone.1.device'), isNull);
    });

    testWidgets('deleted meanwhile: a new phone at the next start', (tester) async {
      final backend = fullBackend()..on('POST', '/api/phones/3/token', (_) => Reply.error(404, 'not_found'));
      final app = TestApp(backend, web: false);
      await app.start(tester, prefs: {'phone.1.device': 3});
      expect(await app.phone.enable(name: 'Pixel', color: '#43A047'), isNull);
      expect(app.phone.gone, isTrue);
      expect(app.phone.deviceId, isNull);
      expect(app.phone.sharing, isFalse);
    });

    testWidgets('browser: no phone sharing', (tester) async {
      final app = TestApp(fullBackend());
      await app.start(tester);
      app.go(tester, '/devices');
      await settle(tester);
      // The add button goes straight to the trackers
      await tapAndSettle(tester, find.text(it.add));
      expect(find.text(it.phoneOption), findsNothing);
      app.go(tester, '/devices/phone');
      await settle(tester);
      expect(find.text(it.phoneOnlyAndroid), findsOneWidget);
      expect(find.byKey(const Key('phoneStart')), findsNothing);
      await app.phone.checkBackground();
      expect(app.phone.supported, isFalse);
    });

    testWidgets('uploads at most every period, repeats the last fix when still', (tester) async {
      final backend = fullBackend()..on('POST', '/api/phones/positions', (_) => {'accepted': 1});
      final fixes = StreamController<Fix>.broadcast();
      final statuses = <PhoneStatus>[];
      final uploader = PhoneUploader(
        const PhoneConfig(server: 'https://tracking.test', userId: 1, deviceId: 3, token: 'upload-1'),
        fixes.stream,
        client: backend.client,
        uploadEvery: const Duration(seconds: 10),
        keepAlive: const Duration(seconds: 30),
        onStatus: statuses.add,
      )..start();
      Fix fix() => (time: DateTime.now(), lat: 45.0, lon: 7.0, accuracy: 5.0, speed: 20.0, altitude: null);
      fixes.add(fix());
      await tester.pump();
      expect(positionsSent(backend), 1);
      fixes.add(fix());
      fixes.add(fix());
      await tester.pump(const Duration(seconds: 1));
      expect(positionsSent(backend), 1);
      await tester.pump(const Duration(seconds: 10));
      expect(positionsSent(backend), 3);
      await tester.pump(const Duration(seconds: 30));
      expect(positionsSent(backend), 4);
      expect(statuses.last.queued, 0);

      // An invalid batch is dropped, not retried forever
      backend.on('POST', '/api/phones/positions', (_) => Reply.error(400, 'bad_request'));
      await tester.pump(const Duration(seconds: 30));
      expect(uploader.queue, isEmpty);
      // Server errors: kept for the next attempt
      backend.on('POST', '/api/phones/positions', (_) => Reply.error(503, 'unavailable'));
      await tester.pump(const Duration(seconds: 30));
      expect(uploader.queue, hasLength(1));
      uploader.stop();
      await fixes.close();
    });

    test('configuration and state of the service survive the isolate boundary', () {
      const config = PhoneConfig(server: 'https://tracking.test', userId: 1, deviceId: 3, token: 'upload-1');
      expect(PhoneConfig.fromJson(config.toJson())!.toJson(), config.toJson());
      expect(PhoneConfig.fromJson(null), isNull);
      expect(PhoneConfig.fromJson({'server': 'x', 'userId': '1', 'deviceId': 3, 'token': 't'}), isNull);

      final time = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final status = PhoneStatus.fromJson(PhoneStatus(lastFix: (time: time, lat: 45.0, lon: 7.0, accuracy: 12.0, speed: 3.0, altitude: 200.0), queued: 4).toJson());
      expect(status.lastFix!.time, time);
      expect(status.lastFix!.accuracy, 12);
      expect(status.queued, 4);
      expect(status.gone, isFalse);
      final empty = PhoneStatus.fromJson(const PhoneStatus(gone: true).toJson());
      expect(empty.lastFix, isNull);
      expect(empty.gone, isTrue);
    });

    testWidgets('phone page of the device: no analysis, commands or alarms', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices/3', (_) => phoneDevice())
        ..on('GET', '/api/devices/3/positions', (_) => {'positions': [], 'truncated': false})
        ..on('GET', '/api/devices/3/shares', (_) => [])
        ..on('GET', '/api/devices/3/geofences', (_) => [])
        ..on('DELETE', '/api/devices/3', (_) => {'ok': true});
      final app = TestApp(backend, web: false);
      await app.start(tester, prefs: {'phone.1.device': 3});
      app.go(tester, '/devices/3');
      await settle(tester);
      expect(find.text(it.tabAnalysis), findsOneWidget);
      expect(find.text(it.sharingActive), findsOneWidget);
      expect(find.text(it.accuracyMeters('14')), findsOneWidget);
      expect(find.text(it.locate), findsNothing);

      await tapAndSettle(tester, find.text(it.tabHistory));
      expect(find.byType(TextButton), findsWidgets);
      await tapAndSettle(tester, find.text(it.tabSettings));
      expect(find.text(it.imei), findsNothing);
      expect(find.text(it.alarmNotifications), findsNothing);
      expect(backend.calls('/api/devices/3/notification-settings'), isEmpty);
      await tapAndSettle(tester, find.text(it.removePhone));
      expect(find.text(it.removePhoneTitle), findsOneWidget);
      await tapAndSettle(tester, find.text(it.confirm));
      expect(backend.calls('/api/devices/3', 'DELETE').length, 1);
      expect(app.phone.deviceId, isNull);
      expect((await SharedPreferences.getInstance()).getInt('phone.1.device'), isNull);
    });

    testWidgets('shared phone: viewer notice, list and marker', (tester) async {
      final backend = fullBackend()
        ..on('GET', '/api/devices', (_) => [phoneDevice(id: 4, owner: false)])
        ..on('GET', '/api/devices/4', (_) => phoneDevice(id: 4, owner: false))
        ..on('GET', '/api/devices/4/positions', (_) => {'positions': [], 'truncated': false})
        ..on('GET', '/api/devices/4/geofences', (_) => []);
      final app = TestApp(backend);
      await app.start(tester);
      expect(find.byIcon(Icons.smartphone), findsOneWidget);
      app.go(tester, '/devices');
      await settle(tester);
      expect(find.textContaining(it.accuracyMeters('14')), findsOneWidget);
      await tapAndSettle(tester, find.text('Pixel'));
      expect(find.textContaining(it.viewerNotice('Mario', '')), findsOneWidget);
      expect(find.text(it.tabSettings), findsNothing);
    });
  });

  group('map filters', () {
    testWidgets('ownership, state, kind, owner, name, frame', (tester) async {
      final app = TestApp(mapBackend());
      await app.start(tester);
      expect(find.byType(MapOverviewScreen), findsOneWidget);
      expect(find.text(it.shownCount(5, 5)), findsOneWidget);

      await tapAndSettle(tester, find.text(it.filterMine));
      expect(find.text(it.shownCount(3, 5)), findsOneWidget);
      await tapAndSettle(tester, find.text(it.filterShared));
      expect(find.text(it.noMatch), findsOneWidget);
      await tapAndSettle(tester, find.text(it.resetFilters));
      expect(find.text(it.shownCount(5, 5)), findsOneWidget);

      await tapAndSettle(tester, find.text(it.filterMoving));
      expect(find.text(it.shownCount(4, 5)), findsOneWidget);
      await tapAndSettle(tester, find.text(it.filterOffline));
      expect(find.text(it.shownCount(2, 5)), findsOneWidget);
      await tapAndSettle(tester, find.text(it.filterOffline));
      await tapAndSettle(tester, find.text(it.filterMoving));

      await tapAndSettle(tester, find.text(it.filterPhones));
      expect(find.text(it.shownCount(3, 5)), findsOneWidget);
      await tapAndSettle(tester, find.text(it.filterPhones));
      await tapAndSettle(tester, find.text(it.filterTrackers));
      expect(find.text(it.shownCount(2, 5)), findsOneWidget);
      await tapAndSettle(tester, find.text(it.filterTrackers));

      await tapAndSettle(tester, find.byKey(const Key('ownerFilter')));
      await tapAndSettle(tester, find.text(it.filterOwner('Mario')).last);
      expect(find.text(it.shownCount(2, 5)), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('ownerFilter')));
      await tapAndSettle(tester, find.text(it.filterAllOwners).last);
      expect(find.text(it.shownCount(5, 5)), findsOneWidget);

      await tester.enterText(find.byKey(const Key('searchDevices')), 'pix');
      await settle(tester);
      expect(find.text(it.shownCount(1, 5)), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip(it.fitAll));
      await tapAndSettle(tester, find.byType(DeviceMarker));
      expect(find.textContaining(it.accuracyMeters('14')), findsOneWidget);
      await tapAndSettle(tester, find.byIcon(Icons.close).last);

      await tester.enterText(find.byKey(const Key('searchDevices')), '');
      await settle(tester);
      await tapAndSettle(tester, find.byTooltip(it.fitAll));
      await tapAndSettle(tester, find.byTooltip('iPhone Mario'));
      expect(find.textContaining(it.sharedBy('Mario')), findsOneWidget);
    });

    test('filter defaults and copies', () {
      const filter = DeviceFilter();
      expect(filter.isDefault, isTrue);
      expect(filter.copyWith(query: 'x').isDefault, isFalse);
      expect(filter.copyWith(owner: () => 'Mario').copyWith().owner, 'Mario');
      expect(filter.copyWith(owner: () => 'Mario').copyWith(owner: () => null).owner, isNull);
    });
  });
}
