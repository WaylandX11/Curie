import 'traffic.dart';
import 'vpn.dart';

/// Держит опрос метрик независимо от того, открыт ли экран.
///
/// Раньше старт опроса жил в `HomeScreen`: после долгого фона приложение
/// возвращалось с уже подключённым туннелем, но с нулевым портом в UI, и
/// индикатор скорости застывал. Теперь порт приходит из нативного сервиса.
class TunnelMonitor {
  static bool _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    Vpn.status.addListener(_onStatus);
    _onStatus();
  }

  static void _onStatus() {
    if (Vpn.status.value != VpnStatus.connected) {
      Traffic.stop();
      return;
    }
    if (Vpn.isRustActive) {
      // Rust не поднимает HTTP-метрики: Traffic берёт счётчики из MethodChannel,
      // порт здесь нужен только как ключ опроса.
      Traffic.start(
        Vpn.metricsPort.value > 0 ? Vpn.metricsPort.value : Traffic.defaultPort,
      );
    } else if (Vpn.metricsPort.value > 0) {
      Traffic.start(Vpn.metricsPort.value);
    } else {
      Traffic.stop();
    }
  }
}
