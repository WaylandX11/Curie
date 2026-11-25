import 'dart:convert';

/// Разбор share-ссылок в outbound'ы Xray.
///
/// В Android-версии это делает libXray (`convertShareLinksToXrayJson`). На
/// Windows используется официальный `xray.exe`, у которого нет этого метода,
/// поэтому镁 converter живёт на Dart: поддерживаются протоколы, которые
/// умеет импортер Curie (VLESS, VMess, Trojan, Shadowsocks, SOCKS, Hysteria2).
class ShareLinkParser {
  static List<Map<String, dynamic>> parseText(String text) {
    final outbounds = <Map<String, dynamic>>[];
    for (final raw in text.split(RegExp(r'[\r\n\s]+'))) {
      final link = raw.trim();
      if (link.isEmpty) continue;
      final outbound = parse(link);
      if (outbound != null) outbounds.add(outbound);
    }
    if (outbounds.length > 1) {
      for (var i = 0; i < outbounds.length; i++) {
        outbounds[i]['tag'] = i == 0 ? 'proxy' : 'proxy-${i + 1}';
      }
    }
    return outbounds;
  }

  static Map<String, dynamic>? parse(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    return switch (scheme) {
      'vless' => _vless(uri),
      'vmess' => _vmess(uri, link.trim()),
      'trojan' => _trojan(uri),
      'ss' => _shadowsocks(uri),
      'socks' || 'socks5' => _socks(uri),
      'http' || 'https' => _http(uri),
      'hysteria2' || 'hy2' => _hysteria2(uri),
      _ => null,
    };
  }

  static Map<String, dynamic>? _vless(Uri uri) {
    final address = uri.host;
    final port = uri.port;
    final id = uri.userInfo;
    if (address.isEmpty || port <= 0 || id.isEmpty) return null;

    final q = uri.queryParameters;
    final network = (q['type'] ?? 'tcp').toLowerCase();
    final security = (q['security'] ?? 'none').toLowerCase();
    final name = _name(uri);

    return {
      'protocol': 'vless',
      'tag': name,
      'settings': {
        'vnext': [
          {
            'address': address,
            'port': port,
            'users': [
              {
                'id': id,
                'level': 0,
                'encryption': q['encrypt'] ?? 'none',
                if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
              },
            ],
          },
        ],
      },
      'streamSettings': _stream(
        network: network,
        security: security,
        query: q,
        fallbackHost: address,
      ),
    };
  }

  static Map<String, dynamic>? _vmess(Uri uri, String link) {
    // Не берём uri.host: Uri нормализует хост к нижнему регистру, а base64
    // регистрозависим — VMess-ссылка из-за этого разбиралась неверно.
    final encoded = link
        .substring('vmess://'.length)
        .split(RegExp(r'[?#]'))
        .first;
    final decoded = _decodeBase64(encoded);
    if (decoded == null) return null;
    final Object? json;
    try {
      json = jsonDecode(decoded);
    } on Object {
      return null;
    }
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final address = (map['add'] as String?)?.trim() ?? '';
    final port = map['port'];
    final id = (map['id'] as String?)?.trim() ?? '';
    if (address.isEmpty || id.isEmpty) return null;

    final network = ((map['net'] as String?) ?? 'tcp').toLowerCase();
    final security = ((map['tls'] as String?) ?? 'none').toLowerCase();
    final query = <String, String>{
      'host': (map['host'] as String?) ?? '',
      'path': (map['path'] as String?) ?? '',
      'sni': (map['sni'] as String?) ?? '',
      'alpn': (map['alpn'] as String?) ?? '',
      'fp': (map['fp'] as String?) ?? '',
      'type': network,
      'security': security,
    };

    return {
      'protocol': 'vmess',
      'tag': _name(uri, fallback: map['ps'] as String?),
      'settings': {
        'vnext': [
          {
            'address': address,
            'port': port is int ? port : int.tryParse(port.toString()) ?? 443,
            'users': [
              {
                'id': id,
                'level': 0,
                'aid': int.tryParse(map['aid']?.toString() ?? '0') ?? 0,
                'security': (map['scy'] as String?) ?? 'auto',
              },
            ],
          },
        ],
      },
      'streamSettings': _stream(
        network: network,
        security: security,
        query: query,
        fallbackHost: address,
      ),
    };
  }

  static Map<String, dynamic>? _trojan(Uri uri) {
    final address = uri.host;
    final port = uri.port;
    final password = uri.userInfo;
    if (address.isEmpty || port <= 0 || password.isEmpty) return null;

    final q = uri.queryParameters;
    return {
      'protocol': 'trojan',
      'tag': _name(uri),
      'settings': {
        'servers': [
          {
            'address': address,
            'port': port,
            'password': password,
            'level': 0,
          },
        ],
      },
      'streamSettings': _stream(
        network: (q['type'] ?? 'tcp').toLowerCase(),
        security: (q['security'] ?? 'tls').toLowerCase(),
        query: q,
        fallbackHost: address,
      ),
    };
  }

