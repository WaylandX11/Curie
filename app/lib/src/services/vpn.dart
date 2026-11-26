import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/settings.dart';
import 'app_log.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

/// Управление туннелем. Статус приходит пушем из Kotlin (`stateChanged`),
/// поэтому UI не опрашивает сервис в цикле. Сессия (порты, время старта)
/// хранится в нативном слое и переживает пересоздание Flutter-виджетов.
class Vpn {
  static const MethodChannel _channel = MethodChannel(
    'io.github.waylandx11.curie/bridge',
  );

  static final ValueNotifier<VpnStatus> status = ValueNotifier(
    VpnStatus.disconnected,
  );
  static final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Локальный HTTP-прокси Xray, через который идут фоновые запросы приложения.
  /// Открыт только когда туннель реально подключён.
  static final ValueNotifier<int> outboundProxyPort = ValueNotifier(0);
  static final ValueNotifier<int> metricsPort = ValueNotifier(0);
  static final ValueNotifier<DateTime?> connectedAt = ValueNotifier(null);

  /// true, пока активный туннель держит Rust-ядро. Выставляется из статуса
  /// нативного слоя, поэтому переживает пересоздание Flutter-движка.
  static bool isRustActive = false;

  static bool get isSupported => Platform.isAndroid;

  /// Порт для обновлений: 0, когда туннель не работает.
  static int get tunnelProxyPort =>
      status.value == VpnStatus.connected ? outboundProxyPort.value : 0;

  static Future<void>? _ready;

  static Future<void> init() => _ready ??= _init();

  static Future<void> _init() async {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stateChanged' && call.arguments is Map) {
        _apply((call.arguments as Map).cast<String, dynamic>());
      }
      if (call.method == 'log' && call.arguments is Map) {
        final args = (call.arguments as Map).cast<String, dynamic>();
        AppLog.add('android', (args['message'] as String?) ?? '');
      }
      return null;
    });
    await refresh();
  }

  /// Перечитать состояние сервиса. Вызывается при возврате в приложение:
  /// пуш мог быть пропущен, пока Flutter-изолят был в фоне.
  static Future<void> refresh() async {
    if (!isSupported) return;
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>('status');
      if (state != null) _apply(state);
    } on PlatformException {
      // Канал ещё не готов — остаёмся в исходном состоянии.
    } on MissingPluginException {
      // Не Android.
    }
  }

  static void _apply(Map<String, dynamic> args) {
    final next = _statusFromName(args['status'] as String?);
    final active = next == VpnStatus.connected;
    final started = (args['connectedAt'] as num?)?.toInt();

    // Сначала порты и время старта, затем статус: слушатели статуса
    // (TunnelMonitor и экран) должны сразу видеть готовую сессию.
    outboundProxyPort.value = active
        ? (args['check'] as num?)?.toInt() ?? 0
        : 0;
    metricsPort.value = active ? (args['metrics'] as num?)?.toInt() ?? 0 : 0;
    isRustActive = args['core'] == 'rust';
    connectedAt.value = active && started != null && started > 0
        ? DateTime.fromMillisecondsSinceEpoch(started)
        : null;
    lastError.value = args['error'] as String?;
    status.value = next;
  }

  static Future<void> connect({
    required String config,
    required Settings settings,
    String geoDir = '',
  }) async {
    try {
      await _channel.invokeMethod<void>('connect', {
        'config': config,
        'tunnelMode': settings.tunnelMode.wireName,
        'useRustCore': settings.useRustCore,
        'dns': settings.dns,
        'mtu': settings.mtu,
        'mode': settings.routingMode.wireName,
        'allowed': settings.allowedApps,
        'bypassed': settings.bypassedApps,
        'geoDir': geoDir,
      });
    } on PlatformException catch (e) {
      throw VpnException(e.code, e.message ?? e.code);
    }
  }

  /// Накопительные счётчики Rust-ядра; null, когда туннель не на нём.
  static Future<({int up, int down})?> rustTraffic() async {
    try {
      final raw = await _channel.invokeMapMethod<String, num>('rustTraffic');
      if (raw == null) return null;
      return (
        up: (raw['up'] ?? 0).toInt(),
        down: (raw['down'] ?? 0).toInt(),
      );
    } on Object {
      return null;
    }
  }

  static Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');

  static VpnStatus _statusFromName(String? name) => switch (name) {
    'connecting' => VpnStatus.connecting,
    'connected' => VpnStatus.connected,
    'disconnecting' => VpnStatus.disconnecting,
    'error' => VpnStatus.error,
    _ => VpnStatus.disconnected,
  };
}

class VpnException implements Exception {
  const VpnException(this.code, this.message);

  final String code;
  final String message;

  bool get isDenied => code == 'vpn_denied';

  @override
  String toString() => message;
}
