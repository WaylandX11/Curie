import 'dart:io';

import 'app_log.dart';

/// Результат активной проверки интернета через поднятый туннель.
class CheckResult {
  const CheckResult({
    required this.ok,
    this.ms,
    this.status,
    this.error,
  });

  final bool ok;
  final int? ms;
  final int? status;
  final String? error;
}

/// Приложение исключено из VPN (иначе ядро ушло бы в собственный TUN), поэтому
/// обычный HTTP-запрос из Dart идёт мимо туннеля и ничего не доказывает.
///
/// В конфиг Xray добавляется локальный HTTP-прокси на 127.0.0.1, маршрутизированный
/// через рабочий outbound. Запрос через него — честная проверка «туннель → сайт».
class ConnectionCheck {
  const ConnectionCheck();

  static const String probeUrl = 'https://cp.cloudflare.com/generate_204';
  static const Duration timeout = Duration(seconds: 8);

  Future<CheckResult> run(int checkPort) async {
    final watch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (_) => 'PROXY 127.0.0.1:$checkPort';
    try {
      final request = await client.getUrl(Uri.parse(probeUrl)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'Curie/connection-check');
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      watch.stop();
      final ok = response.statusCode == 204 ||
          (response.statusCode >= 200 && response.statusCode < 400);
      final result = CheckResult(
        ok: ok,
        ms: watch.elapsedMilliseconds,
        status: response.statusCode,
        error: ok ? null : 'HTTP ${response.statusCode}',
      );
      AppLog.add(
        'check',
        ok
            ? 'туннель отвечает: ${result.ms} мс, HTTP ${result.status}'
            : 'туннель ответил HTTP ${result.status}',
      );
      return result;
    } on Object catch (e) {
      watch.stop();
      final message = e.toString();
      AppLog.add('check', 'проверка не прошла: $message');
      return CheckResult(ok: false, ms: watch.elapsedMilliseconds, error: message);
    } finally {
      client.close(force: true);
    }
  }
}
