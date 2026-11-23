import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

DateTime? _date(dynamic value) => value == null ? null : DateTime.parse(value as String).toLocal();
double? _double(dynamic value) => value == null ? null : (value as num).toDouble();
int? _int(dynamic value) => value == null ? null : (value as num).round();

/// Status of a point, as sent by the tracker (viewers get only moving / parked)
enum TrackStatus {
  moving,
  engineOff,
  heartbeat,
  alarm;

  static TrackStatus of(int value) => TrackStatus.values[value.clamp(0, 3)];
}

/// Events of a point (bit field of the protocol)
class TrackEvents {
  static const motion = 0x01;
  static const tilt = 0x02;
  static const powerLost = 0x04;
  static const lowBattery = 0x08;
}

class Position {
  Position({
    required this.time,
    this.lat,
    this.lon,
    this.altitude,
    this.speed,
    this.pressure,
    this.temperature,
    this.voltage,
    this.satellites,
    this.signal,
    this.events = 0,
    this.status = TrackStatus.heartbeat,
    this.stale = false,
    this.cellLat,
    this.cellLon,
    this.cellAccuracy,
    this.accuracy,
  });

  factory Position.fromJson(Map<String, dynamic> json) => Position(
        time: _date(json['time'])!,
        lat: _double(json['lat']),
        lon: _double(json['lon']),
        altitude: _int(json['altitude']),
        speed: _int(json['speed']),
        pressure: _double(json['pressure']),
        temperature: _double(json['temperature']),
        voltage: _double(json['voltage']),
        satellites: _int(json['satellites']),
        signal: _int(json['signal']),
        events: _int(json['events']) ?? 0,
        status: TrackStatus.of(_int(json['status']) ?? 2),
        stale: json['stale'] == true,
        cellLat: _double(json['cell_lat']),
        cellLon: _double(json['cell_lon']),
        cellAccuracy: _int(json['cell_accuracy']),
        accuracy: _int(json['accuracy']),
      );

  final DateTime time;
  final double? lat;
  final double? lon;
  final int? altitude;
  final int? speed;
  final double? pressure;
  final double? temperature;
  final double? voltage;
  final int? satellites;
  final int? signal;
  final int events;
  final TrackStatus status;

  /// No GNSS fix: last known position, or the serving cell
  final bool stale;
  final double? cellLat;
  final double? cellLon;
  final int? cellAccuracy;

  /// Radius of the fix of a phone (m)
  final int? accuracy;

  /// GNSS position, or the estimate from the cell
  LatLng? get point {
    if (lat != null && lon != null) return LatLng(lat!, lon!);
    if (cellLat != null && cellLon != null) return LatLng(cellLat!, cellLon!);
    return null;
  }

  bool get fromCell => lat == null && cellLat != null;
}

/// State of a device for the filters of the map
enum DeviceState { moving, parked, offline }

/// A device seen by the user: owned (all the data) or shared with them (view only:
/// position, state, name, owner and end of the share). A tracker, or a phone that shares
/// its own position.
/// Period of a tracker in a vehicle
class Installation {
  Installation({required this.imei, required this.installedAt, this.removedAt});

  factory Installation.fromJson(Map<String, dynamic> json) => Installation(
        imei: json['imei'] as String,
        installedAt: DateTime.parse(json['installedAt'] as String).toLocal(),
        removedAt: _date(json['removedAt']),
      );

  final String imei;
  final DateTime installedAt;
  final DateTime? removedAt;
}

