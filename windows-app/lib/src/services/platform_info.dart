import 'dart:io';

import 'windows_system.dart';

/// ОС для User-Agent. На Android версию дал MethodChannel, на Windows читаем
/// DisplayVersion из реестра. Значение кэшируется — за время жизни процесса
/// версия ОС не меняется.
class PlatformInfo {
  static String? _cache;

  static Future<String> userAgentPart() async {
    final cached = _cache;
    if (cached != null) return cached;

    var result = Platform.operatingSystem;
    if (Platform.isWindows) {
      final version = await WindowsRegistry.read(
        WindowsRegistry.windowsNt,
        'DisplayVersion',
      );
      final clean = version
              ?.trim()
              .replaceAll(RegExp(r'[^0-9A-Za-z.]'), '') ??
          '';
      if (clean.isNotEmpty) result = 'Windows$clean';
    }

    _cache = result;
    return result;
  }
}
