import 'dart:ffi';
import 'dart:io';

/// Язык интерфейса Windows, а не язык, выбранный внутри Curie.
///
/// Используется `GetUserDefaultUILanguage` — язык, который видит пользователь
/// в меню «Пуск» и диалогах Windows. `Platform.localeName` здесь только запасной
/// вариант: он отражает региональные настройки и может не совпадать с языком
/// интерфейса системы.
bool isRussianSystemLocale([String? localeName]) {
  if (localeName != null) {
    return localeName.toLowerCase().startsWith('ru');
  }

  final langId = _cachedUiLangId;
  if (langId != null) return isRussianUiLangId(langId);
  return Platform.localeName.toLowerCase().startsWith('ru');
}

/// LANGID -> язык. `0x0419` — русский (STARTPRIMARYLANG = `0x19`).
bool isRussianUiLangId(int langId) => (langId & 0x03ff) == 0x0019;

final int? _cachedUiLangId = _readUiLangId();

int? _readUiLangId() {
  if (!Platform.isWindows) return null;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getUiLanguage = kernel32.lookupFunction<
        Uint16 Function(),
        int Function()>('GetUserDefaultUILanguage');
    return getUiLanguage();
  } on Object {
    return null;
  }
}