class Device {
  Device({
    required this.id,
    required this.name,
    required this.color,
    required this.role,
    this.kind = 'tracker',
    this.imei = '',
    this.model = '',
    this.manufacturer = '',
    this.firmware = '',
    this.registeredAt,
    this.lastSeenAt,
    this.connected = false,
    this.lastPosition,
    this.liveUntil,
    this.antitheftPausedUntil,
    this.shareExpiresAt,
    this.ownerName,
    this.battery,
    this.pausedUntil,
    this.stopAlertHours,
    this.batteryAlert,
    this.archived = false,
    this.installations = const [],
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as int,
        kind: json['kind'] as String? ?? 'tracker',
        imei: json['imei'] as String? ?? '',
        name: json['name'] as String,
        color: parseColor(json['color'] as String?),
        role: json['role'] as String? ?? 'viewer',
        model: json['model'] as String? ?? '',
        manufacturer: json['manufacturer'] as String? ?? '',
        firmware: json['firmware'] as String? ?? '',
        registeredAt: _date(json['registeredAt']),
        lastSeenAt: _date(json['lastSeenAt']),
        connected: json['connected'] == true,
        lastPosition: json['lastPosition'] == null
            ? null
            : Position.fromJson(json['lastPosition'] as Map<String, dynamic>),
        liveUntil: _unix(json['liveUntil']),
        antitheftPausedUntil: _unix(json['antitheftPausedUntil']),
        shareExpiresAt: _date(json['shareExpiresAt']),
        ownerName: json['ownerName'] as String?,
        battery: json['battery'] as int?,
        pausedUntil: _date(json['pausedUntil']),
        stopAlertHours: json['stopAlertHours'] as int?,
        batteryAlert: json['batteryAlert'] as int?,
        archived: json['archived'] == true,
        installations: [
          for (final item in (json['installations'] as List? ?? const []).cast<Map<String, dynamic>>()) Installation.fromJson(item),
        ],
      );

  final int id;

  /// tracker or phone
  final String kind;
  final String imei;
  String name;
  Color color;
  final String role;
  final String model;
  final String manufacturer;
  String firmware;
  final DateTime? registeredAt;
  DateTime? lastSeenAt;
  bool connected;
  Position? lastPosition;
  DateTime? liveUntil;
  DateTime? antitheftPausedUntil;
  final DateTime? shareExpiresAt;
  final String? ownerName;

  /// Phones: battery of the phone (%) and end of the pause chosen by its owner
  int? battery;
  DateTime? pausedUntil;

  /// Alerts of the logged user: long stop after these hours outside their areas, low
  /// battery (%) of a phone shared with them; null = off
  int? stopAlertHours;
  int? batteryAlert;

  /// Vehicle kept for its history, hidden from the map
  final bool archived;

  /// Trackers installed in this vehicle, latest first (detail of the owner)
  final List<Installation> installations;

  bool get isOwner => role == 'owner';
  bool get isPaused => pausedUntil != null && pausedUntil!.isAfter(DateTime.now());

  /// Realtime "device" event: online, last contact, battery and pause of a phone
  void applyEvent(Map<String, dynamic> event) {
    if (event['online'] == true) connected = true;
    if (event['lastSeenAt'] != null) lastSeenAt = DateTime.parse(event['lastSeenAt'] as String).toLocal();
    if (event.containsKey('battery')) battery = event['battery'] as int?;
    if (event.containsKey('pausedUntil')) pausedUntil = _date(event['pausedUntil']);
  }
  bool get isPhone => kind == 'phone';

  /// Car without a tracker: positions from the phone of the owner while driving
  bool get isVehicle => kind == 'vehicle';

  /// With the firmware: commands, alarms, modem, SIM, updates
  bool get isTracker => kind == 'tracker';
  bool get isLive => liveUntil != null && liveUntil!.isAfter(DateTime.now());

  /// Moving: a recent point while driving. Unreachable: a tracker silent for longer than
  /// the threshold of the server, a phone that stopped sharing. A vehicle fed by a phone is
  /// never unreachable: without the phone on board it's parked.
  DeviceState stateAt(DateTime now, Duration offlineAfter) {
    final seen = lastSeenAt;
    final offline = switch (kind) {
      'vehicle' => false,
      'phone' => !connected,
      _ => seen == null || now.difference(seen) > offlineAfter,
    };
    if (offline) return DeviceState.offline;
    final p = lastPosition;
    if (p != null && p.status == TrackStatus.moving && now.difference(p.time) < const Duration(minutes: 10)) {
      return DeviceState.moving;
    }
    return DeviceState.parked;
  }

  /// Viewers: the backend sends registeredAt only to the owner
  bool get waitingFirstContact => isOwner && registeredAt == null;

  static DateTime? _unix(dynamic value) =>
      value == null ? null : DateTime.fromMillisecondsSinceEpoch((value as num).toInt() * 1000);
}

Color parseColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return const Color(0xFF1E88E5);
  return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
}

String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Data of a notification, localized by the app: device name, area, time of the event
class NotificationData {
  NotificationData({
    required this.device,
    required this.time,
    this.area,
    this.battery,
    this.hours,
    this.voltage,
    this.maintenance,
    this.title,
    this.due,
    this.days,
    this.km,
    this.version,
    this.automatic,
    this.month,
    this.distanceKm,
    this.trips,
    this.cost,
  });

