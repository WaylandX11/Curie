import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../services/app_log.dart';
import '../services/core_log.dart';
import '../services/store.dart';
import '../services/vpn.dart';
import '../widgets/common.dart';

/// Журнал приложения и отдельно журнал ядра Xray.
/// Оба жизненно важны, чтобы разобраться в проблеме без adb.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

enum _LogSource { app, core }

class _LogScreenState extends State<LogScreen> {
  _LogSource _source = _LogSource.app;
  List<String> _coreLines = const [];

  @override
  void initState() {
    super.initState();
    _loadCore();
  }

  Duration get _retention => Duration(
        hours: Store.instance.state.value.settings.xrayLogRetentionHours,
      );

  Future<void> _loadCore() async {
    final lines = await CoreLog.read(retention: _retention);
    if (!mounted) return;
    setState(() => _coreLines = lines);
  }

  Future<void> _copy() async {
    if (_source == _LogSource.app) {
      await ClipboardCopy.copy(context, AppLog.dump());
      return;
    }
    final dump = await CoreLog.dump(retention: _retention);
    if (!mounted) return;
    await ClipboardCopy.copy(context, dump);
  }

  Future<void> _delete() async {
    if (_source == _LogSource.app) {
      AppLog.clear();
      return;
    }
    // Ядро держит файл открытым: усечение во время работы даст дыру из NUL,
    // а не чистый журнал. Просим сначала отключиться.
    final status = Vpn.status.value;
    if (status == VpnStatus.connected ||
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting) {
      if (mounted) {
        showMessage(context, AppLocalizations.of(context).tr('logClearDisconnect'));
      }
      return;
    }
    await CoreLog.clear();
    await _loadCore();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('log')),
        actions: [
          if (_source == _LogSource.core)
            IconButton(
              tooltip: l10n.tr('refreshLog'),
              icon: const Icon(Icons.refresh),
              onPressed: _loadCore,
            ),
          IconButton(
            tooltip: l10n.tr('copyLog'),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: l10n.tr('delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<_LogSource>(
                segments: [
                  ButtonSegment(
                    value: _LogSource.app,
                    label: Text(l10n.tr('logApp')),
                    icon: const Icon(Icons.layers_outlined),
                  ),
                  ButtonSegment(
                    value: _LogSource.core,
                    label: Text(l10n.tr('logCore')),
                    icon: const Icon(Icons.memory),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (value) {
                  setState(() => _source = value.first);
                  if (_source == _LogSource.core) unawaited(_loadCore());
                },
              ),
            ),
            Expanded(
              child: _source == _LogSource.app
                  ? ValueListenableBuilder<List<LogEntry>>(
                      valueListenable: AppLog.entries,
                      builder: (context, entries, _) {
                        if (entries.isEmpty) return _empty(l10n, theme);
                        return _list(
                          entries
                              .map((entry) => MapEntry(
                                    entry.format(),
                                    _isError(entry.message),
                                  ))
                              .toList()
                              .reversed
                              .toList(),
                          theme,
                        );
                      },
                    )
                  : (_coreLines.isEmpty
                      ? _empty(l10n, theme)
                      : _list(
                          _coreLines.reversed
                              .map((line) => MapEntry(line, _isError(line)))
                              .toList(),
                          theme,
                        )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(AppLocalizations l10n, ThemeData theme) => Center(
        child: Text(
          l10n.tr('logEmpty'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _list(List<MapEntry<String, bool>> lines, ThemeData theme) =>
      ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: lines.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) => SelectableText(
          lines[index].key,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: lines[index].value ? theme.colorScheme.error : null,
          ),
        ),
      );

  bool _isError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('error') ||
        lower.contains('warning') ||
        lower.contains('ошибка');
  }
}
