import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/profile.dart';
import '../models/settings.dart';
import 'app_log.dart';
import 'connection.dart';
import 'xray.dart';

class PingResult {
  const PingResult({this.ms, this.error, required this.at});

  final int? ms;
  final String? error;
  final DateTime at;

  bool get ok => ms != null;
}

/// Один замер: готовый элемент запроса `pingBatch` для узла.
class _Probe {
  const _Probe({
    required this.profileId,
    required this.item,
    required this.fallback,
  });

  final String profileId;
  final Map<String, dynamic> item;

  /// Запасной сервер: его результат используется, только если основные не
  /// ответили.
  final bool fallback;
}

class _Attempt {
  const _Attempt({this.ms, this.error, this.fallback = false});

  final int? ms;
  final String? error;
  final bool fallback;

  _Attempt copyWithFallback(bool value) => _Attempt(
        ms: ms,
        error: error,
        fallback: value,
      );
}

/// Задержка до узлов: TCP/TLS-рукопожатие или GET-запрос через узел.
///
/// У узла-балансировщика проверяются и основные серверы, и fallback. Пока
/// работает основной — показывает его задержку; если все основные мертвы,
/// берётся ответ запасного.
class Ping {
  static final ValueNotifier<Map<String, PingResult>> results = ValueNotifier({});

  /// Идёт общий замер — для кнопки в карточке провайдера.
  static final ValueNotifier<bool> running = ValueNotifier(false);

  /// Узлы, которые прямо сейчас измеряются: у них в списке крутится спиннер,
  /// даже если старое значение уже есть.
  static final ValueNotifier<Set<String>> pending = ValueNotifier(<String>{});

  static const int _errorDelay = 10000;
  static const int _timeoutDelay = 11000;

  static Future<void> measure(List<Profile> profiles, Settings settings) async {
    if (profiles.isEmpty || running.value) return;

    final ids = profiles.map((profile) => profile.id).toSet();
    running.value = true;
    pending.value = {...pending.value, ...ids};

    try {
      switch (settings.pingMode) {
        case PingMode.tcp:
          await _tcp(profiles, settings);
        case PingMode.proxy:
          await _proxy(profiles, settings);
      }
    } finally {
      pending.value = {...pending.value}..removeAll(ids);
      running.value = false;
    }
  }

  static Future<void> _tcp(List<Profile> profiles, Settings settings) async {
    final timeout = Duration(seconds: settings.pingTimeoutSeconds);

    await Future.wait(profiles.map((profile) async {
      try {
        final plan = await pingTargetsFor(profile);
        if (plan.targets.isEmpty) {
          _put(profile.id, _error('нет адреса'));
          return;
        }

        final attempts = await Future.wait(
          plan.targets.map((target) async {
            final attempt = await _tcpTarget(target, timeout);
            return attempt.copyWithFallback(target.fallback);
          }),
        );
        _put(profile.id, _bestAttempt(attempts));
      } on Object catch (e) {
        _put(profile.id, _error(e));
      } finally {
        _done(profile.id);
      }
    }));
  }

