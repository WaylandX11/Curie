import 'dart:convert';

import '../models/settings.dart';
import 'server_selection.dart';

/// Собирает рабочий конфиг Xray для TUN-режима.
///
/// Если узел пришёл из JSON-подписки целиком (`base`), сохраняем её routing,
/// balancers и observatory: там и балансировка между серверами, и обход
/// российских сайтов. Меняем только то, без чего туннель не работает:
/// inbound'ы (вместо socks/http — TUN) и DNS-перехват.
///
/// Дескриптор TUN сюда не входит: его знает только Android, и Kotlin сам
/// добавляет `env."xray.tun.fd"` перед запуском.
String buildXrayConfig({
  required List<Map<String, dynamic>> outbounds,
  Settings settings = const Settings(),
  Map<String, dynamic>? base,
  int metricsPort = 49227,
  int checkPort = 0,
  String logPath = '',
  String? geoAssetDir,
}) {
  final config = <String, dynamic>{...?base};

  // Xray ищет geoip.dat/geosite.dat в каталоге из `xray.location.asset`.
  // На Windows TUN-дескриптор не нужен, но каталог баз должен дойти до ядра.
  final env =
      (config['env'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  if (geoAssetDir != null && geoAssetDir.isNotEmpty) {
    env['xray.location.asset'] = geoAssetDir;
    env['XRAY_LOCATION_ASSET'] = geoAssetDir;
  }
  if (env.isNotEmpty) config['env'] = env;

  // Ключ именно `logLevel`: старый `loglevel` ядро не понимало и молча
  // использовало warning. При выключенном журнале levels none отключает и
  // stdout, и запись в файл.
  final logging =
      settings.xrayLogEnabled &&
      settings.xrayLogLevel != XrayLogLevel.none &&
      logPath.isNotEmpty;
  config['log'] = logging
      ? {
          'logLevel': settings.xrayLogLevel.wireName,
          'error': logPath,
          'access': 'none',
          // Это строка в Xray-core: `true` не парсится и ломает весь конфиг.
          // `full` маскирует ipv4 и ipv6 полностью.
          'maskAddress': 'full',
        }
      : {'logLevel': 'none', 'error': 'none', 'access': 'none'};

  // Счётчики трафика для индикатора скорости. Метрики читаются локально,
  // через 127.0.0.1, и не создают ещё одного слушателя наружу.
  config['metrics'] = {'listen': '127.0.0.1:$metricsPort'};
  config['stats'] = <String, dynamic>{};
  final policy =
      (base?['policy'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  final system =
      (policy['system'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
  config['policy'] = {
    ...policy,
    'system': {
      ...system,
      'statsInboundUplink': true,
      'statsInboundDownlink': true,
      'statsOutboundUplink': true,
      'statsOutboundDownlink': true,
    },
  };

  final merged = <Map<String, dynamic>>[...outbounds];
  if (!_hasTag(merged, 'direct')) {
    merged.add({'tag': 'direct', 'protocol': 'freedom'});
  }
  if (!_hasTag(merged, 'dns-out')) {
    merged.add({'tag': 'dns-out', 'protocol': 'dns'});
  }
  config['outbounds'] = merged;

  // В конфигах Remnawave запасной хост (`proxy`) стоит первым, а рабочие —
  // `proxy-2`, `proxy-3`. DNS и локальная проверка должны идти через рабочий
  // сервер, иначе «Проверить» показывает обрыв, когда основной доступен.
  final proxies = Servers.proxies(merged);
  final fallbackTags = Servers.allFallbackTags(proxies, base);
  final proxyTag = _proxyTag(proxies, fallbackTags);

  // Панель может прислать балансировщик без fallbackTag (тогда при отказе всех
  // основных серверов трафик некуда переключать) или не прислать routing вовсе.
  // Добавляем fallbackTag/балансировщик, чтобы подключение шло по основному
  // серверу, а при его недоступности — по запасному.
  final panelBalancers = _panelBalancers(base);
  final panelRules = _panelRules(base);
  final hasBalancerRule = panelRules.any((rule) => rule['balancerTag'] != null);
  final autoBalancerTag =
      proxies.length > 1 && panelBalancers.isEmpty && !hasBalancerRule
      ? 'curie-auto-balancer'
      : null;
  final balancers = <Map<String, dynamic>>[
    ...panelBalancers,
    if (autoBalancerTag != null)
      {
        'tag': autoBalancerTag,
        'selector': [
          for (final outbound in proxies)
            if (!fallbackTags.contains(Servers.tag(outbound)))
              Servers.tag(outbound),
        ].whereType<String>().toList(),
        'fallbackTag': ?(fallbackTags.isNotEmpty ? fallbackTags.first : null),
        // Явно задаём пустые settings: так формат совпадает с шаблонами
        // Remnawave, где leastLoad всегда несёт этот объект.
        'strategy': {'type': 'leastLoad', 'settings': <String, dynamic>{}},
      },
  ];
  var addedFallbackTag = false;
  if (autoBalancerTag == null) {
    for (final balancer in balancers) {
      if (balancer['fallbackTag'] != null) continue;
      final candidate = _firstUnselectedProxy(balancer['selector'], proxies);
      if (candidate == null) continue;
      balancer['fallbackTag'] = candidate;
      addedFallbackTag = true;
    }
  }

  // Проверка сети, подписки и DNS должны идти туда же, куда и обычный трафик:
  // через балансировщик с fallbackTag. Иначе при отказе основного узла
  // запасной работает, а локальный прокси и сторож висят на мёртвом outbound.
  const dnsInboundTag = 'curie-dns';
  final withFallback = balancers
      .where((balancer) => balancer['fallbackTag'] != null)
      .toList();
  final trafficBalancer = withFallback.isNotEmpty
      ? withFallback.first
      : (balancers.isNotEmpty ? balancers.first : null);
  final trafficBalancerTag = trafficBalancer?['tag'] as String?;
  final dnsViaBalancer =
      settings.dnsRoute == DnsRoute.tunnel && trafficBalancerTag != null;

  // Свои inbound'ы панели (socks/http на 127.0.0.1) не нужны: трафик приходит
  // из TUN или локального SOCKS5. Исключение — HTTP-прокси для «Проверить»:
  // он слушает только 127.0.0.1 и делает запрос через рабочий outbound.
  config['inbounds'] = [
    if (settings.tunnelMode.hasTun)
      {
        'tag': 'tun',
        'port': 0,
        'protocol': 'tun',
        'settings': {
          // Имя обязательно: без него Xray зовёт net.Interfaces() для генерации
          // utun-имени, а Android запрещает netlink обычному приложению
          // ("route ip+net: netlinkrib: permission denied").
          'name': 'curie-tun',
          'mtu': settings.mtu,
        },
        // Без сниффинга Xray видит только IP: доменные правила панели
        // (`domain:vk.com`, `full:mos.ru` и т.п.) никогда не срабатывают.
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          // Подменяем адрес и для dial: иначе direct уходит на IP, полученный
          // через вышестоящий DNS прокси, и белые списки панели не открываются.
          // С domainStrategy IPIfNonMatch доменные и IP-правила работают вместе.
          'routeOnly': false,
        },
      },
    if (settings.tunnelMode.hasProxy)
      {
        'tag': 'socks',
        'protocol': 'socks',
        'listen': '127.0.0.1',
        'port': settings.effectiveSocksPort,
        'settings': <String, dynamic>{
          'udp': true,
          if (settings.socksAuth)
            'auth': 'password'
          else
            'auth': 'noauth',
          if (settings.socksAuth)
            'accounts': [
              {
                'user': settings.socksUsername,
                'pass': settings.effectiveSocksPassword,
              },
            ],
        },
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': false,
        },
      },
    if (checkPort > 0 && proxyTag != null)
      {
        'tag': 'check',
        'port': checkPort,
        'protocol': 'http',
        'listen': '127.0.0.1',
        'settings': <String, dynamic>{},
      },
  ];

  // DNS по умолчанию идёт через тот же путь, что и обычный трафик. Когда есть
  // балансировщик, запросы DNS идут через него — вместе с основным узлом
  // автоматически работает и запасной.
  config['dns'] = _dns(
    base?['dns'],
    settings,
    dnsViaBalancer
        ? null
        : settings.dnsRoute == DnsRoute.tunnel
        ? proxyTag
        : 'direct',
    inboundTag: dnsViaBalancer ? dnsInboundTag : null,
  );

  config['routing'] = _routing(
    base?['routing'],
    settings,
    checkOutbound: checkPort > 0 ? proxyTag : null,
    checkBalancerTag: checkPort > 0 ? trafficBalancerTag : null,
    dnsBalancerTag: dnsViaBalancer ? trafficBalancerTag : null,
    dnsInboundTag: dnsInboundTag,
    balancers: balancers,
    catchAllBalancer: autoBalancerTag,
  );

  // Observatory нужен стратегиям leastPing/leastLoad и fallbackTag — без него
  // балансировщик не определит, какой сервер жив, и ядро не запустится.
  if (base?['observatory'] != null) {
    config['observatory'] = base!['observatory'];
  }
  if (base?['burstObservatory'] != null) {
    config['burstObservatory'] = base!['burstObservatory'];
  } else if ((autoBalancerTag != null || addedFallbackTag) &&
      base?['observatory'] == null) {
    config['burstObservatory'] = {
      'subjectSelector': [for (final outbound in proxies) Servers.tag(outbound)]
          .whereType<String>()
          .toList(),
      'pingConfig': {
        // Как и сторож/проверка: gstatic недоступен с части выходов, из-за
        // чего балансировщик ошибочно помечал живые узлы мёртвыми.
        'destination': 'https://cp.cloudflare.com/generate_204',
        'interval': '30s',
        'timeout': '5s',
        'sampling': 1,
      },
    };
  }

  return jsonEncode(config);
}

Map<String, dynamic> _dns(
  Object? panelDns,
  Settings settings,
  String? tag, {
  String? inboundTag,
}) {
  Map<String, dynamic>? rest;
  List<dynamic> servers;

  // По умолчанию берём DNS из подписки: он учитывает белые списки панели.
  // Резервный 77.88.8.8 используется, только если подписка не прислала DNS
  // или пользователь явно выбрал фиксированный адрес в настройках.
  final usePanelDns =
      settings.dnsUsePanel &&
      panelDns is Map &&
      (panelDns['servers'] as List?)?.isNotEmpty == true;

  if (usePanelDns) {
    rest = panelDns.cast<String, dynamic>();
    servers = rest['servers'] as List;
  } else {
    servers = [settings.dns, if (settings.dns != '8.8.8.8') '8.8.8.8'];
  }

  // Когда DNS идёт через балансировщик, все запросы должны нести один тег:
  // серверы панели со своим `tag` иначе уйдут на закреплённый outbound.
  final dnsTag = inboundTag ?? tag;
  final normalized = servers.map((server) {
    if (server is String) {
      return <String, dynamic>{'address': server, 'tag': ?dnsTag};
    }
    if (server is Map) {
      final advanced = server.cast<String, dynamic>();
      return <String, dynamic>{
        ...advanced,
        'tag': ?(dnsTag ?? advanced['tag']),
      };
    }
    return server;
  }).toList();

  return {
    ...?rest,
    'servers': normalized,
    'queryStrategy': (rest?['queryStrategy'] as String?) ?? 'UseIPv4',
    'tag': ?inboundTag,
  };
}

Map<String, dynamic> _routing(
  Object? panelRouting,
  Settings settings, {
  String? checkOutbound,
  String? checkBalancerTag,
  String? dnsBalancerTag,
  String? dnsInboundTag,
  required List<Map<String, dynamic>> balancers,
  String? catchAllBalancer,
}) {
  // DNS из туннеля всегда обрабатывает встроенный резолвер ядра.
  const dnsRule = <String, dynamic>{
    'type': 'field',
    'inboundTag': ['tun'],
    'port': '53',
    'outboundTag': 'dns-out',
  };

  Map<String, dynamic> routing;
  List<Map<String, dynamic>> rules;
  if (panelRouting is Map && panelRouting['rules'] is List) {
    // Копируем: ниже подставляем domainStrategy, не меняя исходный JSON подписки.
    routing = Map<String, dynamic>.from(panelRouting.cast<String, dynamic>());
    rules = (routing['rules'] as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    // В панельных конфигах domainStrategy часто отсутствует (по умолчанию
    // AsIs). Тогда IP-правила из белых списков никогда не срабатывают на
    // доменные подключения: TUN видит IP, сниффинг даёт домен, но IP-правило
    // уже не проверяется. IpIfNonMatch заставляет ядро резолвить домен, если
    // доменное правило не совпало, и затем проверить IP-белый список.
    routing['domainStrategy'] ??= rules.any((rule) => rule.containsKey('ip'))
        ? 'IpIfNonMatch'
        : 'AsIs';
  } else {
    routing = {'domainStrategy': 'AsIs'};
    rules = [
      if (settings.bypassLan)
        {
          'type': 'field',
          'ip': [
            '127.0.0.0/8',
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '169.254.0.0/16',
            '224.0.0.0/4',
            '::1/128',
            'fc00::/7',
            'fe80::/10',
            'ff00::/8',
          ],
          'outboundTag': 'direct',
        },
    ];
  }

  return {
    ...routing,
    'rules': [
      // Проверочный запрос идёт туда же, куда и обычный трафик: через
      // балансировщик с fallbackTag, а не через один закреплённый outbound.
      if (checkOutbound != null || checkBalancerTag != null)
        {
          'type': 'field',
          'inboundTag': ['check'],
          'outboundTag': ?(checkBalancerTag == null ? checkOutbound : null),
          'balancerTag': ?checkBalancerTag,
        },
      if (settings.tunnelMode.hasTun) dnsRule,
      // SOCKS5 идёт по тому же рабочему пути, что и check/TUN.
      if (settings.tunnelMode.hasProxy &&
          (checkOutbound != null || checkBalancerTag != null))
        {
          'type': 'field',
          'inboundTag': ['socks'],
          'outboundTag': ?(checkBalancerTag == null ? checkOutbound : null),
          'balancerTag': ?checkBalancerTag,
        },
      // DNS, сгенерированный ядром, тоже должен попадать в балансировщик.
      if (dnsBalancerTag != null && dnsInboundTag != null)
        {
          'type': 'field',
          'inboundTag': [dnsInboundTag],
          'balancerTag': dnsBalancerTag,
        },
      ...rules,
      // Правило панели с balancerTag имеет приоритет: добавленный балансир
      // подключается только когда панель не указала свой.
      if (catchAllBalancer != null)
        {
          'type': 'field',
          'network': 'tcp,udp',
          'balancerTag': catchAllBalancer,
        },
    ],
    if (balancers.isNotEmpty) 'balancers': balancers,
  };
}

List<Map<String, dynamic>> _panelBalancers(Map<String, dynamic>? base) {
  final routing = base?['routing'];
  if (routing is! Map || routing['balancers'] is! List) return const [];
  return (routing['balancers'] as List)
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
}

List<Map<String, dynamic>> _panelRules(Map<String, dynamic>? base) {
  final routing = base?['routing'];
  if (routing is! Map || routing['rules'] is! List) return const [];
  return (routing['rules'] as List)
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
}

/// Запасной outbound для балансировщика без `fallbackTag`: первый прокси, не
/// покрытый его селектором. В Remnawave это как раз тег `proxy`.
String? _firstUnselectedProxy(
  Object? selector,
  List<Map<String, dynamic>> proxies,
) {
  final prefixes = selector is List
      ? selector.whereType<String>()
      : const <String>[];
  for (final outbound in proxies) {
    final tag = Servers.tag(outbound);
    if (tag == null) continue;
    if (prefixes.any(tag.startsWith)) continue;
    return tag;
  }
  return null;
}

String? _proxyTag(
  List<Map<String, dynamic>> proxies,
  Set<String> fallbackTags,
) {
  for (final outbound in proxies) {
    final tag = Servers.tag(outbound);
    if (tag == null || fallbackTags.contains(tag)) continue;
    return tag;
  }
  // Один outbound — скорее всего это и есть запасной хост; всё равно он нужен
  // для DNS и локальной проверки.
  for (final outbound in proxies) {
    final tag = Servers.tag(outbound);
    if (tag != null) return tag;
  }
  return null;
}

bool _hasTag(List<Map<String, dynamic>> outbounds, String tag) =>
    outbounds.any((outbound) => outbound['tag'] == tag);
