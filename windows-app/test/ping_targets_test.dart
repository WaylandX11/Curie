import 'dart:convert';

import 'package:curie_windows/src/models/profile.dart';
import 'package:curie_windows/src/services/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const proxyA = <String, dynamic>{
    'tag': 'proxy-a',
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {'address': 'a.example.com', 'port': 443},
      ],
    },
    'streamSettings': {
      'security': 'tls',
      'tlsSettings': {
        'serverName': 'cdn.example.com',
        'alpn': ['h2', 'http/1.1'],
      },
    },
  };
  const proxyB = <String, dynamic>{
    'tag': 'proxy-b',
    'protocol': 'trojan',
    'settings': {
      'servers': [
        {'address': 'b.example.com', 'port': 8443},
      ],
    },
  };
  const direct = <String, dynamic>{'tag': 'direct', 'protocol': 'freedom'};

  Profile balancer(List<String> selector, List<Map<String, dynamic>> outbounds) =>
      Profile(
        name: 'Balancer',
        configJson: jsonEncode({
          'outbounds': outbounds,
          'routing': {
            'balancers': [
              {'tag': 'balance', 'selector': selector},
            ],
          },
        }),
        hasBalancer: true,
      );

  test('balancer pings every server under its selector', () async {
    final plan = await pingTargetsFor(
      balancer(['proxy'], [proxyA, proxyB, direct]),
    );

    expect(
      plan.targets.map((target) => target.address),
      ['a.example.com', 'b.example.com'],
    );
    expect(plan.targets.first.security, 'tls');
    expect(plan.targets.first.serverName, 'cdn.example.com');
    expect(plan.targets.first.alpn, ['h2', 'http/1.1']);
    expect(plan.targets.last.isTls, isFalse);
  });

  test('balancer selector matches tags by prefix', () async {
    const germanyA = <String, dynamic>{
      'tag': 'Germany-A',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'de1.example.com', 'port': 443},
        ],
      },
    };
    const germanyB = <String, dynamic>{
      'tag': 'Germany-B',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'de2.example.com', 'port': 443},
        ],
      },
    };
    const netherlands = <String, dynamic>{
      'tag': 'netherlands',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'nl.example.com', 'port': 443},
        ],
      },
    };

    final plan = await pingTargetsFor(
      balancer(['Germany'], [germanyA, germanyB, netherlands, direct]),
    );

    expect(
      plan.targets.map((target) => target.address),
      ['de1.example.com', 'de2.example.com'],
    );
  });

  test('a regular node pings only its primary outbound', () async {
    final profile = Profile(
      name: 'Node',
      configJson: jsonEncode({
        'outbounds': [proxyA, proxyB, direct],
      }),
      hasBalancer: false,
    );

    final plan = await pingTargetsFor(profile);
    expect(plan.targets.single.address, 'a.example.com');
  });

  test('a balancer without matching tags falls back to the first server', () async {
    final plan = await pingTargetsFor(
      balancer(['missing'], [proxyA, proxyB, direct]),
    );

    expect(plan.targets.single.address, 'a.example.com');
  });

  test('pingBatch items keep outboundTag outside xrayJson', () async {
    final plan = await pingTargetsFor(
      balancer(['proxy'], [proxyA, proxyB, direct]),
    );
    final item = pingBatchItem(plan, plan.targets.last);

    expect(item['outboundTag'], 'proxy-b');
    final config = jsonDecode(item['xrayJson'] as String) as Map;
    expect(config.containsKey('outboundTag'), isFalse);
    expect((config['outbounds'] as List), hasLength(3));
  });

  test('Remnawave fallback is measured after the numbered primary servers',
      () async {
    // Пример из подписки: `proxy` — запасной хост, `proxy-2` — рабочий.
    const fallback = <String, dynamic>{
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'y.six-seven.icu', 'port': 443},
        ],
      },
    };
    const primary = <String, dynamic>{
      'tag': 'proxy-2',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'serv.six-seven.icu', 'port': 443},
        ],
      },
    };
    final profile = Profile(
      name: 'Обход БС',
      configJson: jsonEncode({
        'outbounds': [fallback, primary, direct],
        'burstObservatory': {'subjectSelector': ['proxy']},
      }),
    );

    final plan = await pingTargetsFor(profile);

    expect(plan.targets.map((t) => t.address), [
      'serv.six-seven.icu',
      'y.six-seven.icu',
    ]);
    expect(plan.targets.map((t) => t.fallback), [false, true]);
  });

  test('explicit balancer fallbackTag is kept as a fallback target', () async {
    const fallback = <String, dynamic>{
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'fallback.example.com', 'port': 443},
        ],
      },
    };
    const primary = <String, dynamic>{
      'tag': 'proxy-2',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'primary.example.com', 'port': 443},
        ],
      },
    };
    final profile = Profile(
      name: 'Balancer',
      configJson: jsonEncode({
        'outbounds': [fallback, primary, direct],
        'routing': {
          'balancers': [
            {
              'tag': 'balance',
              'selector': ['proxy-'],
              'fallbackTag': 'proxy',
            },
          ],
        },
      }),
    );

    final plan = await pingTargetsFor(profile);

    expect(plan.targets.map((t) => t.address), [
      'primary.example.com',
      'fallback.example.com',
    ]);
    expect(plan.targets.map((t) => t.fallback), [false, true]);
  });

  test('duplicate address and port are measured once', () async {
    const same = <String, dynamic>{
      'tag': 'proxy-copy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {'address': 'a.example.com', 'port': 443},
        ],
      },
    };

    final plan = await pingTargetsFor(
      balancer(['proxy'], [proxyA, same, direct]),
    );

    expect(plan.targets, hasLength(1));
  });
}
