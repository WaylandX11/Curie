import 'dart:async';

import 'app_log.dart';
import 'core_log.dart';
import 'geo_assets.dart';
import 'store.dart';
import 'subscriptions.dart';
import 'update_checker.dart';
import 'vpn.dart';

/// Периодические фоновые проверки в рамках живого процесса.
///
/// Без WorkManager: проверки просыпаются по таймеру и сразу после возврата в
/// приложение. Туннель при этом поднимается нативным сервисом, поэтому запросы
/// идут через него даже при выключенном экране.
class CurieSchedulers {
  static const Duration _subscriptionCadence = Duration(minutes: 15);
  static const Duration _updateCadence = Duration(hours: 1);

  static Timer? _subscriptionTimer;
  static Timer? _updateTimer;
  static bool _started = false;
  static bool _subscriptionsBusy = false;
  static bool _updatesBusy = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    UpdateChecker.restorePending();
    await _pruneCoreLogIfIdle();
    await GeoAssets.refreshStatus();
    unawaited(GeoAssets.noticeStoredSubscriptions());

    // Первый проход после первого кадра: сеть не должна задерживать запуск UI.
    Timer(const Duration(seconds: 2), () {
      unawaited(checkSubscriptions());
      unawaited(checkUpdates());
      unawaited(GeoAssets.maybeAutoUpdate());
    });
    _subscriptionTimer ??= Timer.periodic(
      _subscriptionCadence,
      (_) => unawaited(checkSubscriptions()),
    );
    _updateTimer ??= Timer.periodic(_updateCadence, (_) {
      unawaited(checkUpdates());
      unawaited(GeoAssets.maybeAutoUpdate());
    });
  }

  /// Сразу после foreground: догоняем то, что прошло, пока приложение было в фоне.
  static Future<void> resume() async {
    if (!_started) return;
    await Vpn.refresh();
    await _pruneCoreLogIfIdle();
    await Future.wait([
      checkSubscriptions(),
      checkUpdates(),
      GeoAssets.maybeAutoUpdate(),
    ]);
  }

  /// Перезаписывать журнал можно только когда ядро не держит файл открытым.
  static Future<void> _pruneCoreLogIfIdle() async {
    if (Vpn.status.value != VpnStatus.disconnected) return;
    try {
      await CoreLog.prune(
        retention: Duration(
          hours: Store.instance.state.value.settings.xrayLogRetentionHours,
        ),
      );
    } on Object {
      // Журнал — необязательная деталь: сбой файла не мешает проверкам.
    }
  }

  static Future<void> checkSubscriptions({bool force = false}) async {
    if (_subscriptionsBusy) return;
    _subscriptionsBusy = true;
    try {
      final settings = Store.instance.state.value.settings;
      if (!force && !settings.autoUpdateSubscriptions) return;
      final due = Store.instance.state.value.subscriptions
          .where(
            (s) => s.isStale(userHours: settings.subscriptionUpdateHours),
          )
          .length;
      if (due == 0) return;
      AppLog.add(
        'subscription',
        'автообновление: $due из '
            '${Store.instance.state.value.subscriptions.length} подписок',
      );
      await Subscriptions.refreshAll(
        onlyStale: true,
        intervalHours: settings.subscriptionUpdateHours,
      );
    } finally {
      _subscriptionsBusy = false;
    }
  }

  static Future<void> checkUpdates({bool force = false}) async {
    if (_updatesBusy) return;
    _updatesBusy = true;
    try {
      await UpdateChecker.check(force: force, showCoreDialog: true);
    } finally {
      _updatesBusy = false;
    }
  }
}
