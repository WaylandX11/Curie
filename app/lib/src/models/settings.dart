/// Как приложения попадают в туннель.
enum RoutingMode {
  /// Через прокси идёт всё.
  all,

  /// В туннель только выбранные приложения, остальные напрямую.
  onlySelected,

  /// Выбранные приложения идут напрямую, остальные через прокси.
  bypassSelected;

  /// Принимает и имя из хранилища, и короткое имя из платформенного канала.
  static RoutingMode fromName(String? name) => switch (name) {
        'onlySelected' || 'only' => RoutingMode.onlySelected,
        'bypassSelected' || 'bypass' => RoutingMode.bypassSelected,
        _ => RoutingMode.all,
      };

  /// Имя для платформенного канала.
  String get wireName => switch (this) {
        RoutingMode.all => 'all',
        RoutingMode.onlySelected => 'only',
        RoutingMode.bypassSelected => 'bypass',
      };
}

/// Как мерить задержку до узла.
enum PingMode {
  /// TCP connect до адреса:порта сервера. Для TLS/REALITY дополнительно
  /// выполняется TLS-рукопожатие с настоящим SNI: так видны узлы, которые
  /// провайдер режет по имени, хотя TCP-порт у них открыт.
  tcp,

  /// GET-запрос через сам узел (libXray `pingBatch`): честная задержка,
  /// включая DNS, TCP и TLS-handshake.
  proxy;

  static PingMode fromName(String? name) => switch (name) {
        'tcp' => PingMode.tcp,
        // 'icmp' больше не поддерживается телефонами, 'http' означало замер
        // через узел. Старые настройки мигрируют на рабочие режимы.
        'icmp' => PingMode.tcp,
        _ => PingMode.proxy,
      };

  String get wireName => name;
}

/// Как именно делать замер через узел (как режимы в Happ).
enum PingProfile {
  /// Один запрос на новом соединении.
  single,

  /// Два запроса, берётся лучший результат (keep-alive не используется).
  double,

  /// Два запроса в одном соединении/транспорте — чистое время ответа.
  keepAlive;

  static PingProfile fromName(String? name) => switch (name) {
        'double' => PingProfile.double,
        'keepAlive' => PingProfile.keepAlive,
        _ => PingProfile.single,
      };

  String get wireName => name;
}

/// Куда отправлять DNS-запросы, пришедшие из туннеля.
///
/// По умолчанию — через прокси: провайдер не видит имена сайтов, а белые
/// списки панели не обрывают резолвинг. `direct` оставляет резолвинг на
/// защищённый системный сокет, если прокси не умеет UDP DNS.
enum DnsRoute {
  tunnel,
  direct;

  static DnsRoute fromName(String? name) =>
      name == 'direct' ? DnsRoute.direct : DnsRoute.tunnel;

  String get wireName => name;
}

class Settings {
  /// Yandex DNS: доступен и через прокси, и напрямую, часто лежит в белых
  /// списках панелей. 1.1.1.1/8.8.8.8 у многих провайдеров режутся.
  static const defaultDns = '77.88.8.8';

  /// Значение по умолчанию в старых версиях — нужно только для миграции.
  static const legacyDefaultDns = '1.1.1.1';

  /// Тестовая страница для замера через узел.
  static const defaultPingUrl = 'https://www.gstatic.com/generate_204';
  static const minPingTimeout = 5;
  static const maxPingTimeout = 15;

  const Settings({
    this.routingMode = RoutingMode.all,
    this.allowedApps = const [],
    this.bypassedApps = const [],
    this.dns = defaultDns,
    this.dnsUsePanel = false,
    this.dnsRoute = DnsRoute.tunnel,
    this.bypassLan = true,
    this.autoUpdateSubscriptions = true,
    this.sendHwid = false,
    this.pingMode = PingMode.proxy,
    this.pingProfile = PingProfile.single,
    this.pingTimeoutSeconds = minPingTimeout,
    this.pingUrl = defaultPingUrl,
    this.mtu = 1500,
  });

  final RoutingMode routingMode;
  final List<String> allowedApps;
  final List<String> bypassedApps;
  final String dns;

  /// true — брать серверы из JSON подписки. По умолчанию false: надёжный
  /// `77.88.8.8` важнее того, что прописала панель (у многих он единственный,
  /// кто не режется провайдером и не вылетает из белых списков).
  final bool dnsUsePanel;
  final DnsRoute dnsRoute;
  final bool bypassLan;
  final bool autoUpdateSubscriptions;

  /// Отправлять панели идентификатор устройства. Выключено по умолчанию:
  /// это лишние данные о пользователе, включать стоит только если панель
  /// требует HWID (лимит устройств).
  final bool sendHwid;

