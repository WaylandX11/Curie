import 'dart:convert';

import 'package:curie_windows/src/services/subscription_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const outbound = {
    'tag': 'proxy',
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {
          'address': 'nl.example.com',
          'port': 443,
          'users': [
            {'id': 'uuid', 'encryption': 'none'},
          ],
        },
      ],
    },
    'streamSettings': {'network': 'xhttp', 'security': 'tls'},
  };

  group('JSON subscription', () {
    test('array of configs with remarks (XTLS standard)', () {
      final body = jsonEncode([
        {'remarks': '🇳🇱 Нидерланды', 'outbounds': [outbound]},
        {'remarks': '🇩🇪 Германия', 'outbounds': [outbound]},
      ]);

      final nodes = SubscriptionParser.parseJson(body, subscriptionUrl: 'https://panel/sub');

      expect(nodes.length, 2);
      expect(nodes.first.name, '🇳🇱 Нидерланды');
      expect(nodes.first.isJson, isTrue);
      expect(nodes.first.address, 'nl.example.com');
      expect(nodes.first.port, 443);
      expect(nodes.first.protocol, 'vless');
      expect(nodes.first.network, 'xhttp');
      expect(nodes.first.security, 'tls');
      expect(nodes.first.chips, ['VLESS', 'XHTTP', 'TLS', 'JSON']);
    });

    test('bare outbounds object: every proxy outbound is a node', () {
      final body = jsonEncode({
        'outbounds': [
          outbound,
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
      });

      final nodes = SubscriptionParser.parseJson(body);
      expect(nodes.length, 1);
      expect(nodes.single.name, 'proxy');
    });

    test('full config with routing stays one node', () {
      final body = jsonEncode({
        'remarks': 'Обход БС',
        'routing': {'rules': []},
        'outbounds': [outbound, {'tag': 'direct', 'protocol': 'freedom'}],
      });

      final nodes = SubscriptionParser.parseJson(body);
      expect(nodes.length, 1);
      expect(nodes.single.name, 'Обход БС');
      expect(SubscriptionParser.outboundsOf(nodes.single).length, 2);
    });

    test('full config with a balancer keeps routing and observatory', () {
      final body = jsonEncode({
        'remarks': '🇩🇪 📡 Германия',
        'dns': {'servers': ['1.1.1.1'], 'queryStrategy': 'UseIPv4'},
        'routing': {
          'rules': [
            {'type': 'field', 'domain': ['full:gosuslugi.ru'], 'outboundTag': 'direct'},
            {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'Germany_Balancer'},
          ],
          'balancers': [
            {
              'tag': 'Germany_Balancer',
              'selector': ['proxy'],
              'strategy': {'type': 'leastLoad'},
            },
          ],
        },
        'burstObservatory': {'subjectSelector': ['proxy']},
        'inbounds': [
          {'tag': 'socks', 'protocol': 'socks', 'port': 10808},
        ],
        'outbounds': [
          outbound,
          {
            'tag': 'proxy-2',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': 'de2.example.com',
                  'port': 443,
                  'users': [
                    {'id': 'uuid'},
                  ],
                },
              ],
            },
          },
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
      });

      final nodes = SubscriptionParser.parseJson(body);
      expect(nodes, hasLength(1));
      final node = nodes.single;
      expect(node.name, '🇩🇪 📡 Германия');
      expect(node.hasBalancer, isTrue);
      expect(node.chips, isNot(contains('BALANCER')));

      // Узел хранится целиком: балансеру нужны оба outbound'а и правила.
      final stored = jsonDecode(node.configJson!) as Map<String, dynamic>;
      expect((stored['routing'] as Map)['balancers'], isNotEmpty);
      expect((stored['burstObservatory'] as Map)['subjectSelector'], ['proxy']);
      expect(SubscriptionParser.outboundsOf(node).length, 3);
    });

    test('id is stable across updates of the same node', () {
      final first = SubscriptionParser.parseJson(
        jsonEncode([{'remarks': 'Node', 'outbounds': [outbound]}]),
        subscriptionUrl: 'https://panel/sub',
      ).single;
      final second = SubscriptionParser.parseJson(
        jsonEncode([{'remarks': 'Node', 'outbounds': [outbound]}]),
        subscriptionUrl: 'https://panel/sub',
      ).single;

      expect(first.id, second.id);
    });

    test('garbage and empty configs yield nothing', () {
      expect(SubscriptionParser.parseJson('не json'), isEmpty);
      expect(SubscriptionParser.parseJson('{"outbounds":[]}'), isEmpty);
      expect(SubscriptionParser.parseJson('[]'), isEmpty);
    });
  });

  group('headers', () {
    test('base64 title and announce are decoded', () {
      final title = base64Encode(utf8.encode('Окно в цифровой мир'));
      expect(SubscriptionParser.decodeHeader('base64:$title'), 'Окно в цифровой мир');
      expect(SubscriptionParser.decodeHeader('Plain title'), 'Plain title');
      expect(SubscriptionParser.decodeHeader(null), isNull);
    });
  });
}
