import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/charts.dart';

final vehicleProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) async => await ref.watch(apiProvider).get('/api/devices/$id/vehicle') as Map<String, dynamic>,
);

/// Allowed values, as the backend checks them (consumption in the unit of the owner)
const consumptionRange = {'l_per_100km': (min: 1.0, max: 50.0), 'km_per_l': (min: 2.0, max: 100.0)};
const _priceRange = (min: 0.0, max: 10.0);
const _wearRange = (min: 0.0, max: 10.0);

const fuelTypes = ['petrol', 'diesel', 'lpg'];

String _text(Object? value) => value == null ? '' : NumberFormat('0.###', Intl.getCurrentLocale()).format(value as num);
double? _parse(TextEditingController controller) => double.tryParse(controller.text.trim().replaceAll(',', '.'));
String _day(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String fuelTypeLabel(AppLocalizations l, String? type) => switch (type) {
      'petrol' => l.fuelPetrol,
      'diesel' => l.fuelDiesel,
      'lpg' => l.fuelLpg,
      _ => l.fuelOther,
    };

/// One of the values over time: price of the fuel, consumption, wear
class _Rate {
  const _Rate(this.kind, this.icon, this.color);

  final String kind;
  final IconData icon;
  final Color color;

  String title(AppLocalizations l) => switch (kind) { 'price' => l.fuelPrices, 'consumption' => l.consumption, _ => l.wearPerKm };

  String unit(String fuelUnit) => switch (kind) {
        'price' => '€/l',
        'consumption' => fuelUnit == 'l_per_100km' ? 'l/100 km' : 'km/l',
        _ => '€/km',
      };

  ({double min, double max}) range(String fuelUnit) =>
      switch (kind) { 'price' => _priceRange, 'consumption' => consumptionRange[fuelUnit]!, _ => _wearRange };

  /// Stored in l/100 km, shown in the unit of the owner
  double shown(num value, String fuelUnit) =>
      kind == 'consumption' && fuelUnit == 'km_per_l' ? double.parse((100 / value).toStringAsFixed(1)) : value.toDouble();

  String format(num value, String fuelUnit) => switch (kind) {
        'price' => '${formatEuro(value, digits: 3)}/l',
        'wear' => '${formatEuro(value, digits: 3)}/km',
        _ => '${_text(shown(value, fuelUnit))} ${unit(fuelUnit)}',
      };
}

const _rates = [
  _Rate('price', Icons.local_gas_station, Colors.orange),
  _Rate('consumption', Icons.speed, Colors.blue),
  _Rate('wear', Icons.tire_repair, Colors.purple),
];

/// Costs of the trips: price of the fuel, consumption (l/100 km or km/l) and wear per km,
/// each with its history (each trip uses the values of its day). The price can follow the
/// weekly national average (MASE); no public source of the wear (ACI tables): the owner
/// looks it up and enters it.
class CostsScreen extends ConsumerWidget {
  const CostsScreen({super.key, required this.deviceId});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.tripCosts)),
      body: ref.watch(vehicleProvider(deviceId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(errorText(l, error))),
            data: (data) => _CostsForm(deviceId: deviceId, profile: data),
          ),
    );
  }
}

class _CostsForm extends ConsumerStatefulWidget {
  const _CostsForm({required this.deviceId, required this.profile});

  final int deviceId;
  final Map<String, dynamic> profile;

  @override
  ConsumerState<_CostsForm> createState() => _CostsFormState();
}

