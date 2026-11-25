import '../models/profile.dart';

/// Страна выходного узла. Определяется по имени узла: панели почти всегда
/// кладут туда флаг-эмодзи или название страны. Никаких внешних запросов —
/// IP пользователя и сервера никуда не уходят.
class Country {
  static const Map<String, String> _names = {
    'россия': 'RU', 'russia': 'RU', 'российская': 'RU', 'рф': 'RU',
    'германия': 'DE', 'germany': 'DE', 'deutschland': 'DE',
    'нидерланды': 'NL', 'netherlands': 'NL', 'holland': 'NL',
    'финляндия': 'FI', 'finland': 'FI',
    'швеция': 'SE', 'sweden': 'SE',
    'норвегия': 'NO', 'norway': 'NO',
    'дания': 'DK', 'denmark': 'DK',
    'исландия': 'IS', 'iceland': 'IS',
    'польша': 'PL', 'poland': 'PL',
    'франция': 'FR', 'france': 'FR',
    'великобритания': 'GB', 'britain': 'GB', 'england': 'GB', 'london': 'GB',
    'ирландия': 'IE', 'ireland': 'IE',
    'испания': 'ES', 'spain': 'ES',
    'италия': 'IT', 'italy': 'IT',
    'португалия': 'PT', 'portugal': 'PT',
    'чехия': 'CZ', 'czech': 'CZ',
    'австрия': 'AT', 'austria': 'AT',
    'швейцария': 'CH', 'switzerland': 'CH',
    'бельгия': 'BE', 'belgium': 'BE',
    'люксембург': 'LU', 'luxembourg': 'LU',
    'греция': 'GR', 'greece': 'GR',
    'болгария': 'BG', 'bulgaria': 'BG',
    'румыния': 'RO', 'romania': 'RO',
    'венгрия': 'HU', 'hungary': 'HU',
    'словакия': 'SK', 'slovakia': 'SK',
    'словения': 'SI', 'slovenia': 'SI',
    'хорватия': 'HR', 'croatia': 'HR',
    'сербия': 'RS', 'serbia': 'RS',
    'эстония': 'EE', 'estonia': 'EE',
    'латвия': 'LV', 'latvia': 'LV',
    'литва': 'LT', 'lithuania': 'LT',
    'украина': 'UA', 'ukraine': 'UA',
    'беларусь': 'BY', 'belarus': 'BY',
    'молдова': 'MD', 'moldova': 'MD',
    'казахстан': 'KZ', 'kazakhstan': 'KZ',
    'армения': 'AM', 'armenia': 'AM',
    'грузия': 'GE', 'georgia': 'GE',
    'азербайджан': 'AZ', 'azerbaijan': 'AZ',
    'турция': 'TR', 'turkey': 'TR', 'türkiye': 'TR',
    'израиль': 'IL', 'israel': 'IL',
    'оаэ': 'AE', 'emirates': 'AE', 'dubai': 'AE',
    'индия': 'IN', 'india': 'IN',
    'китай': 'CN', 'china': 'CN',
    'гонконг': 'HK', 'hong kong': 'HK',
    'япония': 'JP', 'japan': 'JP',
    'корея': 'KR', 'korea': 'KR',
    'сингапур': 'SG', 'singapore': 'SG',
    'австралия': 'AU', 'australia': 'AU',
    'канада': 'CA', 'canada': 'CA',
    'сша': 'US', 'usa': 'US', 'united states': 'US', 'america': 'US',
    'бразилия': 'BR', 'brazil': 'BR',
    'мексика': 'MX', 'mexico': 'MX',
    'аргентина': 'AR', 'argentina': 'AR',
  };

  /// ISO-код страны или null, если определить не удалось.
  static String? of(Profile profile) {
    final fromEmoji = fromText(profile.name);
    if (fromEmoji != null) return fromEmoji;
    return fromText(profile.address ?? '');
  }

  static String? fromText(String text) {
    final emoji = _emojiCode(text);
    if (emoji != null) return emoji;

    final lower = text.toLowerCase();
    for (final entry in _names.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    // Двухбуквенные коды — только отдельным словом, иначе «Russia» даст «US».
    for (final code in _names.values.toSet()) {
      if (RegExp('(^|[^a-z])${code.toLowerCase()}([^a-z]|\$)').hasMatch(lower)) {
        return code;
      }
    }
    return null;
  }

  /// Флаг-эмодзи: пара региональных индикаторов U+1F1E6…U+1F1FF.
  static String? _emojiCode(String text) {
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length - 1; i++) {
      final a = runes[i];
      final b = runes[i + 1];
      if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
        return String.fromCharCode(65 + (a - 0x1F1E6)) +
            String.fromCharCode(65 + (b - 0x1F1E6));
      }
    }
    return null;
  }

  static String flag(String code) {
    if (code.length != 2) return '🏳️';
    final upper = code.toUpperCase();
    return String.fromCharCodes([
      0x1F1E6 + (upper.codeUnitAt(0) - 65),
      0x1F1E6 + (upper.codeUnitAt(1) - 65),
    ]);
  }

  /// Имя без флага — чтобы не показывать флаг дважды.
  static String cleanName(String name) {
    final runes = name.runes.where((r) => r < 0x1F1E6 || r > 0x1F1FF).toList();
    return String.fromCharCodes(runes).trim();
  }
}
