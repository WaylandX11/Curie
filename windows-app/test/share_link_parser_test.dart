import 'dart:convert';

import 'package:curie_windows/src/services/share_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a VLESS WebSocket over TLS link', () {
    final outbound = ShareLinkParser.parse(
      'vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443'
      '?type=ws&security=tls&host=cdn.example.com&path=%2Fchat'
      '&sni=tls.example.com&alpn=h2%2Chttp%2F1.1#Node',
    );

    expect(outbound, isNotNull);
    expect(outbound!['protocol'], 'vless');
    expect(outbound['tag'], 'Node');

    final vnext = (outbound['settings'] as Map)['vnext'] as List;
    final server = vnext.single as Map;
    expect(server['address'], 'example.com');
    expect(server['port'], 443);
    expect((server['users'] as List).single['id'],
        'b831381d-6324-4d53-ad4f-8cda48b30811');

    final stream = outbound['streamSettings'] as Map;
    expect(stream['network'], 'ws');
    expect(stream['security'], 'tls');
    expect((stream['tlsSettings'] as Map)['serverName'], 'tls.example.com');
    expect((stream['tlsSettings'] as Map)['alpn'], ['h2', 'http/1.1']);
    expect((stream['wsSettings'] as Map)['path'], '/chat');
    expect(((stream['wsSettings'] as Map)['headers'] as Map)['Host'],
        'cdn.example.com');
  });

  test('parses a VMess link without lowercasing its base64 payload', () {
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'v': '2',
      'ps': 'VMess Node',
      'add': 'vm.example.com',
      'port': '443',
      'id': 'b831381d-6324-4d53-ad4f-8cda48b30811',
      'aid': '0',
      'net': 'tcp',
      'tls': 'tls',
      'sni': 'tls.example.com',
    })));

    final outbound = ShareLinkParser.parse('vmess://$payload');

    expect(outbound, isNotNull);
    expect(outbound!['protocol'], 'vmess');
    expect(outbound['tag'], 'VMess Node');
    final server = ((outbound['settings'] as Map)['vnext'] as List).single as Map;
    expect(server['address'], 'vm.example.com');
    expect(server['port'], 443);
    expect((server['users'] as List).single['id'],
        'b831381d-6324-4d53-ad4f-8cda48b30811');
    final stream = outbound['streamSettings'] as Map;
    expect(stream['security'], 'tls');
    expect((stream['tlsSettings'] as Map)['serverName'], 'tls.example.com');
  });

  test('parses a Shadowsocks link and ignores unknown schemes', () {
    final credentials = base64Url.encode(utf8.encode('aes-256-gcm:p@ss'));
    final outbound = ShareLinkParser.parse(
      'ss://$credentials@ss.example.com:8388#SS',
    );

    expect(outbound, isNotNull);
    expect(outbound!['protocol'], 'shadowsocks');
    final server = ((outbound['settings'] as Map)['servers'] as List).single as Map;
    expect(server['address'], 'ss.example.com');
    expect(server['port'], 8388);
    expect(server['method'], 'aes-256-gcm');
    expect(server['password'], 'p@ss');

    expect(ShareLinkParser.parse('https://example.com/not-a-proxy'), isNotNull);
    expect(ShareLinkParser.parse('ftp://example.com'), isNull);
  });

  test('assigns unique tags when several links arrive in one text', () {
    final outbounds = ShareLinkParser.parseText([
      'trojan://pwd@example.com:443#First',
      'trojan://pwd@example.org:443#Second',
    ].join('\n'));

    expect(outbounds.map((e) => e['tag']).toList(), ['proxy', 'proxy-2']);
  });
}
