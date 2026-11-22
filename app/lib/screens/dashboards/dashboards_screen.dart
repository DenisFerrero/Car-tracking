import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../device/maintenance_screen.dart' show confirmDelete;
import 'catalog.dart';
import 'sharing.dart';
import 'widget_card.dart';
import 'widget_editor.dart';

final dashboardsProvider = FutureProvider.autoDispose<List<Dashboard>>((ref) async {
  final list = await ref.watch(apiProvider).get('/api/dashboards') as List;
  return [for (final item in list.cast<Map<String, dynamic>>()) Dashboard.fromJson(item)];
});

/// Custom dashboards of the user: widgets of the catalog on a grid that follows the
/// screen. Edit mode: widgets added, changed, duplicated, removed, dragged in order;
/// saved together. The current one opens first (and in the analysis of the vehicles);
/// layouts are sent to friends and received from them.
class DashboardsScreen extends ConsumerStatefulWidget {
  const DashboardsScreen({super.key});

  @override
  ConsumerState<DashboardsScreen> createState() => _DashboardsScreenState();
}

class _DashboardsScreenState extends ConsumerState<DashboardsScreen> {
  int? _selected;

  /// Widgets being edited: null outside the edit mode
  List<DashWidget>? _editing;
  bool _dirty = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName(String title, String initial) {
    final l = context.l10n;
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('dashboardName'),
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(labelText: l.dashboardName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
          FilledButton(
            key: const Key('dashboardNameOk'),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _create(String kind) async {
    final l = context.l10n;
    final name = await _askName(l.dashboardNew, switch (kind) {
      'overview' => l.templateOverview,
      'diagnostics' => l.templateDiagnostics,
      _ => l.navDashboards,
    });
    if (name == null) return;
    await _run(() async {
      final created = await ref.read(apiProvider).post('/api/dashboards', {
        'name': name,
        'layout': Dashboard.layout('30d', template(kind)),
      }) as Map<String, dynamic>;
      _selected = created['id'] as int;
      ref.invalidate(dashboardsProvider);
    });
  }

  Future<void> _save(Dashboard dashboard, {String? name, Object? period, List<DashWidget>? widgets}) => _run(() async {
        await ref.read(apiProvider).put('/api/dashboards/${dashboard.id}', {
          'name': name ?? dashboard.name,
          'layout': Dashboard.layout(period ?? dashboard.period, widgets ?? dashboard.widgets),
        });
        ref.invalidate(dashboardsProvider);
      });

  Future<void> _newDashboard() async {
    final l = context.l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(l.dashboardNew, style: Theme.of(context).textTheme.titleMedium)),
          for (final (key, label, icon) in [
            ('blank', l.templateBlank, Icons.dashboard_customize_outlined),
            ('overview', l.templateOverview, Icons.directions_car),
            ('diagnostics', l.templateDiagnostics, Icons.monitor_heart_outlined),
          ])
            ListTile(key: Key('template_$key'), leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(context, key)),
        ]),
      ),
    );
    if (choice != null) await _create(choice);
  }

  Future<void> _menu(Dashboard dashboard, String action) async {
    final l = context.l10n;
    if (action == 'rename') {
      final name = await _askName(l.dashboardRename, dashboard.name);
      if (name != null) await _save(dashboard, name: name);
      return;
    }
    if (action == 'share') return shareDashboard(context, ref, dashboard);
    if (action == 'current') {
      return _run(() async {
        await ref.read(apiProvider).put('/api/dashboards/${dashboard.id}/current', {'current': !dashboard.current});
        ref.invalidate(dashboardsProvider);
        if (mounted) showMessage(context, dashboard.current ? l.dashboardCurrentUnset : l.dashboardCurrentSet(dashboard.name));
      });
    }
    if (!await confirmDelete(context, l.dashboardDeleteBody(dashboard.name))) return;
    await _run(() async {
      await ref.read(apiProvider).delete('/api/dashboards/${dashboard.id}');
      _selected = null;
      ref.invalidate(dashboardsProvider);
    });
  }

  Future<void> _pickPeriod(Dashboard dashboard, String choice) async {
    if (choice != 'custom') return _save(dashboard, period: choice);
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (range == null || !mounted) return;
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await _save(dashboard, period: {'from': iso(range.start), 'to': iso(range.end)});
  }

  /// A dashboard created from a layout received: shown at once
  void _added(int id) {
    setState(() => _selected = id);
    ref.invalidate(dashboardsProvider);
  }

  // --- Edit mode
  void _change(void Function(List<DashWidget> widgets) change) => setState(() {
        change(_editing!);
        _dirty = true;
      });

  Future<void> _editWidget(Dashboard dashboard, [int? index]) async {
    final changed = await editWidget(context, dashboard.period, index == null ? null : _editing![index]);
    if (changed == null || !mounted) return;
    _change((widgets) {
      if (index == null) {
        widgets.add(changed);
      } else {
        widgets[index] = changed;
      }
    });
  }

  Future<bool> _leaveEditing() async {
    if (!_dirty) return true;
    final l = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.dashboardDiscard),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
              FilledButton(key: const Key('discard'), onPressed: () => Navigator.pop(context, true), child: Text(l.discard)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _cancelEditing() async {
    if (await _leaveEditing() && mounted) setState(() => _editing = null);
  }

  Future<void> _saveEditing(Dashboard dashboard) async {
    await _save(dashboard, widgets: _editing);
    if (!mounted) return;
    setState(() {
      _editing = null;
      _dirty = false;
    });
    showMessage(context, context.l10n.dashboardSaved);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dashboards = ref.watch(dashboardsProvider);
    final list = dashboards.value ?? const <Dashboard>[];
    final dashboard =
        list.where((d) => d.id == _selected).firstOrNull ?? list.where((d) => d.current).firstOrNull ?? list.firstOrNull;

    return PopScope(
      canPop: _editing == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelEditing();
      },
      child: Scaffold(
        appBar: _editing != null && dashboard != null ? _editBar(dashboard) : _viewBar(list, dashboard),
        floatingActionButton: _editing != null && dashboard != null
            ? FloatingActionButton.extended(
                key: const Key('widgetAdd'),
                onPressed: () => _editWidget(dashboard),
                icon: const Icon(Icons.add),
                label: Text(l.widgetAdd),
              )
            : null,
        body: dashboards.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(errorText(l, error))),
          data: (_) => dashboard == null
              ? _empty()
              : _editing != null
                  ? _editList(dashboard)
                  : _view(dashboard),
        ),
      ),
    );
  }

  PreferredSizeWidget _viewBar(List<Dashboard> list, Dashboard? dashboard) {
    final l = context.l10n;
    return AppBar(
      title: list.length > 1
          ? PopupMenuButton<int>(
              key: const Key('dashboardPicker'),
              initialValue: dashboard!.id,
              onSelected: (id) => setState(() => _selected = id),
              itemBuilder: (_) => [
                for (final d in list)
                  PopupMenuItem(
                    value: d.id,
                    child: Row(children: [
                      Flexible(child: Text(d.name, overflow: TextOverflow.ellipsis)),
                      if (d.current) ...[const SizedBox(width: 8), const _CurrentIcon()],
                    ]),
                  ),
              ],
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(dashboard.name, overflow: TextOverflow.ellipsis)),
                if (dashboard.current) ...[const SizedBox(width: 8), const _CurrentIcon()],
                const Icon(Icons.arrow_drop_down),
              ]),
            )
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(dashboard?.name ?? l.navDashboards, overflow: TextOverflow.ellipsis)),
              if (dashboard?.current == true) ...[const SizedBox(width: 8), const _CurrentIcon()],
            ]),
      actions: [
        if (dashboard != null) ...[
          PopupMenuButton<String>(
            key: const Key('dashboardPeriod'),
            tooltip: l.dashboardPeriod,
            icon: const Icon(Icons.date_range),
            onSelected: (choice) => _pickPeriod(dashboard, choice),
            itemBuilder: (_) => [
              for (final p in periodPresets) CheckedPopupMenuItem(value: p, checked: dashboard.period == p, child: Text(periodLabel(l, p))),
              CheckedPopupMenuItem(
                value: 'custom',
                checked: dashboard.period is Map,
                child: Text(dashboard.period is Map ? periodLabel(l, dashboard.period) : l.periodCustom),
              ),
            ],
          ),
          IconButton(
            key: const Key('dashboardEdit'),
            tooltip: l.dashboardEdit,
            icon: const Icon(Icons.edit),
            onPressed: _busy ? null : () => setState(() {
              _editing = [...dashboard.widgets];
              _dirty = false;
            }),
          ),
          IconButton(key: const Key('dashboardNew'), tooltip: l.dashboardNew, icon: const Icon(Icons.add), onPressed: _newDashboard),
          PopupMenuButton<String>(
            key: const Key('dashboardMenu'),
            onSelected: (action) => _menu(dashboard, action),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'current',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(dashboard.current ? Icons.star : Icons.star_outline),
                  title: Text(dashboard.current ? l.dashboardUnsetCurrent : l.dashboardSetCurrent),
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.share), title: Text(l.dashboardShare)),
              ),
              PopupMenuItem(
                value: 'rename',
                child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.drive_file_rename_outline), title: Text(l.dashboardRename)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_outline), title: Text(l.dashboardDelete)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  PreferredSizeWidget _editBar(Dashboard dashboard) {
    final l = context.l10n;
    return AppBar(
      leading: IconButton(key: const Key('editCancel'), icon: const Icon(Icons.close), onPressed: _cancelEditing),
      title: Text('${l.dashboardEdit} · ${dashboard.name}'),
      actions: [
        TextButton(key: const Key('editSave'), onPressed: _busy ? null : () => _saveEditing(dashboard), child: Text(l.save)),
      ],
    );
  }

  Widget _empty() {
    final l = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ReceivedDashboards(onAdded: _added),
            const SizedBox(height: 16),
            const Icon(Icons.dashboard_customize_outlined, size: 48),
            const SizedBox(height: 12),
            Text(l.dashboardEmpty, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('createOverview'),
              onPressed: _busy ? null : () => _create('overview'),
              icon: const Icon(Icons.directions_car),
              label: Text(l.templateOverview),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('createDiagnostics'),
              onPressed: _busy ? null : () => _create('diagnostics'),
              icon: const Icon(Icons.monitor_heart_outlined),
              label: Text(l.templateDiagnostics),
            ),
            const SizedBox(height: 8),
            TextButton(key: const Key('createBlank'), onPressed: _busy ? null : () => _create('blank'), child: Text(l.templateBlank)),
          ]),
        ),
      ),
    );
  }

  Widget _view(Dashboard dashboard) {
    final l = context.l10n;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardDataProvider);
        ref.invalidate(devicesProvider);
        ref.invalidate(sharedDashboardsProvider);
      },
      child: ListView(padding: const EdgeInsets.all(8), children: [
        ReceivedDashboards(onAdded: _added),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(periodLabel(l, dashboard.period), style: Theme.of(context).textTheme.bodySmall),
        ),
        if (dashboard.widgets.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l.dashboardNoWidgets, textAlign: TextAlign.center)))
        else
          DashboardGrid(period: dashboard.period, widgets: dashboard.widgets),
      ]),
    );
  }

  Widget _editList(Dashboard dashboard) {
    final l = context.l10n;
    final widgets = _editing!;
    return ReorderableListView.builder(
      padding: readable(context, const EdgeInsets.fromLTRB(8, 8, 8, 88)),
      buildDefaultDragHandles: false,
      itemCount: widgets.length,
      onReorderItem: (from, to) => _change((list) => list.insert(to, list.removeAt(from))),
      itemBuilder: (context, index) {
        final w = widgets[index];
        return Card(
          key: ValueKey(w.id),
          child: ListTile(
            key: Key('edit_${w.id}'),
            leading: Icon(w.info.icon),
            title: Text(w.titleOf(l)),
            subtitle: Text('${viewLabel(l, w.view)} · ${l.widgetSize(w.width, w.height)}'),
            onTap: () => _editWidget(dashboard, index),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              PopupMenuButton<String>(
                key: Key('menu_${w.id}'),
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      _editWidget(dashboard, index);
                    case 'duplicate':
                      _change((list) => list.insert(index + 1, w.copyWith(id: newWidgetId())));
                    default:
                      _change((list) => list.removeAt(index));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l.widgetEdit)),
                  PopupMenuItem(value: 'duplicate', child: Text(l.widgetDuplicate)),
                  PopupMenuItem(value: 'remove', child: Text(l.widgetRemove)),
                ],
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_handle, key: Key('drag_${w.id}'))),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Mark of the current dashboard
class _CurrentIcon extends StatelessWidget {
  const _CurrentIcon();

  @override
  Widget build(BuildContext context) =>
      Tooltip(message: context.l10n.dashboardCurrent, child: Icon(Icons.star, size: 18, color: Theme.of(context).colorScheme.secondary));
}
