import 'dart:io';

import 'package:flutter/services.dart';

/// Проверка текущей сети для правила «только по Wi-Fi».
///
/// На Android система сама сообщает `NET_CAPABILITY_NOT_METERED`: Wi-Fi и
/// ethernet обычно безлимитные, мобильный оператор — нет. На Windows стационарных
/// безлимитных сетей нет, поэтому ограничение просто не мешает обновлениям.
class NetworkInfo {
  static const MethodChannel _channel = MethodChannel(
    'io.github.waylandx11.curie/bridge',
  );

  /// Подменяется в тестах; в приложении всегда null.
  static Future<bool> Function()? override;

  static Future<bool> isUnmetered() async {
    final custom = override;
    if (custom != null) return custom();
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isUnmeteredNetwork') ?? false;
    } on Object catch (_) {
      // Неизвестная сеть считается платной: лучше пропустить обновление.
      return false;
    }
  }
}
