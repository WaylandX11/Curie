import 'subscription_parser.dart';

/// Общие правила выбора основного сервера и запасного (fallback) для пинга и
/// для рабочего конфига. Должны совпадать, иначе пинг будет показывать один
/// сервер, а трафик пойдёт через другой.
class Servers {
  static bool isProxy(Map<String, dynamic> outbound) {
    final protocol = (outbound['protocol'] as String?)?.toLowerCase();
    return protocol != null &&
        SubscriptionParser.proxyProtocols.contains(protocol);
  }

  static List<Map<String, dynamic>> proxies(
    List<Map<String, dynamic>> outbounds,
  ) =>
      outbounds.where(isProxy).toList();

  static String? tag(Map<String, dynamic> outbound) {
    final value = (outbound['tag'] as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// `selector` балансировщика и `subjectSelector` обсерватории в Xray
  /// сопоставляются с тегом outbound'а по префиксу.
  static List<String> selectorPrefixes(Map<String, dynamic>? base) {
    final prefixes = <String>[];
    final routing = base?['routing'];
    if (routing is Map && routing['balancers'] is List) {
      for (final balancer in (routing['balancers'] as List).whereType<Map>()) {
        final selector = balancer['selector'];
        if (selector is List) prefixes.addAll(selector.whereType<String>());
      }
    }
    final observatory = base?['burstObservatory'] ?? base?['observatory'];
    if (observatory is Map && observatory['subjectSelector'] is List) {
      prefixes.addAll((observatory['subjectSelector'] as List).whereType<String>());
    }
    return prefixes.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static List<String> fallbackTags(Map<String, dynamic>? base) {
    final tags = <String>{};
    final routing = base?['routing'];
    if (routing is Map && routing['balancers'] is List) {
      for (final balancer in (routing['balancers'] as List).whereType<Map>()) {
        final tag = (balancer['fallbackTag'] as String?)?.trim();
        if (tag != null && tag.isNotEmpty) tags.add(tag);
      }
    }
    return tags.toList();
  }

  /// В конфигах Remnawave первый хост получает тег без номера (`proxy`) и
  /// служит запасным, а рабочие хосты — `proxy-2`, `proxy-3`.
  static String? inferFallbackTag(List<Map<String, dynamic>> proxies) {
    for (final outbound in proxies) {
      final tag = Servers.tag(outbound);
      if (tag == null) continue;
      final numberedSibling = proxies.any((other) {
        final otherTag = Servers.tag(other);
        return otherTag != null &&
            otherTag != tag &&
            otherTag.startsWith('$tag-');
      });
      if (numberedSibling) return tag;
    }
    return null;
  }

  /// Все запасные теги: явные `fallbackTag` плюс выведенный по соглашению
  /// Remnawave первый хост.
  static Set<String> allFallbackTags(
    List<Map<String, dynamic>> proxies,
    Map<String, dynamic>? base,
  ) {
    final tags = fallbackTags(base).toSet();
    final inferred = inferFallbackTag(proxies);
    if (tags.isEmpty && inferred != null) tags.add(inferred);
    return tags;
  }
}
