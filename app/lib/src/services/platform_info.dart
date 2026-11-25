import 'dart:io';

import 'package:flutter/services.dart';

/// ОС для User-Agent. На Android версию берём из Build.VERSION.RELEASE через
/// нативный канал: `Platform.operatingSystem` даёт только «android», а в
/// заголовке нужно `Android17`. Значение кэшируется — за время жизни процесса
/// версия ОС не меняется.
class PlatformInfo {
  static const MethodChannel _channel =
      MethodChannel('io.github.waylandx11.curie/bridge');

  static String? _cache;

  static Future<String> userAgentPart() async {
    final cached = _cache;
    if (cached != null) return cached;

    var result = Platform.operatingSystem;
    if (Platform.isAndroid) {
      try {
        final info = await _channel.invokeMapMethod<String, dynamic>(
          'platformInfo',
        );
        final release = (info?['version'] as String?)?.trim() ?? '';
        final major = RegExp(r'\d+').firstMatch(release)?.group(0);
        if (major != null && major.isNotEmpty) {
          result = 'Android$major';
        }
      } on Object {
        // Канал может быть ещё не готов — оставляем «android» без версии.
      }
    }

    _cache = result;
    return result;
  }
}
