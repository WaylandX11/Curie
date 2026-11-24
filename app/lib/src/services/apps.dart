import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_info.dart';

/// Список приложений для раздельного туннелирования.
///
/// Берём все установленные приложения, включая системные и те, у которых нет
/// иконки в лаунчере (Android Auto, GMS). Без `QUERY_ALL_PACKAGES` Android 11+
/// отдаёт только лаунчерные приложения, поэтому разрешение объявлено в
/// манифесте и требует декларации в Play.
class Apps {
  static const MethodChannel _channel =
      MethodChannel('io.github.waylandx11.curie/bridge');

  /// Иконки, уже полученные с платформы. `null` — иконки нет, повторно не просим.
  static final Map<String, Uint8List?> _icons = {};

  static bool get isSupported => Platform.isAndroid;

  static Future<List<AppInfo>> list() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<dynamic>('listApps');
    if (raw == null) return const [];

    final apps = <AppInfo>[];
    for (final item in raw) {
      if (item is! Map) continue;
      apps.add(AppInfo.fromMap(item.cast<String, dynamic>()));
    }
    sortApps(apps);
    return apps;
  }

  /// Пользовательские приложения идут первыми, внутри групп — по алфавиту.
  static void sortApps(List<AppInfo> apps) {
    apps.sort((a, b) {
      if (a.system != b.system) return a.system ? 1 : -1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  /// Иконка приложения: PNG 64×64 или `null`. Запрашивается по требованию и
  /// кешируется: в полном списке сотни пакетов, и отдавать все картинки сразу —
  /// лишние мегабайты и заметная задержка открытия.
  static Future<Uint8List?> icon(String package) async {
    if (_icons.containsKey(package)) return _icons[package];
    if (!isSupported) return null;

    Uint8List? bytes;
    try {
      bytes = await _channel
          .invokeMethod<Uint8List>('appIcon', {'package': package});
    } on PlatformException {
      bytes = null;
    }
    _icons[package] = bytes;
    return bytes;
  }
}
