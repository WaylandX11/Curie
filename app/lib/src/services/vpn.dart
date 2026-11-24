import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/settings.dart';
import 'app_log.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

/// Управление туннелем. Статус приходит пушем из Kotlin (`stateChanged`),
/// поэтому UI не опрашивает сервис в цикле.
class Vpn {
  static const MethodChannel _channel = MethodChannel(
    'io.github.waylandx11.curie/bridge',
  );

  static final ValueNotifier<VpnStatus> status = ValueNotifier(
    VpnStatus.disconnected,
  );
  static final ValueNotifier<String?> lastError = ValueNotifier(null);

  static bool get isSupported => Platform.isAndroid;

  static Future<void>? _ready;

  static Future<void> init() => _ready ??= _init();

  static Future<void> _init() async {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stateChanged' && call.arguments is Map) {
        final args = (call.arguments as Map).cast<String, dynamic>();
        status.value = _statusFromName(args['status'] as String?);
        lastError.value = args['error'] as String?;
      }
      if (call.method == 'log' && call.arguments is Map) {
        final args = (call.arguments as Map).cast<String, dynamic>();
        AppLog.add('android', (args['message'] as String?) ?? '');
      }
      return null;
    });
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>('status');
      if (state != null) {
        status.value = _statusFromName(state['status'] as String?);
        lastError.value = state['error'] as String?;
      }
    } on PlatformException {
      // Канал ещё не готов — остаёмся в исходном состоянии.
    } on MissingPluginException {
      // Не Android.
    }
  }

  static Future<void> connect({
    required String config,
    required Settings settings,
  }) async {
    try {
      await _channel.invokeMethod<void>('connect', {
        'config': config,
        'dns': settings.dns,
        'mtu': settings.mtu,
        'mode': settings.routingMode.wireName,
        'allowed': settings.allowedApps,
        'bypassed': settings.bypassedApps,
      });
    } on PlatformException catch (e) {
      throw VpnException(e.code, e.message ?? e.code);
    }
  }

  static Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');

  /// Первая ABI из `Build.SUPPORTED_ABIS` — нужна, чтобы предложить правильный
  /// split-APK при проверке обновлений. На не-Android возвращает null.
  static Future<String?> abi() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('abi');
    } on Object {
      return null;
    }
  }

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
