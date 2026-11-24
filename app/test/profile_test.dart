import 'package:curie/src/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VLESS profile takes name from tag and address from vnext', () {
    final profile = profileFromOutbound(
      link: 'vless://id@example.com:443#Frankfurt',
      outbound: {
        'tag': 'Frankfurt',
        'settings': {
          'vnext': [
            {'address': 'example.com', 'port': 443},
          ],
        },
      },
      fallbackName: 'fallback',
    );

    expect(profile.name, 'Frankfurt');
    expect(profile.address, 'example.com');
    expect(profile.subscriptionUrl, isNull);
  });

  test('Shadowsocks profile takes address from servers', () {
    final profile = profileFromOutbound(
      link: 'ss://abc@1.2.3.4:8388',
      outbound: {
        'settings': {
          'servers': [
            {'address': '1.2.3.4', 'port': 8388},
          ],
        },
      },
      fallbackName: 'Без имени',
      subscriptionUrl: 'https://panel.example/sub/abc',
    );

    expect(profile.name, 'Без имени');
    expect(profile.address, '1.2.3.4');
    expect(profile.subscriptionUrl, 'https://panel.example/sub/abc');
  });

  test('profile survives a storage round trip', () {
    const profile = Profile(
      link: 'vless://x',
      name: 'Node',
      address: 'host',
      subscriptionUrl: 'https://panel/sub',
    );
    final restored = Profile.fromJson(profile.toJson());

    expect(restored.link, profile.link);
    expect(restored.name, profile.name);
    expect(restored.address, profile.address);
    expect(restored.subscriptionUrl, profile.subscriptionUrl);
  });
}
