import 'dart:convert';

import 'package:flutter/services.dart';

class XrayException implements Exception {
  const XrayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Единственная дверь к ядру: всё общение идёт через `LibXray.invoke`
/// на стороне Kotlin, здесь — только сборка запроса и разбор ответа.
class Xray {
  const Xray();

  static const MethodChannel _channel = MethodChannel('io.github.waylandx11.curie/bridge');
  static const int _apiVersion = 3;

  /// Ответ ядра целиком: `{success, data, error}`.
  Future<Map<String, dynamic>> invoke(String method, Map<String, dynamic> payload) async {
    final request = jsonEncode({
      'apiVersion': _apiVersion,
      'method': method,
      'payload': payload,
    });
    final raw = await _channel.invokeMethod<String>('invoke', {'request': request});
    final response = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
    if (response['success'] != true) {
      final error = (response['error'] as String?)?.trim();
      throw XrayException((error == null || error.isEmpty) ? 'Xray: $method failed' : error);
    }
    return response;
  }

  /// Версия ядра для подписи под кнопкой. Пустая строка, если ядро не ответило.
  Future<String> version() async {
    try {
      final response = await invoke('xrayVersion', const {});
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      return (data['version'] as String?) ?? '';
    } on Object {
      return '';
    }
  }

  /// Свободные localhost-порты под метрики и локальный прокси проверки.
  /// Ядро держит слушатели только на время выбора и сразу закрывает их,
  /// поэтому это не бронь, а кандидаты.
  Future<List<int>> freePorts(int count) async {
    try {
      final response = await invoke('getFreePorts', {'count': count});
      final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final ports = data['ports'] as List?;
      if (ports != null) {
        return ports.map((e) => (e as num).toInt()).toList();
      }
    } on Object {
      // Порты необязательны: используем запасные.
    }
    return const [];
  }

  Future<int?> freePort() async {
    final ports = await freePorts(1);
    return ports.isEmpty ? null : ports.first;
  }

  Future<List<Map<String, dynamic>>> parseLink(String link) async {
    final response = await invoke('convertShareLinksToXrayJson', {'text': link});
    final data = (response['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final outbounds = data['outbounds'];
    if (outbounds is! List || outbounds.isEmpty) {
      throw const XrayException('no outbounds');
    }
    return outbounds.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }
}
