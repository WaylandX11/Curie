import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Выбор темы. Не секрет, поэтому лежит в обычных настройках,
/// а не в шифрованном хранилище.
class ThemeController {
  static const _key = 'theme';

  /// По умолчанию остаёмся на фирменной тёмной теме.
  /// Старые значения `light`/`dark` из SharedPreferences сохраняются:
  /// [AppTheme.fromId] понимает их и не сбрасывает выбор пользователя.
  static final ValueNotifier<AppTheme> theme =
      ValueNotifier(AppTheme.dark);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    theme.value = AppTheme.fromId(prefs.getString(_key));
  }

  static Future<void> set(AppTheme value) async {
    theme.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.id);
    } on Object {
      // Тема применяется сразу, даже если хранилище недоступно (например, в тестах).
    }
  }

  /// Кнопка на главной перебирает темы по кругу.
  static Future<void> toggle() => set(
        AppTheme.values[(theme.value.index + 1) % AppTheme.values.length],
      );
}
