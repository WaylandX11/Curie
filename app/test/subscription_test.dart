import 'dart:convert';
import 'dart:io';

import 'package:curie/src/models/profile.dart';
import 'package:curie/src/models/subscription.dart';
import 'package:curie/src/services/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractLinks', () {
    test('plain list, comments and duplicates are handled', () {
      const body = '''
# profile-title: Curie
vless://a@host:443#One

vless://a@host:443#One
trojan://b@host:443#Two
not a link
''';
      expect(SubscriptionService.extractLinks(body), [
        'vless://a@host:443#One',
        'trojan://b@host:443#Two',
      ]);
    });

    test('base64 subscription wrapper is decoded', () {
      const text = 'vless://a@host:443#One\nss://abc@host:8388#Two';
      final body = base64Encode(utf8.encode(text));
      expect(SubscriptionService.extractLinks(body), [
        'vless://a@host:443#One',
        'ss://abc@host:8388#Two',
      ]);
    });

    test('url-safe base64 without padding is decoded', () {
      const text = 'vless://a@host:443?encryption=none&security=tls#One';
      final body = base64Url
          .encode(utf8.encode(text))
          .replaceAll('=', '')
          .replaceAll('\n', '');
      expect(SubscriptionService.extractLinks(body), [text]);
    });

    test('garbage yields nothing', () {
      expect(SubscriptionService.extractLinks('   '), isEmpty);
      expect(SubscriptionService.extractLinks('<html>error</html>'), isEmpty);
    });
  });

  group('JSON request URL', () {
    test('adds the explicit /json suffix to a bare subscription URL', () {
      expect(
        SubscriptionService.requestUri('https://sub.example.com/abc123').toString(),
        'https://sub.example.com/abc123/json',
      );
    });

    test('keeps URLs that already choose a format', () {
      for (final url in [
        'https://sub.example.com/abc123/json',
        'https://sub.example.com/abc123/clash',
        'https://sub.example.com/abc123/v2ray-json',
        'https://sub.example.com/abc123?token=1',
      ]) {
        expect(SubscriptionService.requestUri(url).toString(), url);
      }
    });

    test('handles a trailing slash and does not change the stored URL', () {
      const url = 'https://sub.example.com/abc123/';
      expect(SubscriptionService.requestUri(url).path, '/abc123/json');
      expect(Uri.parse(url).path, '/abc123/');
    });
  });

  group('subscription link for other clients', () {
    test('shareUrl strips the /json suffix Curie adds for itself', () {
      expect(
        const Subscription(
          url: 'https://panel.example.com/abc/json',
          title: 'Panel',
        ).shareUrl,
        'https://panel.example.com/abc',
      );
      expect(
        const Subscription(
          url: 'https://panel.example.com/abc',
          title: 'Panel',
        ).shareUrl,
        'https://panel.example.com/abc',
      );
      expect(
        const Subscription(
          url: 'https://panel.example.com/abc/json?token=1',
          title: 'Panel',
        ).shareUrl,
        'https://panel.example.com/abc?token=1',
      );
      expect(
        const Subscription(
          url: 'https://panel.example.com/abc/v2ray-json',
          title: 'Panel',
        ).shareUrl,
        'https://panel.example.com/abc',
      );
      expect(
        const Subscription(
          url: 'https://panel.example.com/abc',
          title: 'Panel',
        ).shareUrl,
        'https://panel.example.com/abc',
      );
    });
  });

  test('the panel update interval is stored with the subscription', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response.headers
        ..set('content-type', 'application/json')
        ..set('profile-update-interval', '6');
      request.response.write(jsonEncode([
        {
          'remarks': 'Node',
          'outbounds': [
            {'tag': 'proxy', 'protocol': 'vless'},
          ],
        },
      ]));
      request.response.close();
    });

    final loaded = await const SubscriptionService().refresh(
      Subscription(url: 'http://127.0.0.1:${server.port}/sub', title: 'Panel'),
      userAgent: 'Curie/test',
    );

    expect(loaded.updateIntervalHours, 6);
    expect(loaded.nodes, hasLength(1));
  });

  group('subscription edits', () {
    test('a manual node edit survives a subscription refresh', () {
      final node = Profile(
        name: 'Original',
        configJson: '{"outbounds":[{"tag":"proxy","protocol":"vless"}]}',
        subscriptionUrl: 'https://sub.example.com/abc',
      );
      final edited = node.copyWith(name: 'Renamed');
      final subscription = Subscription(
        url: 'https://sub.example.com/abc',
        title: 'Test',
        nodes: [node],
        edits: {node.id: edited.toJson()},
      );

      expect(subscription.applyEdit(node).name, 'Renamed');
      expect(subscription.applyEdit(node).subscriptionUrl, node.subscriptionUrl);
      expect(
        Subscription.fromJson(subscription.toJson()).applyEdit(node).name,
        'Renamed',
      );
    });
  });

  group('SubscriptionInfo', () {
    test('parses the panel header', () {
      final info = SubscriptionInfo.parse(
        'upload=1024; download=2048; total=10485760; expire=1893456000',
      )!;

      expect(info.used, 3072);
      expect(info.total, 10485760);
      expect(info.usageRatio, closeTo(3072 / 10485760, 1e-9));
      expect(info.expire!.year, 2030);
      expect(info.isExpired, isFalse);
    });

    test('zero total means unlimited', () {
      final info = SubscriptionInfo.parse('upload=1; download=2; total=0; expire=0')!;
      expect(info.usageRatio, isNull);
      expect(info.expire, isNull);
    });

    test('missing header is not an error', () {
      expect(SubscriptionInfo.parse(null), isNull);
      expect(SubscriptionInfo.parse(''), isNull);
    });
  });

  test('subscription is stale until updated', () {
    const fresh = Subscription(url: 'https://panel/sub', title: 'Panel');
    expect(fresh.isStale, isTrue);

    final updated = fresh.copyWith(updatedAt: DateTime.now(), updateIntervalHours: 12);
    expect(updated.isStale, isFalse);

    final old = fresh.copyWith(
      updatedAt: DateTime.now().subtract(const Duration(hours: 13)),
    );
    expect(old.isStale, isTrue);
  });

  test('subscription survives a storage round trip', () {
    final subscription = Subscription(
      url: 'https://panel/sub',
      title: 'Panel',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      info: SubscriptionInfo.parse('upload=1; download=2; total=3; expire=0'),
      updateIntervalHours: 6,
      expanded: true,
    );
    final restored = Subscription.fromJson(subscription.toJson());

    expect(restored.url, subscription.url);
    expect(restored.title, subscription.title);
    expect(restored.updatedAt, subscription.updatedAt);
    expect(restored.info!.used, 3);
    expect(restored.updateIntervalHours, 6);
    expect(restored.expanded, isTrue);
  });
}
