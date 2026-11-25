import 'package:curie_windows/src/services/system_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Russian Windows locales select the Russian tray', () {
    expect(isRussianSystemLocale('ru-RU'), isTrue);
    expect(isRussianSystemLocale('ru'), isTrue);
    expect(isRussianSystemLocale('RU_ru'), isTrue);
  });

  test('other Windows locales select English', () {
    expect(isRussianSystemLocale('en-US'), isFalse);
    expect(isRussianSystemLocale('de-DE'), isFalse);
    expect(isRussianSystemLocale(''), isFalse);
  });

  test('Russian Windows UI language selects the Russian tray', () {
    expect(isRussianUiLangId(0x0419), isTrue); // ru-RU
    expect(isRussianUiLangId(0x0819), isTrue); // ru with another sublanguage
    expect(isRussianUiLangId(0x0409), isFalse); // en-US
    expect(isRussianUiLangId(0x0809), isFalse); // en-GB
  });
}
