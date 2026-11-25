import 'package:curie_windows/src/services/vpn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adapts an Android TUN config into a local proxy config', () {
    final config = <String, dynamic>{
      'env': {'xray.tun.fd': '3'},
      'metrics': {'listen': '127.0.0.1:11111'},
      'outbounds': [
        {'tag': 'proxy', 'protocol': 'vless'},
      ],
      'inbounds': [
        {
          'tag': 'tun',
          'port': 0,
          'protocol': 'tun',
          'settings': {'name': 'curie-tun', 'mtu': 9000},
          'sniffing': {'enabled': true, 'destOverride': ['http', 'tls']},
        },
        {
          'tag': 'check',
          'port': 12345,
          'protocol': 'http',
          'listen': '127.0.0.1',
          'settings': <String, dynamic>{},
        },
      ],
      'routing': {
        'rules': [
          {'inboundTag': ['tun'], 'outboundTag': 'proxy'},
          {'inboundTag': ['check'], 'outboundTag': 'proxy'},
        ],
      },
    };

    final adapted = Vpn.adaptConfigForWindows(config, proxyPort: 22222);

    expect(adapted.containsKey('env'), isFalse);
    expect(adapted['metrics'], config['metrics']);

    final inbounds = adapted['inbounds'] as List;
    expect(inbounds.length, 2);
    final proxy = inbounds.first as Map;
    expect(proxy['tag'], 'proxy');
    expect(proxy['protocol'], 'mixed');
    expect(proxy['listen'], '127.0.0.1');
    expect(proxy['port'], 22222);
    expect((proxy['sniffing'] as Map)['enabled'], isTrue);
    expect((proxy['settings'] as Map)['auth'], 'noauth');
    expect(inbounds.last['tag'], 'check');

    final rules = (adapted['routing'] as Map)['rules'] as List;
    expect(rules.first['inboundTag'], ['proxy']);
    expect(rules.last['inboundTag'], ['check']);
  });

  test('adds a proxy inbound when the source config has no TUN', () {
    final adapted = Vpn.adaptConfigForWindows(
      <String, dynamic>{
        'inbounds': <Object>[],
        'routing': <String, dynamic>{'rules': <Object>[]},
      },
      proxyPort: 30000,
    );

    final inbounds = adapted['inbounds'] as List;
    expect(inbounds.single['tag'], 'proxy');
    expect(inbounds.single['port'], 30000);
  });
}