class _CostsFormState extends ConsumerState<_CostsForm> {
  late Map<String, dynamic> _profile = widget.profile;
  late String _unit = _profile['fuelUnit'] as String;
  late String? _fuelType = _profile['fuelType'] as String?;
  late bool _auto = _profile['fuelPriceAuto'] as bool;
  late final _model = TextEditingController(text: _profile['model'] as String);
  bool _busy = false;

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  /// A request that returns the profile: shown, with a message
  Future<void> _send(Future<Object?> Function() request, String done) async {
    setState(() => _busy = true);
    try {
      final profile = await request() as Map<String, dynamic>;
      setState(() => _profile = profile);
      if (mounted) showMessage(context, done);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _send(
        () => ref.read(apiProvider).put('/api/devices/${widget.deviceId}/vehicle', {
          'model': _model.text.trim(),
          'fuelUnit': _unit,
          'fuelType': _fuelType,
          'fuelPriceAuto': _fuelType != null && _auto,
        }),
        context.l10n.costsSaved,
      );

  Future<void> _addRate(_Rate rate, {double? value}) async {
    final entry = await showDialog<({String validFrom, double value})>(
      context: context,
      builder: (_) => _RateDialog(title: rate.title(context.l10n), unit: rate.unit(_unit), range: rate.range(_unit), initial: value),
    );
    if (entry == null || !mounted) return;
    await _send(
      () => ref.read(apiProvider).post('/api/devices/${widget.deviceId}/rates',
          {'kind': rate.kind, 'validFrom': entry.validFrom, 'value': entry.value, if (rate.kind == 'consumption') 'unit': _unit}),
      context.l10n.costsSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final costPerKm = _profile['costPerKm'] as num?;
    final current = _profile['current'] as Map<String, dynamic>;
    final average = _profile['average'] as Map<String, dynamic>?;
    final values = (_profile['rates'] as Map<String, dynamic>).map((kind, list) => MapEntry(kind, (list as List).cast<Map<String, dynamic>>()));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        key: const Key('costPerKm'),
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.euro),
          title: Text(costPerKm == null ? l.costPerKmUnset : l.costPerKm(formatEuro(costPerKm, digits: 3))),
          subtitle: Text(l.costsIntro),
        ),
      ),
      const SizedBox(height: 16),

      // The vehicle: model, fuel (for the national average), unit of the consumption
      TextField(
        key: const Key('vehicleModel'),
        controller: _model,
        maxLength: 60,
        decoration: InputDecoration(labelText: l.vehicleModel, hintText: l.vehicleModelHint),
      ),
      DropdownButtonFormField<String?>(
        key: const Key('fuelType'),
        initialValue: _fuelType,
        decoration: InputDecoration(labelText: l.fuelType),
        items: [
          for (final type in [...fuelTypes, null]) DropdownMenuItem(value: type, child: Text(fuelTypeLabel(l, type))),
        ],
        onChanged: (value) => setState(() => _fuelType = value),
      ),
      const SizedBox(height: 12),
      Text(l.consumptionUnit, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        key: const Key('fuelUnit'),
        segments: const [
          ButtonSegment(value: 'l_per_100km', label: Text('l/100 km')),
          ButtonSegment(value: 'km_per_l', label: Text('km/l')),
        ],
        selected: {_unit},
        onSelectionChanged: (selection) => setState(() => _unit = selection.first),
      ),
      SwitchListTile(
        key: const Key('fuelPriceAuto'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.fuelPriceAuto),
        subtitle: Text(_fuelType == null ? l.fuelPriceAutoNeedsType : l.fuelPriceAutoHint),
        value: _fuelType != null && _auto,
        onChanged: _fuelType == null ? null : (value) => setState(() => _auto = value),
      ),
      FilledButton(key: const Key('vehicleSave'), onPressed: _busy ? null : _save, child: Text(l.save)),
      if (average != null)
        Card(
          key: const Key('average'),
          margin: const EdgeInsets.only(top: 16),
          child: ListTile(
            leading: const Icon(Icons.public),
            title: Text(l.nationalAverage(fuelTypeLabel(l, _profile['fuelType'] as String?), formatEuro(average['price'] as num, digits: 3))),
            subtitle: Text(l.nationalAverageWeek(formatDay(DateTime.parse(average['week'] as String)))),
            trailing: TextButton(
              key: const Key('useAverage'),
              onPressed: _busy ? null : () => _addRate(_rates.first, value: (average['price'] as num).toDouble()),
              child: Text(l.useAverage),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text(l.ratesHint, style: theme.textTheme.bodySmall),

      for (final rate in _rates) ...[
        const SizedBox(height: 16),
        Row(children: [
          Icon(rate.icon, color: rate.color),
          const SizedBox(width: 8),
          Expanded(child: Text(rate.title(l), style: theme.textTheme.titleMedium)),
          TextButton.icon(
            key: Key('add_${rate.kind}'),
            icon: const Icon(Icons.add),
            label: Text(l.addValue),
            onPressed: _busy ? null : () => _addRate(rate),
          ),
        ]),
        Text(current[rate.kind] == null ? l.rateUnset : l.rateNow(rate.format(current[rate.kind] as num, _unit))),
        if (rate.kind == 'wear')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('searchAci'),
              icon: const Icon(Icons.search),
              label: Text(l.searchAci),
              onPressed: () => openLink(
                context,
                ref,
                Uri.https('www.google.com', '/search', {'q': 'ACI costi chilometrici ${_model.text.trim()}'.trim()}),
              ),
            ),
          ),
        if (values[rate.kind]!.length > 1) _RateChart(rate: rate, values: values[rate.kind]!, unit: _unit),
        for (final item in values[rate.kind]!)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(rate.format(item['value'] as num, _unit)),
            subtitle: Text(l.validFrom(formatDay(DateTime.parse(item['validFrom'] as String)))),
            trailing: IconButton(
              key: Key('delete_${rate.kind}_${item['validFrom']}'),
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () => _send(
                      () => ref.read(apiProvider).delete('/api/devices/${widget.deviceId}/rates/${rate.kind}/${item['validFrom']}'),
                      l.costsSaved),
            ),
          ),
      ],
    ]);
  }
}

