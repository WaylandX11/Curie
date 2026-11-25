import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/app_info.dart';
import '../models/settings.dart';
import '../services/apps.dart';
import '../services/store.dart';

/// Выбор приложений для раздельного туннелирования.
class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({super.key, required this.mode});

  final RoutingMode mode;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  List<AppInfo> _apps = const [];
  Set<String> _selected = {};
  bool _loading = true;
  bool _showSystem = false;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = Store.instance.state.value.settings;
    _selected = {...settings.selectedApps};
    _load();
  }

  Future<void> _load() async {
    try {
      final apps = await Apps.list();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<AppInfo> get _visible {
    final query = _query.toLowerCase();
    return _apps.where((app) {
      if (!_showSystem && app.system) return false;
      if (query.isEmpty) return true;
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _save(Set<String> packages) async {
    await Store.instance.update((state) {
      final settings = state.settings;
      return state.copyWith(
        settings: widget.mode == RoutingMode.onlySelected
            ? settings.copyWith(allowedApps: packages.toList()..sort())
            : settings.copyWith(bypassedApps: packages.toList()..sort()),
      );
    });
  }

  Future<void> _toggle(String package, bool value) async {
    final next = {..._selected};
    if (value) {
      next.add(package);
    } else {
      next.remove(package);
    }
    setState(() => _selected = next);
    await _save(next);
  }

  Future<void> _setAll(bool value) async {
    final next = {..._selected};
    for (final app in _visible) {
      if (value) {
        next.add(app.packageName);
      } else {
        next.remove(app.packageName);
      }
    }
    setState(() => _selected = next);
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('chooseApps')),
        actions: [
          IconButton(
            tooltip: l10n.tr('selectAll'),
            icon: const Icon(Icons.select_all),
            onPressed: _loading ? null : () => _setAll(true),
          ),
          IconButton(
            tooltip: l10n.tr('clearAll'),
            icon: const Icon(Icons.deselect),
            onPressed: _loading ? null : () => _setAll(false),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: l10n.tr('appsSearch'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            SwitchListTile(
              title: Text(l10n.tr('showSystemApps')),
              value: _showSystem,
              onChanged: (value) => setState(() => _showSystem = value),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.fmt('appsSelected', {'count': _selected.length}),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(l10n.tr('appsLoading')),
                        ],
                      ),
                    );
                  }
                  if (_error != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l10n.fmt('genericError', {'error': _error!})),
                      ),
                    );
                  }
                  if (visible.isEmpty) {
                    return Center(child: Text(l10n.tr('appsEmpty')));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final app = visible[index];
                      return CheckboxListTile(
                        value: _selected.contains(app.packageName),
                        onChanged: (value) => _toggle(app.packageName, value ?? false),
                        title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          app.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        secondary: _AppIcon(
                          key: ValueKey(app.packageName),
                          package: app.packageName,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Иконка строки списка. Грузится при появлении в кадре и кешируется в [Apps],
/// чтобы прокрутка не дёргала платформу повторно.
class _AppIcon extends StatefulWidget {
  const _AppIcon({super.key, required this.package});

  final String package;

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.package != widget.package) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await Apps.icon(widget.package);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return SizedBox(
      width: 40,
      height: 40,
      child: bytes == null || bytes.isEmpty
          ? const Icon(Icons.android)
          : Image.memory(bytes, gaplessPlayback: true),
    );
  }
}
