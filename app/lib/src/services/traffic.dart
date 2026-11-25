import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Скорость в байтах в секунду.
class TrafficSample {
  const TrafficSample({this.up = 0, this.down = 0});

  final int up;
  final int down;

  /// В интерфейсе показываем одну суммарную скорость: стрелки ↑/↓ смущали,
  /// когда один из счётчиков подолгу оставался нулевым.
  int get total => up + down;
}

/// Читает счётчики Xray из метрик ядра.
///
/// libXray не отдаёт трафик через `invoke`, но поднимает обычный HTTP-сервер
/// метрик (`/debug/vars`), если в конфиге есть `metrics`, `stats` и политика
/// `statsOutbound*`. Запрос идёт на 127.0.0.1 — системный VPN маршрут его не
/// трогает, наружу ничего не уходит.
class TrafficCounters {
  static const Set<String> serviceTags = {'direct', 'block', 'dns-out'};

  static TrafficSample total(String body, {Set<String> exclude = serviceTags}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on Object {
      return const TrafficSample();
    }
    final stats = (decoded as Map?)?['stats'];
    final outbound = stats is Map ? stats['outbound'] : null;
    if (outbound is! Map) return const TrafficSample();

    var up = 0;
    var down = 0;
    outbound.forEach((tag, value) {
      if (exclude.contains(tag.toString()) || value is! Map) return;
      up += ((value['uplink'] as num?) ?? 0).toInt();
      down += ((value['downlink'] as num?) ?? 0).toInt();
    });
    return TrafficSample(up: up, down: down);
  }
}

/// Опрос счётчиков раз в секунду. Значения в `/debug/vars` накопительные,
/// поэтому скорость — разница между двумя соседними замерами.
class Traffic extends ValueNotifier<TrafficSample> {
  Traffic._() : super(const TrafficSample());

  static const int defaultPort = 49227;
  static final Traffic instance = Traffic._();

  static ValueListenable<TrafficSample> get speed => instance;

  final HttpClient _client = HttpClient()
    // Метрики всегда локальные: системный прокси тут не нужен и может
    // незаметно увести запрос от 127.0.0.1.
    ..findProxy = (_) => 'DIRECT';
  Timer? _timer;
  int _port = defaultPort;
  int? _lastUp;
  int? _lastDown;
  DateTime? _lastAt;

  static void start(int port) => instance._start(port);
  static void stop() => instance._stop();

  void _start(int port) {
    if (_timer != null && _port == port) return;
    _stop();
    _port = port;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _poll();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _resetSample();
  }

  void _resetSample() {
    _lastAt = null;
    _lastUp = null;
    _lastDown = null;
    if (value.up != 0 || value.down != 0) {
      value = const TrafficSample();
    }
  }

  Future<void> _poll() async {
    try {
      final request = await _client
          .getUrl(Uri.parse('http://127.0.0.1:$_port/debug/vars'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        _resetSample();
        return;
      }
      final body = await utf8.decoder.bind(response).join();
      final totals = TrafficCounters.total(body);
      final now = DateTime.now();
      final previousAt = _lastAt;
      final previousUp = _lastUp;
      final previousDown = _lastDown;
      if (previousAt != null && previousUp != null && previousDown != null) {
        final seconds = now.difference(previousAt).inMilliseconds / 1000;
        // Счётчики обнуляются при reconnect: отрицательная дельта — не скорость.
        final up = totals.up - previousUp;
        final down = totals.down - previousDown;
        if (seconds >= 0.5 && up >= 0 && down >= 0) {
          value = TrafficSample(
            up: (up / seconds).round(),
            down: (down / seconds).round(),
          );
        } else {
          // Счётчики обнулились при перезапуске ядра — старая скорость больше
          // не имеет отношения к действительности.
          _resetSample();
        }
      }
      _lastUp = totals.up;
      _lastDown = totals.down;
      _lastAt = now;
    } on Object {
      // Метрики — необязательная деталь интерфейса: ядро могло ещё не
      // поднять сервер, порт занят или соединение закрылось. Не шумим в журнал,
      // но и не показываем последнюю скорость как текущую.
      _resetSample();
    }
  }
}
