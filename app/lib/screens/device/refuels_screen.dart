import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import 'costs_screen.dart' show vehicleProvider;

final refuelsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) async => await ref.watch(apiProvider).get('/api/devices/$id/refuels') as Map<String, dynamic>,
);

String _text(num? value) => value == null ? '' : NumberFormat('0.##', Intl.getCurrentLocale()).format(value);
double? _parse(TextEditingController controller) => double.tryParse(controller.text.trim().replaceAll(',', '.'));
String _day(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Consumption (always per 100 km from the backend) in the unit of the owner: litres, or kWh
/// for the electric ones
String consumptionText(num value, String unit, [String energy = 'l']) =>
    unit == 'km_per_l' ? '${formatDecimal(100 / value, 1)} km/$energy' : '${formatDecimal(value.toDouble(), 1)} $energy/100 km';

/// Refuels of a vehicle: litres, amount, odometer, full tank. Between two full tanks the
/// backend measures the real consumption; with the option of the costs the prices and the
/// consumptions go into the costs of the trips. An electric vehicle has charges in kWh, at
/// home or at a station.
class RefuelsScreen extends ConsumerWidget {
  const RefuelsScreen({super.key, required this.deviceId});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final data = ref.watch(refuelsProvider(deviceId));

    Future<void> edit(Map<String, dynamic> state, [Map<String, dynamic>? refuel]) async {
      final result = await showDialog<Object>(
        context: context,
        builder: (_) => _RefuelDialog(refuel: refuel, odometerKm: state['odometerKm'] as int?, energy: state['energyUnit'] as String? ?? 'l'),
      );
      if (result == null || !context.mounted) return;
      final api = ref.read(apiProvider);
      try {
        if (result == _delete) {
          await api.delete('/api/refuels/${refuel!['id']}');
        } else if (refuel == null) {
          await api.post('/api/devices/$deviceId/refuels', result);
        } else {
          await api.patch('/api/refuels/${refuel['id']}', result);
        }
        ref.invalidate(refuelsProvider(deviceId));
        // Prices and consumptions of the costs follow the refuels
        ref.invalidate(vehicleProvider(deviceId));
        if (context.mounted) showMessage(context, l.refuelSaved);
      } on ApiException catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    final electric = data.value?['energyUnit'] == 'kWh';
    return Scaffold(
      appBar: AppBar(title: Text(electric ? l.charges : l.refuels)),
      floatingActionButton: data.whenOrNull(
        data: (state) => FloatingActionButton.extended(
          key: const Key('addRefuel'),
          onPressed: () => edit(state),
          icon: Icon(electric ? Icons.ev_station : Icons.local_gas_station),
          label: Text(electric ? l.addCharge : l.addRefuel),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(errorText(l, error))),
        data: (state) {
          final refuels = (state['refuels'] as List).cast<Map<String, dynamic>>();
          final summary = state['summary'] as Map<String, dynamic>;
          final unit = state['fuelUnit'] as String;
          final energy = state['energyUnit'] as String? ?? 'l';
          final average = summary['averageConsumption'] as num?;
          final last = summary['lastConsumption'] as num?;
          String consumption(num value) => consumptionText(value, unit, energy);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(refuelsProvider(deviceId).future),
            child: ListView(padding: readable(context, const EdgeInsets.fromLTRB(8, 8, 8, 96)), children: [
              Card(
                key: const Key('refuelSummary'),
                child: ListTile(
                  leading: const Icon(Icons.speed),
                  title: Text(average != null
                      ? l.realConsumption(consumption(average))
                      : electric
                          ? l.realConsumptionUnknownElectric
                          : l.realConsumptionUnknown),
                  subtitle: Text([
                    if (last != null) (electric ? l.lastCharge : l.lastConsumption)(consumption(last)),
                    (electric ? l.chargeTotals : l.refuelTotals)(summary['count'] as int, '${_text(summary['litres'] as num)} $energy',
                        summary['cost'] == null ? '-' : formatEuro(summary['cost'] as num)),
                    if (average != null) l.measuredKm(formatInt((summary['measuredKm'] as num).round())),
                  ].join('\n')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Text(electric ? l.chargesHint : l.refuelsHint, style: Theme.of(context).textTheme.bodySmall),
              ),
              ListTile(
                key: const Key('refuelRates'),
                dense: true,
                leading: Icon(state['ratesFromRefuels'] == true ? Icons.link : Icons.link_off),
                title: Text(state['ratesFromRefuels'] == true ? l.refuelRatesOn : l.refuelRatesOff),
                trailing: TextButton(onPressed: () => context.push('/devices/$deviceId/costs'), child: Text(l.tripCosts)),
              ),
              if (refuels.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(electric ? l.noCharges : l.noRefuels, key: const Key('noRefuels')))),
              for (final refuel in refuels)
                Card(
                  child: ListTile(
                    key: Key('refuel_${refuel['id']}'),
                    leading: Icon(electric
                        ? (refuel['place'] == 'home' ? Icons.home : Icons.ev_station)
                        : refuel['full'] == true
                            ? Icons.local_gas_station
                            : Icons.local_gas_station_outlined),
                    title: Text([
                      formatDay(DateTime.parse(refuel['day'] as String)),
                      '${_text(refuel['litres'] as num)} $energy',
                      if (refuel['cost'] != null) formatEuro(refuel['cost'] as num),
                    ].join(' · ')),
                    subtitle: Text([
                      if (refuel['place'] != null) refuel['place'] == 'home' ? l.chargeHome : l.chargePublic,
                      if (refuel['pricePerLitre'] != null) '${formatEuro(refuel['pricePerLitre'] as num, digits: 3)}/$energy',
                      if (refuel['odometerKm'] != null) '${formatInt(refuel['odometerKm'] as int)} km',
                      if (refuel['full'] != true) electric ? l.chargePartial : l.refuelPartial,
                      if (refuel['consumption'] != null)
                        l.refuelMeasured(consumption(refuel['consumption'] as num), formatInt(refuel['km'] as int)),
                      if ((refuel['note'] as String).isNotEmpty) refuel['note'] as String,
                    ].join(' · ')),
                    onTap: () => edit(state, refuel),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

/// Result of the dialog that deletes the refuel
const _delete = 'delete';

/// New or changed refuel: day, litres, amount (price per litre shown), odometer, full tank;
/// for a charge kWh and the place
class _RefuelDialog extends StatefulWidget {
  const _RefuelDialog({this.refuel, this.odometerKm, this.energy = 'l'});

  final Map<String, dynamic>? refuel;
  final int? odometerKm;
  final String energy;

  @override
  State<_RefuelDialog> createState() => _RefuelDialogState();
}

class _RefuelDialogState extends State<_RefuelDialog> {
  late final _litres = TextEditingController(text: _text(widget.refuel?['litres'] as num?));
  late final _cost = TextEditingController(text: _text(widget.refuel?['cost'] as num?));
  late final _odometer = TextEditingController(
      text: '${widget.refuel == null ? widget.odometerKm ?? '' : widget.refuel!['odometerKm'] ?? ''}');
  late final _note = TextEditingController(text: widget.refuel?['note'] as String?);
  late DateTime _date = widget.refuel == null ? DateTime.now() : DateTime.parse(widget.refuel!['day'] as String);
  late bool _full = widget.refuel?['full'] as bool? ?? true;
  late String? _place = widget.refuel?['place'] as String?;
  String? _error;

  bool get _electric => widget.energy == 'kWh';

  @override
  void dispose() {
    for (final controller in [_litres, _cost, _odometer, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final l = context.l10n;
    final litres = _parse(_litres);
    final cost = _cost.text.trim().isEmpty ? null : _parse(_cost);
    final odometer = _odometer.text.trim().isEmpty ? null : int.tryParse(_odometer.text.trim().replaceAll('.', ''));
    final valid = litres != null && litres > 0 && litres <= 500 && (_cost.text.trim().isEmpty || (cost != null && cost >= 0 && cost <= 10000)) &&
        (_odometer.text.trim().isEmpty || (odometer != null && odometer >= 0));
    if (!valid) return setState(() => _error = _electric ? l.chargeInvalid : l.refuelInvalid);
    Navigator.pop(context, {
      'day': _day(_date),
      'litres': litres,
      'cost': cost,
      'odometerKm': odometer,
      'full': _full,
      'place': _electric ? _place : null,
      'note': _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final litres = _parse(_litres);
    final cost = _parse(_cost);
    final price = litres == null || litres <= 0 || cost == null || cost <= 0 ? null : cost / litres;
    final energy = widget.energy;
    return AlertDialog(
      title: Text(widget.refuel == null ? (_electric ? l.addCharge : l.addRefuel) : (_electric ? l.editCharge : l.editRefuel)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(formatDay(_date)),
            TextButton.icon(
              key: const Key('refuelDate'),
              icon: const Icon(Icons.event),
              label: Text(l.priceDate),
              onPressed: () async {
                final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now());
                if (picked != null) setState(() => _date = picked);
              },
            ),
          ]),
          TextField(
            key: const Key('refuelLitres'),
            controller: _litres,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: _electric ? l.chargeEnergy : l.refuelLitres, suffixText: energy, errorText: _error),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const Key('refuelCost'),
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l.refuelCost,
              suffixText: '€',
              helperText: price == null ? null : '${formatEuro(price, digits: 3)}/$energy',
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const Key('refuelOdometer'),
            controller: _odometer,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.refuelOdometer, suffixText: 'km', helperText: l.refuelOdometerHint),
          ),
          if (_electric) ...[
            Text(l.chargePlace, style: Theme.of(context).textTheme.labelLarge),
            SegmentedButton<String?>(
              key: const Key('chargePlace'),
              segments: [
                ButtonSegment(value: 'home', icon: const Icon(Icons.home), label: Text(l.chargeHome)),
                ButtonSegment(value: 'public', icon: const Icon(Icons.ev_station), label: Text(l.chargePublic)),
                ButtonSegment(value: null, label: Text(l.chargePlaceUnset)),
              ],
              selected: {_place},
              onSelectionChanged: (selection) => setState(() => _place = selection.first),
            ),
          ],
          SwitchListTile(
            key: const Key('refuelFull'),
            contentPadding: EdgeInsets.zero,
            title: Text(_electric ? l.chargeFull : l.refuelFull),
            subtitle: Text(_electric ? l.chargeFullHint : l.refuelFullHint),
            value: _full,
            onChanged: (value) => setState(() => _full = value),
          ),
          TextField(
            key: const Key('refuelNote'),
            controller: _note,
            maxLength: 200,
            decoration: InputDecoration(labelText: l.refuelNote),
          ),
        ]),
      ),
      actions: [
        if (widget.refuel != null)
          TextButton(key: const Key('refuelDelete'), onPressed: () => Navigator.pop(context, _delete), child: Text(l.delete)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('refuelSave'), onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}

