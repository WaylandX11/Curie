import 'dart:typed_data';

import '../models/app_info.dart';

/// Список приложений для раздельного туннелирования.
///
/// android-версия получает список через `PackageManager`. На Windows системный
/// прокси общий для всех процессов, поэтому выбор приложений недоступен:
/// `list()` возвращает пустой список, а UI скрывает этот раздел через
/// `Apps.isSupported`. Логика сортировки остаётся общей и чистой.
class Apps {
  /// Иконки, уже полученные с платформы. На Windows их нет.
  static final Map<String, Uint8List?> _icons = {};

  static bool get isSupported => false;

  static Future<List<AppInfo>> list() async => const [];

  /// Пользовательские приложения идут первыми, внутри групп — по алфавиту.
  static void sortApps(List<AppInfo> apps) {
    apps.sort((a, b) {
      if (a.system != b.system) return a.system ? 1 : -1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  /// windows-реализация иконок приложений отсутствует.
  static Future<Uint8List?> icon(String package) async {
    if (_icons.containsKey(package)) return _icons[package];
    _icons[package] = null;
    return null;
  }
}