  factory NotificationData.fromJson(Map<String, dynamic>? json, DateTime fallback) => NotificationData(
        device: json?['device'] as String? ?? '',
        area: json?['area'] as String?,
        battery: _int(json?['battery']),
        hours: _int(json?['hours']),
        voltage: (json?['voltage'] as num?)?.toDouble(),
        maintenance: json?['maintenance'] as String?,
        title: json?['title'] as String?,
        due: json?['due'] as String?,
        days: _int(json?['days']),
        km: _int(json?['km']),
        version: json?['version'] as String?,
        automatic: json?['automatic'] as bool?,
        month: json?['month'] as String?,
        distanceKm: (json?['distanceKm'] as num?)?.toDouble(),
        trips: _int(json?['trips']),
        cost: (json?['cost'] as num?)?.toDouble(),
        time: _date(json?['time']) ?? fallback,
      );

  final String device;
  final String? area;

  /// phone_battery: % of the phone; long_stop: hours chosen by the owner
  final int? battery;
  final int? hours;

  /// battery_health: mean resting voltage of the car battery
  final double? voltage;

  /// maintenance: kind and title of the deadline, soon or due, days and km left
  final String? maintenance;
  final String? title;
  final String? due;
  final int? days;
  final int? km;

  /// monthly_summary: month YYYY-MM and its totals
  final String? month;
  final double? distanceKm;
  final int? trips;
  final double? cost;

  /// firmware: new version, installed by the tracker itself or by the owner
  final String? version;
  final bool? automatic;
  final DateTime time;
}

class AppNotification {
  AppNotification({
    required this.id,
    this.deviceId,
    required this.kind,
    required this.data,
    required this.createdAt,
    this.lat,
    this.lon,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final createdAt = _date(json['createdAt'])!;
    return AppNotification(
      id: json['id'] as int,
      deviceId: json['deviceId'] as int?,
      kind: json['kind'] as String,
      data: NotificationData.fromJson(json['data'] as Map<String, dynamic>?, createdAt),
      createdAt: createdAt,
      lat: _double(json['lat']),
      lon: _double(json['lon']),
      readAt: _date(json['readAt']),
    );
  }

  final int id;

  /// null for the summary of the month
  final int? deviceId;
  final String kind;
  final NotificationData data;
  final DateTime createdAt;
  final double? lat;
  final double? lon;
  DateTime? readAt;

  IconData get icon => switch (kind) {
        'tilt' => Icons.car_crash,
        'power_lost' => Icons.power_off,
        'low_battery' => Icons.battery_alert,
        'offline' => Icons.signal_cellular_off,
        'online' => Icons.signal_cellular_alt,
        'geofence_enter' => Icons.where_to_vote,
        'geofence_exit' => Icons.logout,
        'phone_battery' => Icons.battery_alert,
        'long_stop' => Icons.timer,
        'battery_health' => Icons.battery_3_bar,
        'maintenance' => Icons.build,
        'firmware' => Icons.system_update,
        'monthly_summary' => Icons.insights,
        _ => Icons.directions_car,
      };
}

/// Viewer of a device shared by the owner (always a friend)
class Share {
  Share({required this.userId, required this.name, this.expiresAt});

  factory Share.fromJson(Map<String, dynamic> json) => Share(
        userId: json['userId'] as int,
        name: json['name'] as String,
        expiresAt: _date(json['expiresAt']),
      );

  final int userId;
  final String name;

  /// null = until revoked
  final DateTime? expiresAt;
}

/// Arrival area of the user on a device: a circle notified on entry (and exit)
class Geofence {
  Geofence({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.radius,
    this.polygon,
    this.notifyEnter = true,
    this.notifyExit = false,
    this.schedule,
    this.inside,
  });

  factory Geofence.fromJson(Map<String, dynamic> json) => Geofence(
        id: json['id'] as int,
        deviceId: json['deviceId'] as int,
        name: json['name'] as String,
        lat: _double(json['lat'])!,
        lon: _double(json['lon'])!,
        radius: _int(json['radius'])!,
        polygon: (json['polygon'] as List?)
            ?.map((vertex) => LatLng(_double((vertex as List)[0])!, _double(vertex[1])!))
            .toList(),
        notifyEnter: json['notifyEnter'] != false,
        notifyExit: json['notifyExit'] == true,
        schedule: json['schedule'] == null ? null : AreaSchedule.fromJson(json['schedule'] as Map<String, dynamic>),
        inside: json['inside'] as bool?,
      );