/// A value over time, up to today
class _RateChart extends StatelessWidget {
  const _RateChart({required this.rate, required this.values, required this.unit});

  final _Rate rate;
  final List<Map<String, dynamic>> values;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final oldest = values.reversed.toList();
    final now = DateTime.now();
    final last = DateTime.parse(oldest.last['validFrom'] as String);
    double y(Map<String, dynamic> item) => rate.shown(item['value'] as num, unit);
    final spots = [
      for (final item in oldest) FlSpot(DateTime.parse(item['validFrom'] as String).millisecondsSinceEpoch.toDouble(), y(item)),
      if (last.isBefore(now)) FlSpot(now.millisecondsSinceEpoch.toDouble(), y(oldest.last)),
    ];
    return ChartCard(
      title: context.l10n.rateTrend,
      height: 160,
      child: TimeChart(
        from: DateTime.parse(oldest.first['validFrom'] as String),
        to: last.isBefore(now) ? now : last,
        unit: ' ${rate.unit(unit)}',
        series: [Series(rate.title(context.l10n), rate.color, spots)],
      ),
    );
  }
}

/// New value from a day (default today)
class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.title, required this.unit, required this.range, this.initial});

  final String title;
  final String unit;
  final ({double min, double max}) range;
  final double? initial;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late final _value = TextEditingController(text: _text(widget.initial));
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _parse(_value);
    final range = widget.range;
    // The price must be above 0, the other values can be 0
    final valid = value != null && value <= range.max && (widget.unit == '€/l' ? value > range.min : value >= range.min);
    if (!valid) return setState(() => _error = context.l10n.valueRange(_text(range.min), _text(range.max)));
    Navigator.pop(context, (validFrom: _day(_date), value: value));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const Key('rateValue'),
          controller: _value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: widget.title, suffixText: widget.unit, errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(l.validFrom(formatDay(_date))),
          TextButton.icon(
            key: const Key('rateDate'),
            icon: const Icon(Icons.event),
            label: Text(l.priceDate),
            onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now());
              if (picked != null) setState(() => _date = picked);
            },
          ),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('rateSave'), onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}
