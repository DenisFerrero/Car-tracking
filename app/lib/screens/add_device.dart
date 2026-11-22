import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';

/// Content of the QR code on the label of the tracker: `CT1:<IMEI>:<pairing code>`
({String imei, String code})? parseLabel(String value) {
  final match = RegExp(r'^CT1:(\d{15}):([0-9A-Za-z-]{8,9})$').firstMatch(value.trim());
  if (match == null) return null;
  return (imei: match[1]!, code: match[2]!.toUpperCase());
}

const deviceColors = [
  Color(0xFF1E88E5), Color(0xFFE53935), Color(0xFF43A047), Color(0xFFFB8C00),
  Color(0xFF8E24AA), Color(0xFF00ACC1), Color(0xFF6D4C41), Color(0xFF546E7A),
];

/// Guided procedure to add a tracker:
/// 1. label: QR code or IMEI + pairing code (proof of physical possession)
/// 2. vehicle: a new one (name and color) or a vehicle of the user without a tracker
/// 3. power on: the app waits for the first contact of the tracker in realtime
/// 4. done
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  final _imei = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  Color _color = deviceColors.first;
  int _step = 0;
  bool _busy = false;
  bool _scanning = false;
  bool _registered = false;
  int? _deviceId;

  /// Vehicle of the user to install the tracker in, null = new vehicle
  int? _vehicleId;
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty) _name.text = context.l10n.defaultDeviceName;
  }

  @override
  void dispose() {
    _events?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final imei = _imei.text.trim();
    if (!RegExp(r'^\d{15}$').hasMatch(imei)) {
      showMessage(context, context.l10n.imeiInvalid);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(apiProvider).post('/api/devices/claim/check', {
        'imei': imei,
        'code': _code.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      if (result['mine'] == true) {
        showMessage(context, context.l10n.alreadyMine);
      } else if (result['available'] != true) {
        showMessage(context, context.l10n.ownedByOther);
      } else {
        _registered = result['registered'] == true;
        setState(() => _step = 1);
      }
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim() async {
    if (_vehicleId == null && _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(apiProvider).post('/api/devices/claim', {
        'imei': _imei.text.trim(),
        'code': _code.text.trim(),
        if (_vehicleId == null) ...{'name': _name.text.trim(), 'color': colorToHex(_color)} else 'vehicleId': _vehicleId,
      }) as Map<String, dynamic>;
      _deviceId = result['id'] as int;
      _registered = result['registered'] == true;
      ref.invalidate(devicesProvider);
      if (!mounted) return;
      setState(() => _step = _registered ? 3 : 2);
      if (!_registered) _waitFirstContact();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Realtime event of the first HELLO, plus a slow poll in case the channel is down
  void _waitFirstContact() {
    final id = _deviceId!;
    _events = ref.read(liveProvider).device(id).listen((event) {
      if (event['type'] == 'registered' || (event['type'] == 'device' && event['online'] == true)) _done();
    });
    _poll = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final device = await ref.read(apiProvider).get('/api/devices/$id') as Map<String, dynamic>;
        if (device['registeredAt'] != null) _done();
      } catch (_) {}
    });
  }

  void _done() {
    _events?.cancel();
    _poll?.cancel();
    ref.invalidate(devicesProvider);
    if (mounted && _step == 2) setState(() => _step = 3);
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
  }

  void _onScan(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final label = parseLabel(barcode.rawValue ?? '');
      if (label != null) {
        setState(() {
          _scanning = false;
          _imei.text = label.imei;
          _code.text = label.code;
        });
        _check();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_scanning) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l.scanTitle),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _scanning = false)),
        ),
        body: MobileScanner(onDetect: _onScan),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.addTracker)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Stepper(
            currentStep: _step,
            controlsBuilder: (context, details) => const SizedBox.shrink(),
            steps: [
              Step(
                title: Text(l.stepLabel),
                subtitle: Text(l.stepLabelSub),
                isActive: _step >= 0,
                state: _step > 0 ? StepState.complete : StepState.indexed,
                content: _labelStep(),
              ),
              Step(
                title: Text(l.stepName),
                isActive: _step >= 1,
                state: _step > 1 ? StepState.complete : StepState.indexed,
                content: _nameStep(),
              ),
              Step(
                title: Text(l.stepPower),
                subtitle: Text(l.stepPowerSub),
                isActive: _step >= 2,
                state: _step > 2 ? StepState.complete : StepState.indexed,
                content: _powerStep(),
              ),
              Step(
                title: Text(l.stepDone),
                isActive: _step >= 3,
                state: _step >= 3 ? StepState.complete : StepState.indexed,
                content: _doneStep(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelStep() {
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.labelHint),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(l.scanQr),
      ),
      const SizedBox(height: 16),
      Text(l.manualEntry, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      TextField(
        key: const Key('imei'),
        controller: _imei,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(15)],
        decoration: InputDecoration(labelText: l.imeiLabel, border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('pairing'),
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: l.pairingCode, hintText: 'XXXX-XXXX', border: const OutlineInputBorder()),
        onSubmitted: (_) => _check(),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(onPressed: _busy ? null : _check, child: Text(l.verify)),
      ),
    ]);
  }

  Widget _nameStep() {
    final l = context.l10n;
    // Vehicles of the user without a tracker: the tracker can go in one of them
    final vehicles = [for (final d in ref.watch(devicesProvider).value ?? const <Device>[]) if (d.isVehicle && d.isOwner) d];
    Widget choice(Key key, int? id, IconData icon, Color? color, String title) => ListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: color, child: Icon(icon, color: color == null ? null : Colors.white)),
          title: Text(title),
          trailing: Icon(_vehicleId == id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: _vehicleId == id ? Theme.of(context).colorScheme.primary : null),
          onTap: () => setState(() => _vehicleId = id),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vehicles.isNotEmpty) ...[
        Text(l.pairInHint),
        const SizedBox(height: 8),
        choice(const Key('pairNew'), null, Icons.add, null, l.pairNewVehicle),
        for (final vehicle in vehicles)
          choice(Key('pairIn_${vehicle.id}'), vehicle.id, Icons.directions_car_filled, vehicle.color,
              vehicle.archived ? '${vehicle.name} · ${l.archived}' : vehicle.name),
        const SizedBox(height: 16),
      ],
      if (_vehicleId == null) ...[
        TextField(
          key: const Key('name'),
          controller: _name,
          maxLength: 60,
          decoration: InputDecoration(labelText: l.nameLabel, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Text(l.mapColor),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final color in deviceColors)
            InkWell(
              onTap: () => setState(() => _color = color),
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                backgroundColor: color,
                child: _color == color ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            ),
        ]),
        const SizedBox(height: 16),
      ],
      // Wraps on narrow phones
      OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, overflowAlignment: OverflowBarAlignment.end, children: [
        TextButton(onPressed: _busy ? null : () => setState(() => _step = 0), child: Text(l.back)),
        FilledButton(onPressed: _busy ? null : _claim, child: Text(l.addToAccount)),
      ]),
    ]);
  }

  Widget _powerStep() {
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(leading: const Icon(Icons.sim_card), title: Text(l.insertSim)),
      ListTile(leading: const Icon(Icons.power), title: Text(l.connectPower)),
      ListTile(
        leading: const Icon(Icons.wb_sunny_outlined),
        title: Text(l.parkOutside),
        subtitle: Text(l.firstFixHint),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(width: 16),
        Expanded(child: Text(l.waitingTracker)),
      ]),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => context.go('/devices/$_deviceId'),
          child: Text(l.continueLater),
        ),
      ),
    ]);
  }

  Widget _doneStep() {
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 32),
        const SizedBox(width: 12),
        Expanded(child: Text(l.trackerConnected)),
      ]),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: _deviceId == null ? null : () => context.go('/devices/$_deviceId'),
          child: Text(l.openDevice),
        ),
      ),
    ]);
  }
}