  final int id;
  final int deviceId;
  final String name;
  final double lat;
  final double lon;
  final int radius;

  /// Vertices of an area drawn as a polygon; null = a circle (center and radius)
  final List<LatLng>? polygon;
  final bool notifyEnter;
  final bool notifyExit;

  /// null = always
  final AreaSchedule? schedule;
  final bool? inside;

  LatLng get center => LatLng(lat, lon);
}

/// Days (Monday = 1) and hours in which an area notifies, in the time zone of the server;
/// from after to: across midnight, from = to: the whole day
class AreaSchedule {
  const AreaSchedule({required this.days, required this.from, required this.to});

  factory AreaSchedule.fromJson(Map<String, dynamic> json) => AreaSchedule(
        days: (json['days'] as List).cast<int>(),
        from: _clock(json['from'] as String),
        to: _clock(json['to'] as String),
      );

  static TimeOfDay _clock(String value) => TimeOfDay(hour: int.parse(value.substring(0, 2)), minute: int.parse(value.substring(3, 5)));
  static String _text(TimeOfDay value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  final List<int> days;
  final TimeOfDay from;
  final TimeOfDay to;

  String get fromText => _text(from);
  String get toText => _text(to);
  bool get allDay => from == to;

  Map<String, dynamic> toJson() => {'days': [...days]..sort(), 'from': fromText, 'to': toText};
}

/// A friend: devices can be shared only with friends
class Friend {
  Friend({required this.id, required this.name, required this.since});

  factory Friend.fromJson(Map<String, dynamic> json) =>
      Friend(id: json['id'] as int, name: json['name'] as String, since: _date(json['since'])!);

  final int id;
  final String name;
  final DateTime since;
}

/// Personal code (shown as ABCDE-FGHJK and in a QR code), friends of the user and the
/// friend requests received and sent (since = date of the request)
class Friends {
  Friends({required this.code, required this.friends, this.incoming = const [], this.outgoing = const []});

  factory Friends.fromJson(Map<String, dynamic> json) {
    List<Friend> list(Object? items) => ((items as List?) ?? []).map((item) => Friend.fromJson(item as Map<String, dynamic>)).toList();
    return Friends(
      code: json['code'] as String,
      friends: list(json['friends']),
      incoming: list(json['incoming']),
      outgoing: list(json['outgoing']),
    );
  }

  /// Prefix of the QR codes of the friends (the labels of the trackers use CT1)
  static const qrPrefix = 'CTF1:';

  final String code;
  final List<Friend> friends;
  final List<Friend> incoming;
  final List<Friend> outgoing;

  String get formattedCode => code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;
  String get qr => '$qrPrefix$code';
}

class User {
  User({required this.id, required this.email, required this.name, required this.isAdmin, this.locale});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        email: json['email'] as String,
        name: json['name'] as String,
        isAdmin: json['isAdmin'] == true,
        locale: json['locale'] as String?,
      );

  final int id;
  final String email;
  final String name;
  final bool isAdmin;

  /// it / en, null until the app saves the language detected on the device
  final String? locale;
}

/// Public configuration of the platform (/api/config)
class ServerConfig {
  ServerConfig({
    required this.appName,
    required this.mapTileUrl,
    required this.mapAttribution,
    required this.simBudgetMb,
    required this.pushEnabled,
    this.offlineAfterHours = 9,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        appName: json['appName'] as String? ?? 'Car Tracking',
        mapTileUrl: json['mapTileUrl'] as String? ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        mapAttribution: json['mapAttribution'] as String? ?? '© OpenStreetMap contributors',
        simBudgetMb: (json['simBudgetMb'] as num?)?.toDouble() ?? 200,
        pushEnabled: json['pushEnabled'] == true,
        offlineAfterHours: (json['offlineAfterHours'] as num?)?.toDouble() ?? 9,
      );

  final String appName;
  final String mapTileUrl;
  final String mapAttribution;
  final double simBudgetMb;
  final bool pushEnabled;

  /// A tracker silent for longer is unreachable
  final double offlineAfterHours;
}
