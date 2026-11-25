import 'dart:convert';

import 'windows_xray.dart';

class XrayException implements Exception {
  const XrayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Единственная дверь к ядру: запрос собирается в том же JSON-envelope,
/// что и на Android (`apiVersion`, `method`, `payload`), но вместо Kotlin
/// его обрабатывает Windows-слой поверх `xray.exe`.
///
/// Публичный API classe не изменился — UI и тесты продолжают работать с
/// `Xray()`, `version()`, `freePorts()`, `parseLink()` и `invoke()`.
class Xray {
  const Xray();

  static const int _apiVersion = 3;

  /// Ответ ядра целиком: `{success, data, error}`.
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> payload,
  ) async {
    final request = jsonEncode({
      'apiVersion': _apiVersion,
      'method': method,
      'payload': payload,
    });
    final envelope = jsonDecode(request) as Map<String, dynamic>;
    final name = envelope['method'] as String? ?? '';
    final body = (envelope['payload'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    try {
      final data = await WindowsXray.invoke(name, body);
      return <String, dynamic>{'success': true, 'data': data};
    } on WindowsXrayException catch (e) {
      throw XrayException(e.message);
    } on Object catch (e) {
      throw XrayException('Xray: $name failed: $e');
    }
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
  /// Это не бронь, а кандидаты: слушатели сразу закрываются.
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
