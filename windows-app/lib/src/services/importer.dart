import '../models/profile.dart';
import 'store.dart';
import 'subscriptions.dart';
import 'subscription_service.dart';
import 'xray.dart';

enum ImportKind { none, link, subscription }

class ImportResult {
  const ImportResult({
    required this.kind,
    this.count = 0,
    this.name,
    this.failure,
  });

  final ImportKind kind;
  final int count;
  final String? name;
  final SubscriptionException? failure;

  bool get ok => kind != ImportKind.none && failure == null;
}

/// Единая точка входа для всего, что приходит извне: буфер обмена, QR-код,
/// ручной ввод. Ссылки становятся серверами, http(s) — подпиской.
class Importer {
  static const Xray _xray = Xray();

  /// Схемы, которые понимает ядро (libXray parse_share).
  static const Set<String> proxySchemes = {
    'vless',
    'vmess',
    'trojan',
    'ss',
    'socks',
    'hysteria2',
    'hy2',
  };

  static bool isProxyLink(String value) {
    final scheme = Uri.tryParse(value.trim())?.scheme.toLowerCase();
    return scheme != null && proxySchemes.contains(scheme);
  }

  static bool isSubscriptionUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
  }

  /// Ищет в тексте ссылки и URL подписки. Порядок строк сохраняется.
  static ({List<String> links, String? subscriptionUrl}) scan(String text) {
    final links = <String>[];
    final seen = <String>{};
    String? subscriptionUrl;

    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (isProxyLink(line)) {
        if (seen.add(line)) links.add(line);
      } else if (subscriptionUrl == null && isSubscriptionUrl(line)) {
        subscriptionUrl = line;
      }
    }
    return (links: links, subscriptionUrl: subscriptionUrl);
  }

  static Future<ImportResult> importText(String text, {String? fallbackName}) async {
    final found = scan(text);

    if (found.links.isNotEmpty) {
      final added = <Profile>[];
      for (final link in found.links) {
        try {
          final outbounds = await _xray.parseLink(link);
          added.add(profileFromOutbound(
            link: link,
            outbound: outbounds.first,
            fallbackName: fallbackName ?? _nameFromLink(link) ?? link,
          ));
        } on Object {
          // Битая ссылка не мешает остальным.
        }
      }
      if (added.isEmpty) {
        return const ImportResult(kind: ImportKind.none);
      }

      await Store.instance.update((state) {
        final existing = state.profiles.map((p) => p.id).toSet();
        final fresh = added.where((p) => !existing.contains(p.id)).toList();
        return state.copyWith(
          profiles: [...state.profiles, ...fresh],
          selectedId: (fresh.isEmpty ? added : fresh).first.id,
        );
      });

      return ImportResult(
        kind: ImportKind.link,
        count: added.length,
        name: added.first.name,
      );
    }

    final url = found.subscriptionUrl;
    if (url != null) {
      final failure = await Subscriptions.add(url, '');
      if (failure != null) {
        return ImportResult(kind: ImportKind.subscription, failure: failure);
      }
      final subscription = Store.instance.state.value.subscriptions
          .where((s) => s.url == url)
          .firstOrNull;
      return ImportResult(
        kind: ImportKind.subscription,
        count: subscription?.nodes.length ?? 0,
        name: subscription?.title,
      );
    }

    return const ImportResult(kind: ImportKind.none);
  }

  static String? _nameFromLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    final fragment = uri.fragment.trim();
    if (fragment.isNotEmpty) {
      try {
        return Uri.decodeComponent(fragment);
      } on ArgumentError {
        return fragment;
      }
    }
    return uri.host.isEmpty ? null : uri.host;
  }
}
