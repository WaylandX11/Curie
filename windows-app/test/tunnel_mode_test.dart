import 'dart:convert';

import 'package:curie_windows/src/models/settings.dart';
import 'package:curie_windows/src/services/xray_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const outbound = <String, dynamic>{
    'tag': 'proxy',
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {'address': 'example.com', 'port': 443},
      ],
    },
  };

  Map<String, dynamic> configFor(
    Settings settings, {
    int checkPort = 12345,
  }) =>
      jsonDecode(
        buildXrayConfig(
          outbounds: [outbound],
          settings: settings,
          checkPort: checkPort,
        ),
      ) as Map<String, dynamic>;

  List<Map<String, dynamic>> inboundsOf(Map<String, dynamic> config) =>
      (config['inbounds'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> rulesOf(Map<String, dynamic> config) =>
      ((config['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  test('tunnel modes expose TUN and SOCKS independently', () {
    expect(TunnelMode.tun.hasTun, isTrue);
    expect(TunnelMode.tun.hasProxy, isFalse);
    expect(TunnelMode.tunProxy.hasTun, isTrue);
    expect(TunnelMode.tunProxy.hasProxy, isTrue);
    expect(TunnelMode.proxy.hasTun, isFalse);
    expect(TunnelMode.proxy.hasProxy, isTrue);
    expect(TunnelMode.fromName('tun_proxy'), TunnelMode.tunProxy);
    expect(TunnelMode.fromName('socks'), TunnelMode.proxy);
    expect(TunnelMode.fromName('unknown'), TunnelMode.tun);
    expect(TunnelMode.proxy.wireName, 'proxy');
  });

  test('SOCKS credentials are generated once and survive reload', () {
    final first = const Settings().materializeSocksDefaults();
    expect(
      first.socksPort,
      allOf(greaterThanOrEqualTo(20000), lessThanOrEqualTo(39999)),
    );
    expect(first.socksUsername, 'curie');
    expect(first.socksPassword, isNotEmpty);
    expect(first.effectiveSocksPort, first.socksPort);
    expect(first.effectiveSocksPassword, first.socksPassword);

    final reloaded = Settings.fromJson(first.toJson());
    expect(reloaded.socksPort, first.socksPort);
    expect(reloaded.socksPassword, first.socksPassword);
    expect(reloaded.socksUsername, first.socksUsername);
    expect(reloaded.socksAuth, isTrue);
    expect(reloaded.tunnelMode, first.tunnelMode);
  });

  test('Windows adapts a TUN-less config to the system proxy', () {
    final config = configFor(
      const Settings(tunnelMode: TunnelMode.proxy, socksPort: 23456),
    );
    expect(
      inboundsOf(config).map((e) => e['protocol']).toList(),
      ['socks', 'http'],
    );
    expect(
      rulesOf(config).any(
        (rule) =>
            rule['inboundTag'] is List &&
            (rule['inboundTag'] as List).contains('tun'),
      ),
      isFalse,
    );
  });

  test('TUN + proxy keeps both inbounds and the DNS intercept rule', () {
    final config = configFor(
      const Settings(tunnelMode: TunnelMode.tunProxy, socksPort: 23456),
    );
    expect(
      inboundsOf(config).map((e) => e['protocol']).toList(),
      ['tun', 'socks', 'http'],
    );
    expect(
      rulesOf(config).any(
        (rule) =>
            rule['outboundTag'] == 'dns-out' &&
            rule['port'] == '53' &&
            (rule['inboundTag'] as List?)?.contains('tun') == true,
      ),
      isTrue,
    );
  });

  test('SOCKS authentication can be disabled', () {
    final socks = inboundsOf(
      configFor(
        const Settings(
          tunnelMode: TunnelMode.tunProxy,
          socksPort: 23456,
          socksAuth: false,
        ),
      ),
    ).firstWhere((inbound) => inbound['tag'] == 'socks');
    final settings = socks['settings'] as Map<String, dynamic>;
    expect(settings['auth'], 'noauth');
    expect(settings.containsKey('accounts'), isFalse);
  });
}
