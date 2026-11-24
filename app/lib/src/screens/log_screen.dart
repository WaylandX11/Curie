import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../services/app_log.dart';
import '../widgets/common.dart';

/// Журнал событий: подключения, ошибки ядра, обновления подписок.
/// Нужен, чтобы показать проблему без отладчика и adb.
class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('log')),
        actions: [
          IconButton(
            tooltip: l10n.tr('copyLog'),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => ClipboardCopy.copy(context, AppLog.dump()),
          ),
          IconButton(
            tooltip: l10n.tr('delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: AppLog.clear,
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<LogEntry>>(
          valueListenable: AppLog.entries,
          builder: (context, entries, _) {
            if (entries.isEmpty) {
              return Center(child: Text(l10n.tr('logEmpty')));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[entries.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SelectableText(
                    entry.format(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: entry.message.contains('ошибка')
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
