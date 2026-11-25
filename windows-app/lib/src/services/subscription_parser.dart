import 'dart:convert';

import '../models/profile.dart';

/// Разбор тела подписки. Remnawave и совместимые панели отдают либо JSON
/// (массив конфигов или объект с outbounds), либо base64-список ссылок.
/// JSON приоритетнее: он приходит от панелей с шаблонами и balancer'ами.
class SubscriptionParser {
  /// Прокси-протоколы: только они считаются узлами.
  static const Set<String> proxyProtocols = {
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'socks',
    'http',
    'hysteria',
    'wireguard',
  };

  static bool looksLikeJson(String body) {
    final text = body.trimLeft();
    return text.startsWith('[') || text.startsWith('{');
  }

  /// Узлы из JSON-подписки. Пустой список, если это не JSON или узлов нет.
  static List<Profile> parseJson(String body, {String? subscriptionUrl}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on Object {
      return const [];
    }

    final profiles = <Profile>[];
    for (final config in _configs(decoded)) {
      profiles.addAll(_profilesFromConfig(config, subscriptionUrl));
    }
    return profiles;
  }

  /// Каждый элемент массива — отдельное подключение; одиночный объект тоже.
  static List<Map<String, dynamic>> _configs(Object? decoded) {
    if (decoded is List) {
      return decoded.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (decoded is Map) {
      return [decoded.cast<String, dynamic>()];
    }
    return const [];
  }

  static List<Profile> _profilesFromConfig(
    Map<String, dynamic> config,
    String? subscriptionUrl,
  ) {
    final outbounds = (config['outbounds'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    if (outbounds.isEmpty) return const [];

    final remarks = (config['remarks'] as String?)?.trim();
    final isFullConfig = remarks != null ||
        config.containsKey('inbounds') ||
        config.containsKey('routing') ||
        config.containsKey('dns');

    if (isFullConfig) {
      // Один узел = весь конфиг панели: сохраняем routing, balancers и
      // observatory, иначе потеряем и балансировку, и обход российских сайтов.
      final primary = _primary(outbounds);
      if (primary == null) return const [];
      final details = outboundDetails(primary);
      final balancers = (config['routing'] as Map?)?['balancers'];
      return [
        Profile(
          name: (remarks != null && remarks.isNotEmpty)
              ? remarks
              : ((primary['tag'] as String?) ?? details.address ?? 'Node'),
          configJson: jsonEncode(config),
          address: details.address,
          port: details.port,
          subscriptionUrl: subscriptionUrl,
          protocol: details.protocol,
          network: details.network,
          security: details.security,
          hasBalancer: balancers is List && balancers.isNotEmpty,
        ),
      ];
    }

    // «Голый» список outbounds: каждый прокси-протокол — отдельный узел.
    final profiles = <Profile>[];
    for (final outbound in outbounds) {
      final protocol = (outbound['protocol'] as String?)?.toLowerCase();
      if (protocol == null || !proxyProtocols.contains(protocol)) continue;
      final details = outboundDetails(outbound);
      final tag = (outbound['tag'] as String?)?.trim();
      profiles.add(Profile(
        name: (tag != null && tag.isNotEmpty) ? tag : (details.address ?? 'Node'),
        configJson: jsonEncode({
          'outbounds': [outbound],
        }),
        address: details.address,
        port: details.port,
        subscriptionUrl: subscriptionUrl,
        protocol: details.protocol,
        network: details.network,
        security: details.security,
      ));
    }
    return profiles;
  }

  static Map<String, dynamic>? _primary(List<Map<String, dynamic>> outbounds) {
    for (final outbound in outbounds) {
      final protocol = (outbound['protocol'] as String?)?.toLowerCase();
      if (protocol != null && proxyProtocols.contains(protocol)) return outbound;
    }
    return outbounds.isEmpty ? null : outbounds.first;
  }

  /// Outbound'ы узла для сборки рабочего конфига.
  static List<Map<String, dynamic>> outboundsOf(Profile profile) {
    final raw = profile.configJson;
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (decoded['outbounds'] as List?)
              ?.whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList() ??
          const [];
    } on Object {
      return const [];
    }
  }

  /// Ссылки из plain/base64-тела.
  static List<String> extractLinks(String body) {
    var text = body.trim();
    if (text.isEmpty) return const [];

    if (!text.contains('://')) {
      final decoded = tryBase64(text);
      if (decoded != null && decoded.contains('://')) {
        text = decoded;
      }
    }

    final links = <String>[];
    final seen = <String>{};
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(line)) continue;
      if (seen.add(line)) links.add(line);
    }
    return links;
  }

  static String? tryBase64(String text) {
    var normalized =
        text.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    final padding = normalized.length % 4;
    if (padding != 0) normalized += '=' * (4 - padding);
    try {
      return utf8.decode(base64Decode(normalized));
    } on Object {
      return null;
    }
  }

  /// Заголовки панели часто приходят как `base64:…`.
  static String? decodeHeader(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final text = value.trim();
    if (text.startsWith('base64:')) {
      return tryBase64(text.substring('base64:'.length))?.trim() ?? text;
    }
    return text;
  }
}