  /// Чем мерить задержку узлов.
  final PingMode pingMode;

  /// Режим замера через узел: один запрос, лучший из двух, keep-alive.
  final PingProfile pingProfile;

  /// Тайм-аут одного замера, секунды (5–15).
  final int pingTimeoutSeconds;

  /// URL, который запрашивает узел при замере.
  final String pingUrl;

  final int mtu;

  List<String> get selectedApps =>
      routingMode == RoutingMode.onlySelected ? allowedApps : bypassedApps;

  Settings copyWith({
    RoutingMode? routingMode,
    List<String>? allowedApps,
    List<String>? bypassedApps,
    String? dns,
    bool? dnsUsePanel,
    DnsRoute? dnsRoute,
    bool? bypassLan,
    bool? autoUpdateSubscriptions,
    bool? sendHwid,
    PingMode? pingMode,
    PingProfile? pingProfile,
    int? pingTimeoutSeconds,
    String? pingUrl,
    int? mtu,
  }) =>
      Settings(
        routingMode: routingMode ?? this.routingMode,
        allowedApps: allowedApps ?? this.allowedApps,
        bypassedApps: bypassedApps ?? this.bypassedApps,
        dns: dns ?? this.dns,
        dnsUsePanel: dnsUsePanel ?? this.dnsUsePanel,
        dnsRoute: dnsRoute ?? this.dnsRoute,
        bypassLan: bypassLan ?? this.bypassLan,
        autoUpdateSubscriptions: autoUpdateSubscriptions ?? this.autoUpdateSubscriptions,
        sendHwid: sendHwid ?? this.sendHwid,
        pingMode: pingMode ?? this.pingMode,
        pingProfile: pingProfile ?? this.pingProfile,
        pingTimeoutSeconds: pingTimeoutSeconds ?? this.pingTimeoutSeconds,
        pingUrl: pingUrl ?? this.pingUrl,
        mtu: mtu ?? this.mtu,
      );

  Map<String, dynamic> toJson() => {
        'routingMode': routingMode.name,
        'allowedApps': allowedApps,
        'bypassedApps': bypassedApps,
        'dns': dns,
        'dnsUsePanel': dnsUsePanel,
        'dnsRoute': dnsRoute.wireName,
        'bypassLan': bypassLan,
        'autoUpdateSubscriptions': autoUpdateSubscriptions,
        'sendHwid': sendHwid,
        'pingMode': pingMode.wireName,
        'pingProfile': pingProfile.wireName,
        'pingTimeoutSeconds': pingTimeoutSeconds,
        'pingUrl': pingUrl,
        'mtu': mtu,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    final savedDns = json['dns'] as String?;
    final legacyDefault = savedDns == legacyDefaultDns;
    final savedTimeout = (json['pingTimeoutSeconds'] as num?)?.toInt();
    final savedUrl = json['pingUrl'] as String?;
    return Settings(
      routingMode: RoutingMode.fromName(json['routingMode'] as String?),
      allowedApps: ((json['allowedApps'] as List?) ?? const []).cast<String>(),
      bypassedApps: ((json['bypassedApps'] as List?) ?? const []).cast<String>(),
      // Старое значение по умолчанию мигрирует на рабочий Yandex DNS.
      dns: (savedDns == null || savedDns.isEmpty || legacyDefault)
          ? defaultDns
          : savedDns,
      // Раньше DNS панели всегда перекрывал пользовательский, когда был в JSON.
      // Теперь по умолчанию используем надёжный адрес приложения — это и есть
      // исправление проблемы, из-за которой сайты не грузились без ручной
      // настройки 77.88.8.8.
      dnsUsePanel: json['dnsUsePanel'] as bool? ?? false,
      dnsRoute: DnsRoute.fromName(json['dnsRoute'] as String?),
      bypassLan: (json['bypassLan'] as bool?) ?? true,
      autoUpdateSubscriptions: (json['autoUpdateSubscriptions'] as bool?) ?? true,
      sendHwid: (json['sendHwid'] as bool?) ?? false,
      pingMode: PingMode.fromName(json['pingMode'] as String?),
      pingProfile: PingProfile.fromName(json['pingProfile'] as String?),
      pingTimeoutSeconds: savedTimeout == null
          ? minPingTimeout
          : (savedTimeout < minPingTimeout
              ? minPingTimeout
              : (savedTimeout > maxPingTimeout ? maxPingTimeout : savedTimeout)),
      pingUrl: (savedUrl == null || savedUrl.trim().isEmpty)
          ? defaultPingUrl
          : savedUrl.trim(),
      mtu: (json['mtu'] as num?)?.toInt() ?? 1500,
    );
  }
}
