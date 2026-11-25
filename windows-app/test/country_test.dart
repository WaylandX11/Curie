import 'package:curie_windows/src/models/profile.dart';
import 'package:curie_windows/src/services/country.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emoji flag in the node name wins', () {
    expect(Country.of(const Profile(name: '🇷🇺 Россия (обход БС)')), 'RU');
    expect(Country.of(const Profile(name: '🇩🇪 Germany')), 'DE');
    expect(Country.of(const Profile(name: '🇳🇱 Netherlands')), 'NL');
  });

  test('country names in Russian and English are recognised', () {
    expect(Country.of(const Profile(name: 'Германия')), 'DE');
    expect(Country.of(const Profile(name: 'Нидерланды')), 'NL');
    expect(Country.of(const Profile(name: 'Finland Helsinki')), 'FI');
    expect(Country.of(const Profile(name: 'United States')), 'US');
  });

  test('Russia is not mistaken for US', () {
    expect(Country.of(const Profile(name: 'Russia')), 'RU');
  });

  test('two-letter code only as a separate word', () {
    expect(Country.of(const Profile(name: 'node-de-01')), 'DE');
    expect(Country.of(const Profile(name: 'weird')), isNull);
  });

  test('flag rendering and name cleanup', () {
    expect(Country.flag('RU'), '🇷🇺');
    expect(Country.cleanName('🇷🇺 Россия'), 'Россия');
  });

  test('unknown node has no country', () {
    expect(Country.of(const Profile(name: 'Обход БС')), isNull);
  });
}
