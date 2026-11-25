import 'dart:convert';

import '../models/profile.dart';
import 'server_selection.dart';
import 'subscription_parser.dart';
import 'xray.dart';

/// Конфиг узла целиком, если он пришёл из JSON-подписки.
Map<String, dynamic>? baseConfigOf(Profile profile) {
  final raw = profile.configJson;
  if (raw == null) return null;
  try {
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  } on Object {
    return null;
  }
}

/// Outbound'ы узла: из готового JSON или разбором ссылки ядром.
Future<List<Map<String, dynamic>>> outboundsFor(Profile profile) async {
  if (profile.isJson) {
    final outbounds = SubscriptionParser.outboundsOf(profile);
    if (outbounds.isEmpty) throw const XrayException('пустой конфиг узла');
    return outbounds;
  }
  final link = profile.link;
  if (link == null) throw const XrayException('у узла нет ни ссылки, ни конфига');
  return const Xray().parseLink(link);
}

/// Один конкретный сервер внутри узла: адрес, порт и параметры TLS.
///
/// У балансировщика серверов несколько: основные (`proxy-2`, `proxy-3`) и
/// запасной (`proxy` — первый хост в терминах Remnawave). Пинг проверяет и тех,
/// и других, но результат запасного используется, только если основные не
/// ответили.
class PingTarget {
  const PingTarget({
    required this.outbound,
    required this.address,
    required this.port,
    this.security,
    this.serverName,
    this.alpn,
    this.fallback = false,
  });

  final Map<String, dynamic> outbound;
  final String address;
  final int port;

  /// `tls`, `reality`, `xtls` или `none`.
  final String? security;

  /// SNI для TLS-проверки TCP-пинга.
  final String? serverName;
  final List<String>? alpn;

  /// Запасной outbound: его задержку показываем только при отказе основных.
  final bool fallback;

  String? get tag {
    final value = (outbound['tag'] as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  bool get isTls =>
      security == 'tls' || security == 'reality' || security == 'xtls';
}

/// Всё, что нужно для замера узла: полный список outbound'ов (для зависимостей
/// вроде `dialerProxy`) и конкретные серверы-кандидаты.
class ProfilePingTargets {
  const ProfilePingTargets({required this.outbounds, required this.targets});

  final List<Map<String, dynamic>> outbounds;
  final List<PingTarget> targets;
}

class _Candidate {
  const _Candidate(this.outbound, this.fallback);

  final Map<String, dynamic> outbound;
  final bool fallback;
}

/// Серверы узла, которые имеет смысл проверять пингом.
Future<ProfilePingTargets> pingTargetsFor(Profile profile) async {
  final outbounds = await outboundsFor(profile);
  final selected = _pingCandidates(outbounds, baseConfigOf(profile));
  final targets = <PingTarget>[];
  final seen = <String>{};

  for (final candidate in selected) {
    final outbound = candidate.outbound;
    final details = outboundDetails(outbound);
    final address = details.address?.trim();
    final port = details.port;
    if (address == null || address.isEmpty || port == null || port <= 0) {
      continue;
    }
    final key = '${address.toLowerCase()}:$port';
    if (!seen.add(key)) continue;

    final stream =
        (outbound['streamSettings'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final tls = (stream['tlsSettings'] as Map?)?.cast<String, dynamic>();
    final reality =
        (stream['realitySettings'] as Map?)?.cast<String, dynamic>();
    final xtls = (stream['xtlsSettings'] as Map?)?.cast<String, dynamic>();
    final serverName = (tls?['serverName'] ??
            reality?['serverName'] ??
            xtls?['serverName']) as String?;
    final alpnRaw = tls?['alpn'];

    targets.add(PingTarget(
      outbound: outbound,
      address: address,
      port: port,
      security: (stream['security'] as String?)?.toLowerCase(),
      serverName: serverName?.trim(),
      alpn: alpnRaw is List ? alpnRaw.whereType<String>().toList() : null,
      fallback: candidate.fallback,
    ));
  }

  return ProfilePingTargets(outbounds: outbounds, targets: targets);
}

/// Элемент запроса `pingBatch`. `outboundTag` обязан быть отдельным полем:
/// libXray читает цель оттуда, а внутри `xrayJson` берёт только `outbounds`.
Map<String, dynamic> pingBatchItem(ProfilePingTargets plan, PingTarget target) {
  final tag = target.tag;
  return {
    'xrayJson': jsonEncode({
      'outbounds': tag != null ? plan.outbounds : [target.outbound],
    }),
    'outboundTag': ?tag,
  };
}

/// Кандидаты для пинга: сначала основные серверы, потом fallback.
///
/// В конфигах Remnawave первый хост получает тег без номера (`proxy`) и
/// используется как `fallbackTag`, а рабочие хосты — `proxy-2`, `proxy-3` и
/// попадают под `selector: ["proxy-"]`. Раньше брался просто первый outbound,
/// поэтому пинг уходил в мёртвый запасной сервер.
List<_Candidate> _pingCandidates(
  List<Map<String, dynamic>> outbounds,
  Map<String, dynamic>? base,
) {
  final proxies = Servers.proxies(outbounds);
  if (proxies.isEmpty) {
    return outbounds.isEmpty ? const [] : [_Candidate(outbounds.first, false)];
  }

  final selectors = Servers.selectorPrefixes(base);
  final fallbackTags = Servers.allFallbackTags(proxies, base);

  // Обычный узел без балансировщика и без запасного сервера проверяется по
  // одному outbound'у: чужие прокси в конфиге нас не интересуют.
  if (selectors.isEmpty && fallbackTags.isEmpty) {
    return [_Candidate(proxies.first, false)];
  }

  final primary = <_Candidate>[];
  final fallback = <_Candidate>[];
  for (final outbound in proxies) {
    final tag = Servers.tag(outbound);
    final isFallback = tag != null && fallbackTags.contains(tag);
    if (isFallback) {
      fallback.add(_Candidate(outbound, true));
      continue;
    }
    if (selectors.isEmpty ||
        (tag != null && selectors.any((s) => tag.startsWith(s)))) {
      primary.add(_Candidate(outbound, false));
    }
    // Outbound под чужим селектором не трогаем: он не участвует в замере.
  }

  if (primary.isEmpty) {
    return fallback.isNotEmpty ? fallback : [_Candidate(proxies.first, false)];
  }
  return [...primary, ...fallback];
}


