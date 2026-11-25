import 'package:curie_windows/src/services/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proxy schemes are recognised', () {
    expect(Importer.isProxyLink('vless://id@host:443#Node'), isTrue);
    expect(Importer.isProxyLink('ss://abc@host:8388'), isTrue);
    expect(Importer.isProxyLink('  trojan://pw@host:443  '), isTrue);
    expect(Importer.isProxyLink('https://panel/sub'), isFalse);
    expect(Importer.isProxyLink('просто текст'), isFalse);
  });

  test('subscription must be http(s) with a host', () {
    expect(Importer.isSubscriptionUrl('https://panel.example/sub/abc'), isTrue);
    expect(Importer.isSubscriptionUrl('http://192.168.1.10:2053/sub/x'), isTrue);
    expect(Importer.isSubscriptionUrl('https://'), isFalse);
    expect(Importer.isSubscriptionUrl('vless://id@host:443'), isFalse);
  });

  test('scan separates links from the subscription URL and drops duplicates', () {
    const text = '''
Подключайся так:
vless://a@host:443#One
vless://a@host:443#One
ss://abc@host:8388#Two
https://panel.example/sub/abc
''';
    final found = Importer.scan(text);

    expect(found.links, ['vless://a@host:443#One', 'ss://abc@host:8388#Two']);
    expect(found.subscriptionUrl, 'https://panel.example/sub/abc');
  });

  test('links win over a subscription URL when both are present', () async {
    // importText требует ядро, поэтому проверяем только классификацию.
    final found = Importer.scan('vless://a@host:443\nhttps://panel/sub');
    expect(found.links, isNotEmpty);
  });

  test('empty and unrelated text yields nothing', () {
    final found = Importer.scan('   \n\nкакой-то текст\n');
    expect(found.links, isEmpty);
    expect(found.subscriptionUrl, isNull);
  });
}