  /// TCP-connect, а для TLS/REALITY — ещё и полное TLS-рукопожатие с настоящим
  /// SNI. Голый connect подтверждает только открытый порт: у провайдера с
  /// белыми списками он проходит, даже когда узел уже не работает.
  static Future<_Attempt> _tcpTarget(PingTarget target, Duration timeout) async {
    final watch = Stopwatch()..start();
    Socket? socket;

    try {
      final raw = await Socket.connect(
        target.address,
        target.port,
        timeout: timeout,
      );
      socket = raw;

      if (!target.isTls) {
        watch.stop();
        return _Attempt(ms: watch.elapsedMilliseconds);
      }

      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) return const _Attempt(error: 'таймаут');

      final sni = target.serverName;
      final secure = await SecureSocket.secure(
        raw,
        host: (sni == null || sni.isEmpty) ? target.address : sni,
        onBadCertificate: (_) => true,
        supportedProtocols: target.alpn,
      ).timeout(remaining);

      socket = null;
      secure.destroy();
      watch.stop();
      return _Attempt(ms: watch.elapsedMilliseconds);
    } on Object catch (e) {
      return _Attempt(error: e.toString());
    } finally {
      socket?.destroy();
    }
  }

  static Future<void> _proxy(List<Profile> profiles, Settings settings) async {
    const xray = Xray();
    final probes = <_Probe>[];
    final remaining = <String, int>{};
    final bestPrimary = <String, PingResult>{};
    final bestFallback = <String, PingResult>{};
    final runs = settings.pingProfile == PingProfile.double ? 2 : 1;

    for (final profile in profiles) {
      try {
        final plan = await pingTargetsFor(profile);
        if (plan.targets.isEmpty) {
          _put(profile.id, _error('нет адреса'));
          _done(profile.id);
          continue;
        }

        for (final target in plan.targets) {
          probes.add(_Probe(
            profileId: profile.id,
            item: pingBatchItem(plan, target),
            fallback: target.fallback,
          ));
        }
        remaining[profile.id] = plan.targets.length * runs;
      } on Object catch (e) {
        _put(profile.id, _error(e));
        _done(profile.id);
      }
    }

    // Ядро принимает не больше пяти конфигов за вызов. Пока обрабатывается
    // одна пятёрка, результаты остальных узлов ещё не готовы — так значения
    // появляются по мере прохождения замера, а не все разом.
    for (var start = 0; start < probes.length; start += 5) {
      final end = start + 5 > probes.length ? probes.length : start + 5;
      final chunk = probes.sublist(start, end);
      final configs = <Map<String, dynamic>>[
        for (final probe in chunk) probe.item,
      ];

      for (var run = 0; run < runs; run++) {
        var items = const <Object?>[];
        Object? failure;

        try {
          final response = await xray.invoke('pingBatch', {
            'configs': configs,
            'timeout': settings.pingTimeoutSeconds,
            'url': settings.pingUrl,
            'warm': settings.pingProfile == PingProfile.keepAlive,
          });
          final data =
              (response['data'] as Map?)?.cast<String, dynamic>() ?? const {};
          items = (data['results'] as List?) ??
              (data['items'] as List?) ??
              const <Object?>[];
        } on Object catch (e) {
          failure = e;
          AppLog.add('ping', 'pingBatch: $e');
        }

        for (var i = 0; i < chunk.length; i++) {
          final probe = chunk[i];
          final result = failure != null
              ? _error(failure)
              : _parseItem(i < items.length ? items[i] : null);

          _apply(
            probe.profileId,
            result,
            fallback: probe.fallback,
            bestPrimary: bestPrimary,
            bestFallback: bestFallback,
          );
          remaining[probe.profileId] = (remaining[probe.profileId] ?? 1) - 1;
          if (remaining[probe.profileId]! <= 0) {
            _done(probe.profileId);
          }
        }
      }
    }
  }

  static PingResult _parseItem(Object? item) {
    if (item is! Map) return _error('нет ответа');

    final delay = (item['delay'] as num?)?.toInt();
    final success = item['success'] == true;
    if (success && delay != null && delay >= 0 && delay < _errorDelay) {
      return PingResult(ms: delay, at: DateTime.now());
    }

    final error = (item['error'] as String?)?.trim();
    if (error != null && error.isNotEmpty) {
      return PingResult(error: error, at: DateTime.now());
    }
    if (delay == _timeoutDelay) {
      return PingResult(error: 'таймаут', at: DateTime.now());
    }
    return _error('узел не ответил');
  }

  /// Основные серверы имеют приоритет над запасным: пока хоть один из них
  /// отвечает, показываем его задержку. Fallback нужен только если основные
  /// не ответили. Внутри группы берём самый быстрый успешный ответ.
  static PingResult _bestAttempt(List<_Attempt> attempts) {
    int? bestPrimary;
    int? bestFallback;
    String? primaryError;
    String? fallbackError;

    for (final attempt in attempts) {
      if (attempt.ms != null) {
        if (attempt.fallback) {
          if (bestFallback == null || attempt.ms! < bestFallback) {
            bestFallback = attempt.ms;
          }
        } else if (bestPrimary == null || attempt.ms! < bestPrimary) {
          bestPrimary = attempt.ms;
        }
        continue;
      }
      if (attempt.fallback) {
        fallbackError ??= attempt.error;
      } else {
        primaryError ??= attempt.error;
      }
    }

    final ms = bestPrimary ?? bestFallback;
    return ms != null
        ? PingResult(ms: ms, at: DateTime.now())
        : _error(primaryError ?? fallbackError ?? 'узел не ответил');
  }

  /// Из всех замеров узла держим лучший результат отдельно для основных
  /// серверов и для fallback, а в интерфейс публикуем приоритетный.
  static void _apply(
    String profileId,
    PingResult result, {
    required bool fallback,
    required Map<String, PingResult> bestPrimary,
    required Map<String, PingResult> bestFallback,
  }) {
    final best = fallback ? bestFallback : bestPrimary;
    final previous = best[profileId];
    if (result.ok) {
      if (previous == null || !previous.ok || result.ms! < previous.ms!) {
        best[profileId] = result;
      }
    } else if (previous == null) {
      best[profileId] = result;
    }

    final primary = bestPrimary[profileId];
    final reserve = bestFallback[profileId];
    final published = (primary != null && primary.ok)
        ? primary
        : ((reserve != null && reserve.ok)
            ? reserve
            : (primary ?? reserve));
    if (published != null) _put(profileId, published);
  }

  static PingResult _error(Object error) =>
      PingResult(error: error.toString(), at: DateTime.now());

  static void _put(String id, PingResult result) {
    results.value = {...results.value, id: result};
  }

  static void _done(String id) {
    if (!pending.value.contains(id)) return;
    pending.value = {...pending.value}..remove(id);
  }
}
