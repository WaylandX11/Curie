/// Сервер. Приходит либо ссылкой (`vless://…`), либо готовым JSON-узлом
/// из JSON-подписки — второй случай основной для Remnawave.
class Profile {
  const Profile({
    required this.name,
    this.link,
    this.configJson,
    this.address,
    this.port,
    this.subscriptionUrl,
    this.protocol,
    this.network,
    this.security,
    this.hasBalancer = false,
  });

  final String name;

  /// Ссылка провайдера, если узел пришёл ссылкой.
  final String? link;

  /// Готовый JSON узла (`{"outbounds":[…]}`), если подписка отдала JSON.
  final String? configJson;

  final String? address;
  final int? port;
  final String? subscriptionUrl;

  /// Для подписей в списке: vless, trojan, shadowsocks…
  final String? protocol;
  final String? network;
  final String? security;

  /// Конфиг узла содержит балансировщик (несколько серверов под одним именем).
  final bool hasBalancer;

  bool get isJson => configJson != null;

  Profile copyWith({
    String? name,
    String? link,
    String? configJson,
    String? address,
    int? port,
    String? subscriptionUrl,
    String? protocol,
    String? network,
    String? security,
    bool? hasBalancer,
  }) =>
      Profile(
        name: name ?? this.name,
        link: link ?? this.link,
        configJson: configJson ?? this.configJson,
        address: address ?? this.address,
        port: port ?? this.port,
        subscriptionUrl: subscriptionUrl ?? this.subscriptionUrl,
        protocol: protocol ?? this.protocol,
        network: network ?? this.network,
        security: security ?? this.security,
        hasBalancer: hasBalancer ?? this.hasBalancer,
      );

  /// Ссылка уникальна; JSON-узел опознаём по подписке и имени — они стабильны
  /// между обновлениями, в отличие от самого конфига.
  String get id => link ?? '${subscriptionUrl ?? ''}#$name';

  /// Короткая строка вида `VLESS · XHTTP · TLS · JSON`.
  List<String> get chips => [
        if (protocol != null) protocol!.toUpperCase(),
        if (network != null && network != 'tcp') network!.toUpperCase(),
        if (security != null && security != 'none') security!.toUpperCase(),
        if (isJson) 'JSON',
      ];

  Map<String, dynamic> toJson() => {
        'name': name,
        if (link != null) 'link': link,
        if (configJson != null) 'configJson': configJson,
        if (address != null) 'address': address,
        if (port != null) 'port': port,
        if (subscriptionUrl != null) 'subscriptionUrl': subscriptionUrl,
        if (protocol != null) 'protocol': protocol,
        if (network != null) 'network': network,
        if (security != null) 'security': security,
        if (hasBalancer) 'hasBalancer': true,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        name: (json['name'] as String?) ?? '',
        link: json['link'] as String?,
        configJson: json['configJson'] as String?,
        address: json['address'] as String?,
        port: (json['port'] as num?)?.toInt(),
        subscriptionUrl: json['subscriptionUrl'] as String?,
        protocol: json['protocol'] as String?,
        network: json['network'] as String?,
        security: json['security'] as String?,
        hasBalancer: (json['hasBalancer'] as bool?) ?? false,
      );
}

/// Разбирает один outbound в профиль-ссылку (когда ядро вернуло JSON по ссылке).
Profile profileFromOutbound({
  required String link,
  required Map<String, dynamic> outbound,
  required String fallbackName,
  String? subscriptionUrl,
}) {
  final tag = (outbound['tag'] as String?)?.trim();
  final details = outboundDetails(outbound);

  return Profile(
    link: link,
    name: (tag != null && tag.isNotEmpty) ? tag : fallbackName,
    address: details.address,
    port: details.port,
    subscriptionUrl: subscriptionUrl,
    protocol: details.protocol,
    network: details.network,
    security: details.security,
  );
}

class OutboundDetails {
  const OutboundDetails({
    this.address,
    this.port,
    this.protocol,
    this.network,
    this.security,
  });

  final String? address;
  final int? port;
  final String? protocol;
  final String? network;
  final String? security;
}

OutboundDetails outboundDetails(Map<String, dynamic> outbound) {
  final settings =
      (outbound['settings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final stream =
      (outbound['streamSettings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

  final server = _firstServer(settings, 'vnext') ?? _firstServer(settings, 'servers');

  return OutboundDetails(
    address: (server?['address'] as String?) ?? (settings['address'] as String?),
    port: (server?['port'] as num?)?.toInt() ?? (settings['port'] as num?)?.toInt(),
    protocol: outbound['protocol'] as String?,
    network: (stream['network'] as String?) ?? 'tcp',
    security: stream['security'] as String?,
  );
}

Map<String, dynamic>? _firstServer(Map<String, dynamic> settings, String key) {
  final list = settings[key];
  if (list is List && list.isNotEmpty) {
    final first = list.first;
    if (first is Map) return first.cast<String, dynamic>();
  }
  return null;
}
