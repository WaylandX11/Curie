import 'dart:convert';

import 'package:curie_windows/src/models/settings.dart';
import 'package:curie_windows/src/services/xray_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serverOutbound = <String, dynamic>{
    'tag': 'proxy',
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {'address': 'example.com', 'port': 443},
      ],
    },
  };

  Map<String, dynamic> build() {
    final json = buildXrayConfig(outbounds: [serverOutbound]);
    return jsonDecode(json) as Map<String, dynamic>;
  }

  test('TUN inbound is present and fd is left to the platform', () {
    final config = build();
    final inbounds = (config['inbounds'] as List).cast<Map<String, dynamic>>();

    expect(inbounds, hasLength(1));
    expect(inbounds.single['protocol'], 'tun');
    expect(inbounds.single['tag'], 'tun');
    // Без имени Xray вызывает net.Interfaces() и падает на Android.
    expect((inbounds.single['settings'] as Map)['name'], isNotEmpty);
    expect(config.containsKey('env'), isFalse,
        reason: 'xray.tun.fd подставляет Kotlin, Dart его не знает');
  });

  test('server outbound comes first, direct and dns-out are appended', () {
    final outbounds = (build()['outbounds'] as List).cast<Map<String, dynamic>>();

    expect(outbounds.map((o) => o['tag']).toList(), ['proxy', 'direct', 'dns-out']);
    expect(outbounds.last['protocol'], 'dns');
  });

  test('DNS from the tunnel is handled before the private-network rule', () {
    final routing = build()['routing'] as Map<String, dynamic>;
    final rules = (routing['rules'] as List).cast<Map<String, dynamic>>();

    expect(rules.first['outboundTag'], 'dns-out');
    expect(rules.first['port'], '53');
    expect(rules.first['inboundTag'], ['tun']);
    expect(rules[1]['outboundTag'], 'direct');
    expect((rules[1]['ip'] as List), contains('192.168.0.0/16'));
  });

  test('no geo files are required by the default rules', () {
    final json = buildXrayConfig(outbounds: [serverOutbound]);
    expect(json.contains('geoip:'), isFalse);
    expect(json.contains('geosite:'), isFalse);
  });

  test('settings change DNS, MTU and the local-network rule', () {
    final config = buildXrayConfig(
      outbounds: [serverOutbound],
      settings: const Settings(dns: '9.9.9.9', mtu: 1400, bypassLan: false),
    );
    final json = jsonDecode(config) as Map<String, dynamic>;

    final servers = (json['dns'] as Map)['servers'] as List;
    expect((servers.first as Map)['address'], '9.9.9.9');
    expect(servers.length, 2, reason: 'второй сервер — запасной');

    final inbounds = (json['inbounds'] as List).cast<Map<String, dynamic>>();
    expect((inbounds.single['settings'] as Map)['mtu'], 1400);

    final rules = ((json['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules.length, 1, reason: 'обход локальной сети выключен');
    expect(rules.single['outboundTag'], 'dns-out');
  });

  test('panel routing, balancers and observatory survive TUN rebuild', () {
    final base = {
      'dns': {'servers': ['1.1.1.1'], 'queryStrategy': 'UseIPv4'},
      'routing': {
        'rules': [
          {'type': 'field', 'domain': ['full:gosuslugi.ru'], 'outboundTag': 'direct'},
          {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'Germany_Balancer'},
        ],
        'balancers': [
          {'tag': 'Germany_Balancer', 'selector': ['proxy']},
        ],
      },
      'burstObservatory': {'subjectSelector': ['proxy']},
      'inbounds': [
        {'tag': 'socks', 'protocol': 'socks', 'port': 10808},
      ],
      'outbounds': [
        serverOutbound,
        {'tag': 'direct', 'protocol': 'freedom'},
      ],
    };

    final json = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound, {'tag': 'direct', 'protocol': 'freedom'}],
      base: base,
    )) as Map<String, dynamic>;

    expect((json['routing'] as Map)['balancers'], isNotEmpty);
    final rules = ((json['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules.length, 3, reason: 'правило DNS добавляется к правилам панели');
    expect(rules.first['outboundTag'], 'dns-out');
    expect(rules.last['balancerTag'], 'Germany_Balancer');
    expect(json['burstObservatory'], isNotNull);
    // Маршрутизацию панели сохраняем; DNS теперь тоже берём из подписки.
    expect(((json['dns'] as Map)['servers'] as List).first,
        {'address': '1.1.1.1', 'tag': 'proxy'});
    expect((json['inbounds'] as List).length, 1, reason: 'socks панели не нужен');
  });

  test('metrics are enabled for the speed indicator', () {
    final json = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      metricsPort: 49100,
    )) as Map<String, dynamic>;

    expect((json['metrics'] as Map)['listen'], '127.0.0.1:49100');
    expect(json['stats'], isEmpty);
    final system = ((json['policy'] as Map)['system'] as Map);
    expect(system['statsOutboundUplink'], isTrue);
    expect(system['statsOutboundDownlink'], isTrue);
  });

  test('without a subscription DNS the fallback address is used', () {
    final servers = (build()['dns'] as Map)['servers'] as List;
    expect((servers.first as Map)['address'], '77.88.8.8');
    expect((servers.first as Map)['tag'], 'proxy');
    expect((servers.last as Map)['address'], '8.8.8.8');
  });

  test('the subscription DNS is used by default', () {
    final json = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      base: {
        'dns': {'servers': ['1.1.1.1']},
      },
    )) as Map<String, dynamic>;
    final servers = (json['dns'] as Map)['servers'] as List;
    expect((servers.first as Map)['address'], '1.1.1.1');
  });

  test('an explicitly chosen DNS overrides the subscription', () {
    final json = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      settings: const Settings(dns: '9.9.9.9', dnsUsePanel: false),
      base: {
        'dns': {'servers': ['1.1.1.1']},
      },
    )) as Map<String, dynamic>;
    final servers = (json['dns'] as Map)['servers'] as List;
    expect((servers.first as Map)['address'], '9.9.9.9');
    expect((servers.first as Map)['tag'], 'proxy');
  });

  test('custom DNS equal to the fallback is not duplicated', () {
    final config = buildXrayConfig(
      outbounds: [serverOutbound],
      settings: const Settings(dns: '8.8.8.8'),
    );
    final json = jsonDecode(config) as Map<String, dynamic>;
    expect(((json['dns'] as Map)['servers'] as List).length, 1);
  });

  test('TUN sniffing makes panel domain rules actually match', () {
    final json = build();
    final tun = (json['inbounds'] as List).single;
    final sniffing = (tun['sniffing'] as Map).cast<String, dynamic>();
    expect(sniffing['enabled'], isTrue);
    expect(sniffing['destOverride'], contains('tls'));
    // Подменяем адрес и для dial: direct должен открывать домен, а не IP,
    // полученный через вышестоящий DNS прокси.
    expect(sniffing['routeOnly'], isFalse);
  });

  test('DNS can be routed directly when UDP DNS through the proxy is unwanted', () {
    final json = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      settings: const Settings(dnsRoute: DnsRoute.direct),
    )) as Map<String, dynamic>;
    final servers = (json['dns'] as Map)['servers'] as List;
    expect((servers.first as Map)['tag'], 'direct');
  });

  test('local check proxy is routed through the server outbounds', () {
    final json = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      metricsPort: 49100,
      checkPort: 49101,
    )) as Map<String, dynamic>;
    final inbounds = (json['inbounds'] as List).cast<Map<String, dynamic>>();
    expect(inbounds.length, 2);
    final check = inbounds.last;
    expect(check['tag'], 'check');
    expect(check['listen'], '127.0.0.1');
    expect(check['port'], 49101);
    final rules = ((json['routing'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();
    expect(rules.first['inboundTag'], ['check']);
    expect(rules.first['outboundTag'], 'proxy');
  });

  const fallbackOutbound = <String, dynamic>{
    'tag': 'proxy',
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {'address': 'y.six-seven.icu', 'port': 443},
      ],
    },
  };
  const primaryOutbound = <String, dynamic>{
    'tag': 'proxy-2',
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {'address': 'serv.six-seven.icu', 'port': 443},
      ],
    },
  };

  test('a config with a fallback host gets an auto balancer with fallbackTag',
      () {
    final config = jsonDecode(buildXrayConfig(
      outbounds: [fallbackOutbound, primaryOutbound],
      base: {
        'remarks': 'Обход БС',
        'burstObservatory': {'subjectSelector': ['proxy']},
      },
      checkPort: 49101,
    )) as Map<String, dynamic>;

    final routing = config['routing'] as Map<String, dynamic>;
    final balancers = (routing['balancers'] as List).cast<Map<String, dynamic>>();
    expect(balancers.single['selector'], ['proxy-2']);
    expect(balancers.single['fallbackTag'], 'proxy');

    final rules = (routing['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules.last['balancerTag'], 'curie-auto-balancer');
    expect(rules.first['outboundTag'], 'proxy-2',
        reason: 'проверка и DNS идут через рабочий сервер, не через fallback');
    final dnsServers =
        ((config['dns'] as Map)['servers'] as List).cast<Map<String, dynamic>>();
    expect(dnsServers.first['tag'], 'proxy-2');
    expect(config['burstObservatory'], isNotNull);
  });

  test('a panel balancer without fallbackTag gets one', () {
    final config = jsonDecode(buildXrayConfig(
      outbounds: [fallbackOutbound, primaryOutbound],
      base: {
        'routing': {
          'rules': [
            {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'balance'},
          ],
          'balancers': [
            {'tag': 'balance', 'selector': ['proxy-']},
          ],
        },
        'burstObservatory': {'subjectSelector': ['proxy']},
      },
    )) as Map<String, dynamic>;

    final routing = config['routing'] as Map<String, dynamic>;
    final balancers = (routing['balancers'] as List).cast<Map<String, dynamic>>();
    expect(balancers.single['fallbackTag'], 'proxy');
    expect(
      (routing['rules'] as List).whereType<Map>().any(
            (rule) => rule['balancerTag'] == 'curie-auto-balancer',
          ),
      isFalse,
      reason: 'панельный балансировщик уже подключён правилом',
    );
  });

  test('explicit panel domainStrategy is never overridden', () {
    final config = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      base: {
        'routing': {
          'domainStrategy': 'IpOnDemand',
          'rules': [
            {
              'type': 'field',
              'ip': ['1.2.3.0/24'],
              'outboundTag': 'direct',
            },
          ],
        },
      },
    )) as Map<String, dynamic>;
    expect((config['routing'] as Map)['domainStrategy'], 'IpOnDemand');
  });

  test('panel direct rules are kept before the catch-all balancer', () {
    // Структура из подписки пользователя: белые списки заданы доменами и
    // CIDR, domainStrategy в панели не указана, балансировщика нет.
    final base = {
      'dns': {
        'servers': ['77.88.8.8', '8.8.8.8', '1.1.1.1', '9.9.9.9'],
        'queryStrategy': 'UseIPv4',
      },
      'routing': {
        'rules': [
          {
            'type': 'field',
            'domain': [r'regexp:.*\.ru$', 'domain:vk.com', 'full:mos.ru'],
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'ip': ['84.201.173.203/32', '77.88.8.8/32'],
            'outboundTag': 'direct',
          },
        ],
      },
      'burstObservatory': {'subjectSelector': ['proxy']},
    };

    final config = jsonDecode(buildXrayConfig(
      outbounds: [
        fallbackOutbound,
        primaryOutbound,
        const {'tag': 'direct', 'protocol': 'freedom'},
        const {'tag': 'block', 'protocol': 'blackhole'},
      ],
      base: base,
      checkPort: 49101,
    )) as Map<String, dynamic>;

    final routing = config['routing'] as Map<String, dynamic>;
    // Без IpIfNonMatch IP-правила не проверялись бы для доменных соединений.
    expect(routing['domainStrategy'], 'IpIfNonMatch');

    final rules = (routing['rules'] as List).cast<Map<String, dynamic>>();
    final directRules =
        rules.where((rule) => rule['outboundTag'] == 'direct').toList();
    expect(directRules, hasLength(2));
    expect(directRules.first['domain'], [
      r'regexp:.*\.ru$',
      'domain:vk.com',
      'full:mos.ru',
    ]);
    expect(directRules.last['ip'], ['84.201.173.203/32', '77.88.8.8/32']);

    final balancerIndex =
        rules.indexWhere((rule) => rule['balancerTag'] == 'curie-auto-balancer');
    final lastDirect =
        rules.lastIndexWhere((rule) => rule['outboundTag'] == 'direct');
    expect(balancerIndex, greaterThan(-1));
    expect(lastDirect, lessThan(balancerIndex),
        reason: 'catch-all балансировщик не должен перехватывать белые списки');

    final balancers = (routing['balancers'] as List).cast<Map<String, dynamic>>();
    expect(balancers.single['selector'], ['proxy-2']);
    expect(balancers.single['fallbackTag'], 'proxy');
    expect((balancers.single['strategy'] as Map)['settings'], isEmpty);

    final tun = (config['inbounds'] as List).first;
    expect((tun['sniffing'] as Map)['routeOnly'], isFalse);
    final dnsServers =
        ((config['dns'] as Map)['servers'] as List).cast<Map<String, dynamic>>();
    expect(dnsServers.first['tag'], 'proxy-2');
    expect(
      (config['outbounds'] as List).map((o) => o['tag']),
      contains('direct'),
    );
  });

  test('Xray logs use logLevel and a masked private file', () {
    const path = '/data/user/0/io.github.waylandx11.curie/files/curie-xray.log';
    final config = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      settings: const Settings(
        xrayLogEnabled: true,
        xrayLogLevel: XrayLogLevel.debug,
      ),
      logPath: path,
    )) as Map<String, dynamic>;
    final log = (config['log'] as Map).cast<String, dynamic>();

    expect(log['logLevel'], 'debug', reason: 'Xray ignores lowercase loglevel');
    expect(log['error'], path);
    expect(log['access'], 'none');
    expect(
      log['maskAddress'],
      'full',
      reason: 'Xray parsing expects a mask string, not a bool',
    );
  });

  test('disabled or pathless logging writes nothing', () {
    final disabled = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
      settings: const Settings(xrayLogEnabled: false),
      logPath: '/some/path',
    )) as Map<String, dynamic>;
    expect((disabled['log'] as Map)['logLevel'], 'none');
    expect((disabled['log'] as Map)['error'], 'none');

    final noPath = jsonDecode(buildXrayConfig(
      outbounds: [serverOutbound],
    )) as Map<String, dynamic>;
    expect((noPath['log'] as Map)['error'], 'none');
  });
}
