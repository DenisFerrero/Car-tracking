import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';
import 'add_device.dart' show deviceColors;

/// Icon of a device: the phone of a person, a car with a tracker or fed by a phone
IconData deviceIcon(Device device) => switch (device.kind) {
      'phone' => Icons.smartphone,
      'vehicle' => Icons.directions_car_filled,
      _ => Icons.directions_car,
    };

/// New vehicle without a tracker (POST /api/vehicles): the phone of the owner shares from
/// it while driving. Returns its id, null when cancelled.
Future<int?> createVehicle(BuildContext context, WidgetRef ref) async {
  final id = await showDialog<int>(context: context, builder: (context) => const _VehicleDialog());
  if (id != null) ref.invalidate(devicesProvider);
  return id;
}

class _VehicleDialog extends ConsumerStatefulWidget {
  const _VehicleDialog();

  @override
  ConsumerState<_VehicleDialog> createState() => _VehicleDialogState();
}

class _VehicleDialogState extends ConsumerState<_VehicleDialog> {
  final _name = TextEditingController();
  final _model = TextEditingController();
  String? _fuel;
  Color _color = deviceColors[3];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final created = await ref.read(apiProvider).post('/api/vehicles', {
        'name': _name.text.trim(),
        'model': _model.text.trim(),
        'fuelType': _fuel,
        'color': colorToHex(_color),
      }) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context, created['id'] as int);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.addVehicleTitle),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.vehicleIntro, style: Theme.of(context).textTheme.bodySmall),
          TextField(
            key: const Key('vehicleName'),
            controller: _name,
            maxLength: 60,
            autofocus: true,
            decoration: InputDecoration(labelText: l.vehicleName),
          ),
          TextField(
            key: const Key('newVehicleModel'),
            controller: _model,
            maxLength: 80,
            decoration: InputDecoration(labelText: l.vehicleModel),
          ),
          DropdownButtonFormField<String?>(
            key: const Key('newVehicleFuel'),
            initialValue: _fuel,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.fuelType),
            items: [
              for (final (value, label) in [('petrol', l.fuelPetrol), ('diesel', l.fuelDiesel), ('lpg', l.fuelLpg), (null, l.fuelOther)])
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (value) => setState(() => _fuel = value),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final color in deviceColors)
              InkWell(
                onTap: () => setState(() => _color = color),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: color,
                  child: _color.toARGB32() == color.toARGB32() ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                ),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('vehicleCreate'), onPressed: _busy ? null : _save, child: Text(l.addVehicle)),
      ],
    );
  }
}
