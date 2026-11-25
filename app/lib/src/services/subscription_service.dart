import 'dart:convert';
import 'dart:io';

import '../models/profile.dart';
import '../models/subscription.dart';
import 'app_log.dart';
import 'subscription_parser.dart';
import 'xray.dart';

/// Ошибка загрузки подписки. `code` локализуется в UI, `detail` — подробности
/// (HTTP-статус, текст сетевого сбоя), их не переводим.
class SubscriptionException implements Exception {
  const SubscriptionException(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => detail == null ? code : '$code: $detail';
}

/// Загрузка подписки.
///
/// Явно просим JSON: Remnawave понимает суффикс `/json` и отдаёт XRAY_JSON
/// даже без правила в панели (по умолчанию он отдал бы base64, потому что наш
/// User-Agent не встроен в её whitelist). Если панель суффикс не понимает —
/// пробуем исходный URL и разбираем всё, что пришло: JSON или ссылки.
class SubscriptionService {
  const SubscriptionService({this.xray = const Xray()});

  final Xray xray;

  static const Duration _timeout = Duration(seconds: 30);

  /// URL запроса с явным запросом JSON. Сохранённая ссылка не меняется.
  static Uri requestUri(String rawUrl, {bool json = true}) {
    final uri = Uri.parse(rawUrl);
    if (!json || uri.hasQuery || uri.hasFragment) return uri;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty ||
        Subscription.formatSuffixes.contains(segments.last.toLowerCase())) {
      return uri;
    }
    return uri.replace(pathSegments: [...segments, 'json']);
  }

  Future<Subscription> refresh(
    Subscription subscription, {
    Map<String, String> headers = const {},
    String userAgent = 'Curie',
    int proxyPort = 0,
  }) async {
    final baseUri = Uri.parse(subscription.url);
    final jsonUri = requestUri(subscription.url);
    final candidates = <Uri>[
      if (jsonUri != baseUri) jsonUri,
      baseUri,
    ];

    _Fetched? fetched;
    List<Profile>? nodes;
    SubscriptionException? failure;
    var viaSuffix = false;

    for (var i = 0; i < candidates.length; i++) {
      try {
        final result = await _fetch(
          candidates[i],
          headers: headers,
          userAgent: userAgent,
          proxyPort: proxyPort,
        );
        final parsed = await _nodes(result.body, result.contentType, subscription.url);
        if (parsed.isEmpty) throw const SubscriptionException('noNodes');

        // `/json` проигнорирован панелью и вернул ссылки: есть шанс, что
        // базовый URL отдаст JSON (например, по правилу в панели).
        if (i == 0 && parsed.first.isJson == false && candidates.length > 1) {
          failure ??= const SubscriptionException('links', 'json suffix ignored');
          continue;
        }

        fetched = result;
        nodes = parsed;
        viaSuffix = i == 0;
        break;
      } on SubscriptionException catch (e) {
        if (e.code == 'hwidLimit') rethrow;
        failure = e;
        if (i == candidates.length - 1) rethrow;
      }
    }

    if (fetched == null || nodes == null) {
      throw failure ?? const SubscriptionException('noNodes');
    }

    // Ручные правки узлов переживают обновление подписки.
    nodes = nodes.map(subscription.applyEdit).toList();

    AppLog.add('subscription',
        '${subscription.url}: ${nodes.length} узлов (${nodes.first.isJson ? 'JSON' : 'ссылки'}${viaSuffix ? ', /json' : ''})');

    final title = SubscriptionParser.decodeHeader(fetched.header('profile-title')) ??
        subscription.title.ifEmpty(_hostOf(subscription.url));
    final interval = int.tryParse(fetched.header('profile-update-interval') ?? '') ?? 0;

    return subscription.copyWith(
      title: title,
      nodes: nodes,
      updatedAt: DateTime.now(),
      updateIntervalHours: interval > 0 ? interval : subscription.updateIntervalHours,
      info: SubscriptionInfo.parse(fetched.header('subscription-userinfo')) ??
          subscription.info,
      announce: SubscriptionParser.decodeHeader(fetched.header('announce')) ??
          subscription.announce,
      supportUrl: fetched.header('support-url') ?? subscription.supportUrl,
      webPageUrl: fetched.header('profile-web-page-url') ?? subscription.webPageUrl,
      clearError: true,
    );
  }

  Future<_Fetched> _fetch(
    Uri uri, {
    required Map<String, String> headers,
    required String userAgent,
    required int proxyPort,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      // Curie исключён из собственного TUN. Когда туннель поднят, панель
      // обновляем через локальный HTTP-прокси Xray; иначе — напрямую.
      ..findProxy = (_) => proxyPort > 0
          ? 'PROXY 127.0.0.1:$proxyPort'
          : 'DIRECT';
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/plain;q=0.9, */*;q=0.8',
      );
      // Панели различают клиентов по заголовкам; ОС сообщаем всегда, HWID — по согласию.
      request.headers.set('x-device-os', Platform.operatingSystem);
      headers.forEach(request.headers.set);
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close().timeout(_timeout);

      if (response.statusCode != HttpStatus.ok) {
        if (response.statusCode == HttpStatus.notFound && !headers.containsKey('x-hwid')) {
          throw const SubscriptionException('hwidRequired');
        }
        throw SubscriptionException('http', '${response.statusCode}');
      }

      if (_flag(response, 'x-hwid-max-devices-reached') || _flag(response, 'x-hwid-limit')) {
        throw const SubscriptionException('hwidLimit');
      }
      if (_flag(response, 'x-hwid-not-supported')) {
        throw const SubscriptionException('hwidRequired');
      }

      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      // Копируем заголовки: клиент закрывается в finally, а meta-заголовки
      // панели нужны уже после его закрытия.
      final responseHeaders = <String, String>{};
      response.headers.forEach(
        (name, values) => responseHeaders[name.toLowerCase()] = values.join(', '),
      );
      return _Fetched(body, response.headers.contentType?.mimeType ?? '', responseHeaders);
    } on SubscriptionException {
      rethrow;
    } on Object catch (e) {
      throw SubscriptionException('network', e.toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Profile>> _nodes(String body, String contentType, String url) async {
    // 1. JSON — приоритет, даже если content-type врёт.
    if (contentType.contains('json') || SubscriptionParser.looksLikeJson(body)) {
      final parsed = SubscriptionParser.parseJson(body, subscriptionUrl: url);
      if (parsed.isNotEmpty) return parsed;
    }

    // 2. Ссылки: plain-список или base64.
    final links = SubscriptionParser.extractLinks(body);
    if (links.isEmpty) throw const SubscriptionException('noLinks');

    final nodes = <Profile>[];
    for (final link in links) {
      try {
        final outbounds = await xray.parseLink(link);
        nodes.add(profileFromOutbound(
          link: link,
          outbound: outbounds.first,
          fallbackName: _nameFromLink(link) ?? 'Node ${nodes.length + 1}',
          subscriptionUrl: url,
        ));
      } on Object {
        // Битый узел не должен ронять всю подписку.
      }
    }
    return nodes;
  }

  static bool _flag(HttpClientResponse response, String name) =>
      response.headers.value(name)?.toLowerCase() == 'true';

  /// Оставлено для совместимости с тестами и внешними вызовами.
  static List<String> extractLinks(String body) => SubscriptionParser.extractLinks(body);

  static String _hostOf(String url) => Uri.tryParse(url)?.host ?? url;

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

class _Fetched {
  const _Fetched(this.body, this.contentType, this.headers);

  final String body;
  final String contentType;
  final Map<String, String> headers;

  String? header(String name) => headers[name.toLowerCase()];
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
