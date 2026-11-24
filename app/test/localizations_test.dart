import 'package:curie/src/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Russian translation covers every English key', () {
    final missing = AppLocalizations.en.keys
        .where((key) => !AppLocalizations.ru.containsKey(key))
        .toList();
    expect(missing, isEmpty, reason: 'нет перевода: $missing');
  });

  test('no extra keys in Russian', () {
    final extra = AppLocalizations.ru.keys
        .where((key) => !AppLocalizations.en.containsKey(key))
        .toList();
    expect(extra, isEmpty, reason: 'лишние ключи: $extra');
  });

  test('placeholders match between languages', () {
    final pattern = RegExp(r'\{(\w+)\}');
    for (final key in AppLocalizations.en.keys) {
      final en = pattern
          .allMatches(AppLocalizations.en[key]!)
          .map((m) => m.group(1))
          .toSet();
      final ru = pattern
          .allMatches(AppLocalizations.ru[key]!)
          .map((m) => m.group(1))
          .toSet();
      expect(ru, en, reason: 'плейсхолдеры разошлись в ключе $key');
    }
  });
}
