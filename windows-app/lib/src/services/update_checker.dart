import 'dart:convert';

import '../generated/build_info.dart';
import '../generated/core_info.dart';
import 'app_log.dart';
import 'store.dart';
import 'update.dart';
import 'update_notifier.dart';
import 'vpn.dart';

enum UpdateCheckResult { skipped, upToDate, available, error }

/// Раз в сутки проверяет GitHub и решает, что показать пользователю.
///
/// Новая версия Xray — отдельный диалог один раз на версию ядра. Просто новая
/// версия приложения — только строка-баннер на главной.
class UpdateChecker {
  static const Duration _daily = Duration(hours: 24);

  static Future<UpdateCheckResult> check({
    bool force = false,
    bool showCoreDialog = false,
  }) async {
    final settings = Store.instance.state.value.settings;
    final now = DateTime.now();
    final last = settings.lastUpdateCheckAt;
    if (!force && last != null && now.difference(last) < _daily) {
      return UpdateCheckResult.skipped;
    }

    try {
      final release = await GithubUpdate.fetchLatest(
        proxyPort: Vpn.tunnelProxyPort,
      );
      if (release == null || release.version.isEmpty) {
        return UpdateCheckResult.error;
      }

      final isNewer = GithubUpdate.isNewer(release.version, buildStamp);
      final coreUpdated = isNewer &&
          release.coreVersion != null &&
          GithubUpdate.isNewerCore(release.coreVersion!, libXrayVersion);

      if (!isNewer) {
        await Store.instance.update((state) => state.copyWith(
              settings: state.settings.copyWith(
                lastUpdateCheckAt: now,
                clearPendingUpdate: true,
              ),
            ));
        AppLog.add('update', 'актуальная версия: ${release.version}');
        return UpdateCheckResult.upToDate;
      }

      final firstCoreNotice = coreUpdated &&
          settings.lastNotifiedCoreVersion != release.coreVersion;
      // Отметку ставим и для ручной проверки: её диалог тоже показывает
      // сообщение про ядро, поэтому фоновый диалог не должен повториться.
      await Store.instance.update((state) => state.copyWith(
            settings: state.settings.copyWith(
              lastUpdateCheckAt: now,
              pendingUpdate: jsonEncode(_encode(release)),
              lastNotifiedCoreVersion:
                  firstCoreNotice ? release.coreVersion : null,
            ),
          ));

      AppLog.add(
        'update',
        'доступна версия ${release.version}'
            '${coreUpdated ? ', Xray ${release.coreVersion}' : ''}',
      );
      UpdateNotifier.publish(
        UpdateNotice(release, coreUpdated: coreUpdated),
        showCoreDialog: showCoreDialog && firstCoreNotice,
      );
      return UpdateCheckResult.available;
    } on Object catch (e) {
      AppLog.add('update', 'ошибка проверки: $e');
      return UpdateCheckResult.error;
    }
  }

  /// Восстанавливаем баннер из зашифрованного состояния при запуске.
  static void restorePending() {
    final raw = Store.instance.state.value.settings.pendingUpdate;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final release = GithubRelease(
        version: (decoded['version'] as String?) ?? '',
        tag: (decoded['tag'] as String?) ?? '',
        htmlUrl: (decoded['htmlUrl'] as String?) ?? '',
        notes: (decoded['notes'] as String?) ?? '',
        downloadUrl: (decoded['downloadUrl'] as String?) ?? '',
        coreVersion: decoded['coreVersion'] as String?,
      );
      if (release.version.isEmpty) return;
      final coreUpdated = release.coreVersion != null &&
          GithubUpdate.isNewerCore(release.coreVersion!, libXrayVersion);
      UpdateNotifier.restore(UpdateNotice(release, coreUpdated: coreUpdated));
    } on Object {
      // Битая запись не должна мешать запуску — следующая проверка перезапишет.
    }
  }

  static Map<String, dynamic> _encode(GithubRelease release) => {
        'version': release.version,
        'tag': release.tag,
        'htmlUrl': release.htmlUrl,
        'notes': release.notes,
        'downloadUrl': release.downloadUrl,
        'coreVersion': release.coreVersion,
      };
}
