import 'package:curie/src/services/theme_controller.dart';
import 'package:curie/src/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  tearDown(() => ThemeController.theme.value = AppTheme.dark);

  test('old SharedPreferences values keep working', () {
    expect(AppTheme.fromId(null), AppTheme.dark);
    expect(AppTheme.fromId('dark'), AppTheme.dark);
    expect(AppTheme.fromId('light'), AppTheme.light);
    expect(AppTheme.fromId('amber'), AppTheme.amber);
    expect(AppTheme.fromId('unknown'), AppTheme.dark);
  });

  test('every theme has a stable id, label and brightness', () {
    for (final theme in AppTheme.values) {
      expect(AppTheme.fromId(theme.id), theme);
      expect(theme.labelKey, startsWith('theme'));
    }
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.forest.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(AppTheme.amber.brightness, Brightness.dark);
    expect(AppTheme.ocean.brightness, Brightness.dark);
  });

  test('the header button cycles through all palettes', () async {
    ThemeController.theme.value = AppTheme.dark;
    await ThemeController.toggle();
    expect(ThemeController.theme.value, AppTheme.light);
    await ThemeController.toggle();
    expect(ThemeController.theme.value, AppTheme.amber);
    await ThemeController.toggle();
    expect(ThemeController.theme.value, AppTheme.ocean);
    await ThemeController.toggle();
    expect(ThemeController.theme.value, AppTheme.forest);
    await ThemeController.toggle();
    expect(ThemeController.theme.value, AppTheme.dark);
  });
}