  static Map<String, dynamic>? _shadowsocks(Uri uri) {
    final address = uri.host;
    final port = uri.port;
    if (address.isEmpty || port <= 0) return null;

    var userInfo = uri.userInfo;
    var plugin = uri.queryParameters['plugin'] ?? '';
    if (userInfo.isEmpty && uri.pathSegments.isNotEmpty) {
      final decoded = _decodeBase64(uri.pathSegments.join('/'));
      if (decoded != null) userInfo = decoded;
    }
    if (userInfo.isEmpty) return null;

    final decodedInfo = _decodeBase64(userInfo) ?? userInfo;
    final separator = decodedInfo.indexOf(':');
    if (separator <= 0) return null;
    final method = decodedInfo.substring(0, separator);
    final password = decodedInfo.substring(separator + 1);
    if (plugin.isEmpty && password.contains(';')) {
      final parts = password.split(';');
      plugin = parts.skip(1).join(';');
    }

    final server = <String, dynamic>{
      'address': address,
      'port': port,
      'method': method,
      'password': password.split(';').first,
      'level': 0,
    };
    final pluginName = plugin.split(';').first;
    if (pluginName.isNotEmpty) {
      server['plugin'] = pluginName;
      final opts = plugin.split(';').skip(1).join(';');
      if (opts.isNotEmpty) server['pluginOpts'] = opts;
    }

    return {
      'protocol': 'shadowsocks',
      'tag': _name(uri),
      'settings': {'servers': [server]},
    };
  }

  static Map<String, dynamic>? _socks(Uri uri) {
    final address = uri.host;
    final port = uri.port;
    if (address.isEmpty || port <= 0) return null;
    final parts = uri.userInfo.split(':');
    final user = parts.first;
    final password = parts.length > 1 ? parts.sublist(1).join(':') : '';
    return {
      'protocol': 'socks',
      'tag': _name(uri),
      'settings': {
        'servers': [
          {
            'address': address,
            'port': port,
            'version': '5',
            'users': [
              if (user.isNotEmpty)
                {'user': user, 'pass': password},
            ],
          },
        ],
      },
    };
  }

  static Map<String, dynamic>? _http(Uri uri) {
    final address = uri.host;
    final port = uri.port;
    if (address.isEmpty || port <= 0) return null;
    final parts = uri.userInfo.split(':');
    final user = parts.first;
    final password = parts.length > 1 ? parts.sublist(1).join(':') : '';
    return {
      'protocol': 'http',
      'tag': _name(uri),
      'settings': {
        'servers': [
          {
            'address': address,
            'port': port,
            if (user.isNotEmpty)
              'users': [
                {'user': user, 'pass': password},
              ],
          },
        ],
      },
    };
  }

  static Map<String, dynamic>? _hysteria2(Uri uri) {
    final address = uri.host;
    final port = uri.port;
    final password = uri.userInfo;
    if (address.isEmpty || port <= 0 || password.isEmpty) return null;
    final q = uri.queryParameters;
    return {
      'protocol': 'hysteria2',
      'tag': _name(uri),
      'settings': {
        'address': address,
        'port': port,
        'password': password,
        if ((q['obfs'] ?? '').isNotEmpty) 'obfs': q['obfs'],
      },
      'streamSettings': _stream(
        network: 'raw',
        security: 'tls',
        query: q,
        fallbackHost: address,
      ),
    };
  }

  static Map<String, dynamic> _stream({
    required String network,
    required String security,
    required Map<String, String> query,
    required String fallbackHost,
  }) {
    final sni = _first(query, ['sni', 'serverName', 'host']) ?? fallbackHost;
    final host = _first(query, ['host', 'Host']) ?? '';
    final path = _first(query, ['path', 'serviceName']) ?? '/';
    final alpn = _first(query, ['alpn']) ?? '';
    final fingerprint = _first(query, ['fp', 'fingerprint']) ?? '';
    final headerType = _first(query, ['headerType', 'type']) ?? '';

    final stream = <String, dynamic>{
      'network': network == 'h2' ? 'http' : network,
      'security': security == 'reality' ? 'reality' : security,
    };

    if (security == 'tls' || security == 'xtls') {
      stream['tlsSettings'] = <String, dynamic>{
        'serverName': sni,
        'allowInsecure': false,
        if (alpn.isNotEmpty) 'alpn': alpn.split(RegExp(r'[,;]')),
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
      };
    } else if (security == 'reality') {
      stream['realitySettings'] = <String, dynamic>{
        'serverName': sni,
        if ((_first(query, ['pbk', 'publicKey']) ?? '').isNotEmpty)
          'publicKey': _first(query, ['pbk', 'publicKey']),
        if ((_first(query, ['sid', 'shortId']) ?? '').isNotEmpty)
          'shortId': _first(query, ['sid', 'shortId']),
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
      };
    }

    switch (network) {
      case 'ws':
        stream['wsSettings'] = <String, dynamic>{
          'path': path,
          'headers': <String, String>{if (host.isNotEmpty) 'Host': host},
        };
      case 'grpc':
        stream['grpcSettings'] = <String, dynamic>{
          'serviceName': path == '/' ? '' : path,
          'multiMode': false,
        };
      case 'http':
      case 'h2':
      case 'xhttp':
        stream['httpSettings'] = <String, dynamic>{
          'host': host.isEmpty ? <String>[] : host.split(RegExp(r'[,;]')),
          'path': path,
        };
      case 'quic':
        stream['quicSettings'] = <String, dynamic>{
          'header': {'type': headerType.isEmpty ? 'none' : headerType},
        };
      default:
        if (headerType.isNotEmpty && headerType != 'none') {
          stream['tcpSettings'] = <String, dynamic>{
            'header': {'type': headerType},
          };
        }
    }

    return stream;
  }

  static String? _first(Map<String, String> query, List<String> keys) {
    for (final key in keys) {
      final value = query[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String _name(Uri uri, {String? fallback}) {
    final raw = uri.fragment.isNotEmpty ? uri.fragment : fallback;
    if (raw == null || raw.trim().isEmpty) return 'proxy';
    try {
      return Uri.decodeComponent(raw.trim());
    } on Object {
      return raw.trim();
    }
  }

  static String? _decodeBase64(String value) {
    var normalized = value
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    final padding = normalized.length % 4;
    if (padding != 0) normalized += '=' * (4 - padding);
    try {
      return utf8.decode(base64Decode(normalized));
    } on Object {
      return null;
    }
  }
}
