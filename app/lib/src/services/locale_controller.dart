import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Выбор языка. Не секрет, поэтому лежит в обычных настройках,
/// а не в шифрованном хранилище.
class LocaleController {
  static const _key = 'locale';

  static final ValueNotifier<Locale?> locale = ValueNotifier(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null) locale.value = Locale(code);
  }

  static Future<void> set(Locale? value) async {
    locale.value = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, value.languageCode);
    }
  }
}
