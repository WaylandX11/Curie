import 'dart:convert';
import 'dart:math';

/// Как поднимается локальный доступ к туннелю.
enum TunnelMode {
  /// Только системный TUN-интерфейс.
  tun,

  /// TUN и локальный SOCKS5 для других приложений.
  tunProxy,

  /// Только локальный SOCKS5, без TUN-интерфейса.
  proxy;

  static TunnelMode fromName(String? name) => switch (name) {
    'tunProxy' || 'tun_proxy' || 'tun-proxy' => TunnelMode.tunProxy,
    'proxy' || 'socks' => TunnelMode.proxy,
    _ => TunnelMode.tun,
  };

  String get wireName => switch (this) {
    TunnelMode.tun => 'tun',
    TunnelMode.tunProxy => 'tunProxy',
    TunnelMode.proxy => 'proxy',
  };

  /// Нужен ли системный TUN (и разрешение VpnService).
  bool get hasTun => this != TunnelMode.proxy;

  /// Нужен ли локальный SOCKS5-вход.
  bool get hasProxy => this != TunnelMode.tun;
}

/// Порт и пароль SOCKS5 создаются один раз при первом запуске и затем
/// хранятся в зашифрованном состоянии. `null` в модели означает «ещё не
/// созданы» — так const-конструктор остаётся доступным для тестов.
int _randomSocksPort() => 20000 + _socksRandom.nextInt(20000);

final Random _socksRandom = Random.secure();

int? _generatedSocksPort;

int defaultSocksPort() => _generatedSocksPort ??= _randomSocksPort();

String _randomSocksPassword() => base64Url.encode(
  List<int>.generate(18, (_) => _socksRandom.nextInt(256)),
).replaceAll('=', '');

String? _generatedSocksPassword;

String defaultSocksPassword() =>
    _generatedSocksPassword ??= _randomSocksPassword();

const String defaultSocksUsername = 'curie';

/// Как показывать несколько подписок на главном экране.
enum SubscriptionsLayout {
  /// Листание: одна подписка на экран, переключение свайпом (как фото).
  pager,
  /// Все подписки друг за другом на одном экране.
  list;

  static SubscriptionsLayout fromName(String? name) =>
      name == 'list' ? SubscriptionsLayout.list : SubscriptionsLayout.pager;

  String get wireName => name;
}

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

/// Уровень журнала ядра. Значения совпадают с `log.logLevel` в Xray-core:
/// `debug`, `info`, `warning`, `error`, `none`.
enum XrayLogLevel {
  debug,
  info,
  warning,
  error,
  none;

  static XrayLogLevel fromName(String? name) => switch (name) {
    'debug' => XrayLogLevel.debug,
    'info' => XrayLogLevel.info,
    'error' => XrayLogLevel.error,
    'none' => XrayLogLevel.none,
    _ => XrayLogLevel.warning,
  };

  String get wireName => name;
}

class Settings {
  /// Резервный DNS на случай, когда подписка не прислала свои серверы.
  /// По умолчанию нейтральный публичный адрес; 77.88.8.8 (Яндекс) используется
  /// только если пользователь выбрал его явно.
  static const defaultDns = '8.8.8.8';

  /// Значение по умолчанию в старых версиях — нужно только для миграции.
  static const legacyDefaultDns = '1.1.1.1';

  /// Ревизия значений по умолчанию: когда она увеличивается, новые значения
  /// применяются один раз и к уже сохранённым настройкам.
  static const int currentDefaultsRevision = 3;

  /// Тестовая страница для замера через узел.
  static const defaultPingUrl = 'https://www.gstatic.com/generate_204';
  static const minPingTimeout = 5;
  static const maxPingTimeout = 15;

  /// Ручной интервал автообновления подписок. Панель всё равно сообщает свой
  /// `profile-update-interval`, но пользовательский выбор важнее.
  static const defaultSubscriptionUpdateHours = 12;
  static const minSubscriptionUpdateHours = 1;
  static const maxSubscriptionUpdateHours = 168;

  /// Журнал ядра пишется в приватный каталог приложения и очищается по времени.
  static const defaultLogRetentionHours = 24;
  static const minLogRetentionHours = 1;
  static const maxLogRetentionHours = 168;

  /// Источники geoip.dat/geosite.dat проекта russia-blocked. Пользователь может
  /// заменить каждый адрес своим или подгрузить файл вручную.
  static const defaultGeoipUrl =
      'https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/release/geoip.dat';
  static const defaultGeositeUrl =
      'https://raw.githubusercontent.com/runetfreedom/russia-blocked-geosite/release/geosite.dat';
  static const defaultGeoAssetsUpdateHours = 24;
  static const minGeoAssetsUpdateHours = 1;
  static const maxGeoAssetsUpdateHours = 168;

  const Settings({
    this.tunnelMode = TunnelMode.tun,
    this.useRustCore = false,
    this.subscriptionsLayout = SubscriptionsLayout.list,
    this.routingMode = RoutingMode.all,
    this.allowedApps = const [],
    this.bypassedApps = const [],
    this.dns = defaultDns,
    this.dnsUsePanel = true,
    this.dnsRoute = DnsRoute.tunnel,
    this.bypassLan = true,
    this.geoAssetsAutoUpdate = true,
    this.geoAssetsWifiOnly = true,
    this.geoAssetsRestartXray = true,
    this.geoAssetsUpdateHours = defaultGeoAssetsUpdateHours,
    this.geoipUrl = defaultGeoipUrl,
    this.geositeUrl = defaultGeositeUrl,
    this.geoAssetsPromptShown = false,
    this.geoipUpdatedAt,
    this.geositeUpdatedAt,
    this.geoipSha256,
    this.geositeSha256,
    this.autoUpdateSubscriptions = true,
    this.subscriptionUpdateHours = defaultSubscriptionUpdateHours,
    this.sendHwid = true,
    this.pingMode = PingMode.proxy,
    this.pingProfile = PingProfile.single,
    this.pingTimeoutSeconds = minPingTimeout,
    this.pingUrl = defaultPingUrl,
    this.mtu = 1500,
    this.socksPort,
    this.socksUsername = defaultSocksUsername,
    this.socksPassword,
    this.socksAuth = true,
    this.xrayLogEnabled = true,
    this.xrayLogLevel = XrayLogLevel.warning,
    this.xrayLogRetentionHours = defaultLogRetentionHours,
    this.lastUpdateCheckAt,
    this.lastNotifiedCoreVersion,
    this.pendingUpdate,
    this.defaultsRevision = currentDefaultsRevision,
  });

  final TunnelMode tunnelMode;

  /// Экспериментальное Rust-ядро. По умолчанию выключено: обычные подключения
  /// идут через встроенный Xray-core из libXray.
  final bool useRustCore;

  /// Как показывать несколько подписок на главном экране.
  final SubscriptionsLayout subscriptionsLayout;

  final RoutingMode routingMode;
  final List<String> allowedApps;
  final List<String> bypassedApps;
  final String dns;

  /// true — брать серверы из JSON подписки. Это значение по умолчанию:
  /// адрес из панели учитывает её белые списки и настройки провайдера.
  final bool dnsUsePanel;
  final DnsRoute dnsRoute;
  final bool bypassLan;

  /// Обновление geoip.dat/geosite.dat, нужных правилам geoip:/geosite:.
  final bool geoAssetsAutoUpdate;
  final bool geoAssetsWifiOnly;
  final bool geoAssetsRestartXray;
  final int geoAssetsUpdateHours;
  final String geoipUrl;
  final String geositeUrl;
  final bool geoAssetsPromptShown;
  final DateTime? geoipUpdatedAt;
  final DateTime? geositeUpdatedAt;
  final String? geoipSha256;
  final String? geositeSha256;

  final bool autoUpdateSubscriptions;

  /// Во сколько часов обновлять подписки, когда автообновление включено.
  /// Перекрывает интервал из заголовка панели.
  final int subscriptionUpdateHours;

  /// Отправлять панели идентификатор устройства. Включено по умолчанию:
  /// многие панели требуют HWID для лимита устройств. Отключается в настройках.
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

  /// Настройки локального SOCKS5. Порт и пароль создаются один раз и
  /// сохраняются; `null` означает, что генерация ещё не произошла.
  final int? socksPort;
  final String socksUsername;
  final String? socksPassword;
  final bool socksAuth;

  /// Писать ошибки и предупреждения ядра в приватный файл. Адреса в журнале
  /// маскируются конфигом Xray (`maskAddress`).
  final bool xrayLogEnabled;
  final XrayLogLevel xrayLogLevel;
  final int xrayLogRetentionHours;

  /// Служебные отметки для проверки обновлений раз в сутки и правила
  /// «один диалог на версию ядра».
  final DateTime? lastUpdateCheckAt;
  final String? lastNotifiedCoreVersion;

  /// Сериализованный `GithubRelease`, который показываем баннером на главной.
  /// Живёт в зашифрованном состоянии, чтобы баннер переживал перезапуск.
  final String? pendingUpdate;

  /// Служебное поле для одноразовой миграции значений по умолчанию.
  final int defaultsRevision;

  List<String> get selectedApps =>
      routingMode == RoutingMode.onlySelected ? allowedApps : bypassedApps;

  int get effectiveSocksPort => socksPort ?? defaultSocksPort();

  String get effectiveSocksPassword =>
      socksPassword ?? defaultSocksPassword();

  /// Materialize one-time generated credentials so they are persisted in the
  /// encrypted state instead of changing between launches.
  Settings materializeSocksDefaults() {
    if (socksPort != null && socksPassword != null) return this;
    return copyWith(
      socksPort: socksPort ?? defaultSocksPort(),
      socksPassword: socksPassword ?? defaultSocksPassword(),
    );
  }

  Settings copyWith({
    TunnelMode? tunnelMode,
    bool? useRustCore,
    SubscriptionsLayout? subscriptionsLayout,
    RoutingMode? routingMode,
    List<String>? allowedApps,
    List<String>? bypassedApps,
    String? dns,
    bool? dnsUsePanel,
    DnsRoute? dnsRoute,
    bool? bypassLan,
    bool? geoAssetsAutoUpdate,
    bool? geoAssetsWifiOnly,
    bool? geoAssetsRestartXray,
    int? geoAssetsUpdateHours,
    String? geoipUrl,
    String? geositeUrl,
    bool? geoAssetsPromptShown,
    DateTime? geoipUpdatedAt,
    DateTime? geositeUpdatedAt,
    String? geoipSha256,
    String? geositeSha256,
    bool? autoUpdateSubscriptions,
    int? subscriptionUpdateHours,
    bool? sendHwid,
    PingMode? pingMode,
    PingProfile? pingProfile,
    int? pingTimeoutSeconds,
    String? pingUrl,
    int? mtu,
    int? socksPort,
    String? socksUsername,
    String? socksPassword,
    bool? socksAuth,
    bool? xrayLogEnabled,
    XrayLogLevel? xrayLogLevel,
    int? xrayLogRetentionHours,
    DateTime? lastUpdateCheckAt,
    String? lastNotifiedCoreVersion,
    String? pendingUpdate,
    bool clearPendingUpdate = false,
    int? defaultsRevision,
  }) => Settings(
    tunnelMode: tunnelMode ?? this.tunnelMode,
    useRustCore: useRustCore ?? this.useRustCore,
    subscriptionsLayout: subscriptionsLayout ?? this.subscriptionsLayout,
    routingMode: routingMode ?? this.routingMode,
    allowedApps: allowedApps ?? this.allowedApps,
    bypassedApps: bypassedApps ?? this.bypassedApps,
    dns: dns ?? this.dns,
    dnsUsePanel: dnsUsePanel ?? this.dnsUsePanel,
    dnsRoute: dnsRoute ?? this.dnsRoute,
    bypassLan: bypassLan ?? this.bypassLan,
    geoAssetsAutoUpdate: geoAssetsAutoUpdate ?? this.geoAssetsAutoUpdate,
    geoAssetsWifiOnly: geoAssetsWifiOnly ?? this.geoAssetsWifiOnly,
    geoAssetsRestartXray: geoAssetsRestartXray ?? this.geoAssetsRestartXray,
    geoAssetsUpdateHours: geoAssetsUpdateHours ?? this.geoAssetsUpdateHours,
    geoipUrl: geoipUrl ?? this.geoipUrl,
    geositeUrl: geositeUrl ?? this.geositeUrl,
    geoAssetsPromptShown: geoAssetsPromptShown ?? this.geoAssetsPromptShown,
    geoipUpdatedAt: geoipUpdatedAt ?? this.geoipUpdatedAt,
    geositeUpdatedAt: geositeUpdatedAt ?? this.geositeUpdatedAt,
    geoipSha256: geoipSha256 ?? this.geoipSha256,
    geositeSha256: geositeSha256 ?? this.geositeSha256,
    autoUpdateSubscriptions:
        autoUpdateSubscriptions ?? this.autoUpdateSubscriptions,
    subscriptionUpdateHours:
        subscriptionUpdateHours ?? this.subscriptionUpdateHours,
    sendHwid: sendHwid ?? this.sendHwid,
    pingMode: pingMode ?? this.pingMode,
    pingProfile: pingProfile ?? this.pingProfile,
    pingTimeoutSeconds: pingTimeoutSeconds ?? this.pingTimeoutSeconds,
    pingUrl: pingUrl ?? this.pingUrl,
    mtu: mtu ?? this.mtu,
    socksPort: socksPort ?? this.socksPort,
    socksUsername: socksUsername ?? this.socksUsername,
    socksPassword: socksPassword ?? this.socksPassword,
    socksAuth: socksAuth ?? this.socksAuth,
    xrayLogEnabled: xrayLogEnabled ?? this.xrayLogEnabled,
    xrayLogLevel: xrayLogLevel ?? this.xrayLogLevel,
    xrayLogRetentionHours: xrayLogRetentionHours ?? this.xrayLogRetentionHours,
    lastUpdateCheckAt: lastUpdateCheckAt ?? this.lastUpdateCheckAt,
    lastNotifiedCoreVersion:
        lastNotifiedCoreVersion ?? this.lastNotifiedCoreVersion,
    pendingUpdate: clearPendingUpdate
        ? null
        : (pendingUpdate ?? this.pendingUpdate),
    defaultsRevision: defaultsRevision ?? this.defaultsRevision,
  );

  Map<String, dynamic> toJson() => {
    'tunnelMode': tunnelMode.wireName,
    'useRustCore': useRustCore,
    'subscriptionsLayout': subscriptionsLayout.wireName,
    'routingMode': routingMode.name,
    'allowedApps': allowedApps,
    'bypassedApps': bypassedApps,
    'dns': dns,
    'dnsUsePanel': dnsUsePanel,
    'dnsRoute': dnsRoute.wireName,
    'bypassLan': bypassLan,
    'geoAssetsAutoUpdate': geoAssetsAutoUpdate,
    'geoAssetsWifiOnly': geoAssetsWifiOnly,
    'geoAssetsRestartXray': geoAssetsRestartXray,
    'geoAssetsUpdateHours': geoAssetsUpdateHours,
    'geoipUrl': geoipUrl,
    'geositeUrl': geositeUrl,
    'geoAssetsPromptShown': geoAssetsPromptShown,
    if (geoipUpdatedAt != null)
      'geoipUpdatedAt': geoipUpdatedAt!.millisecondsSinceEpoch,
    if (geositeUpdatedAt != null)
      'geositeUpdatedAt': geositeUpdatedAt!.millisecondsSinceEpoch,
    if (geoipSha256 != null) 'geoipSha256': geoipSha256,
    if (geositeSha256 != null) 'geositeSha256': geositeSha256,
    'autoUpdateSubscriptions': autoUpdateSubscriptions,
    'subscriptionUpdateHours': subscriptionUpdateHours,
    'sendHwid': sendHwid,
    'pingMode': pingMode.wireName,
    'pingProfile': pingProfile.wireName,
    'pingTimeoutSeconds': pingTimeoutSeconds,
    'pingUrl': pingUrl,
    'mtu': mtu,
    if (socksPort != null) 'socksPort': socksPort,
    'socksUsername': socksUsername,
    if (socksPassword != null) 'socksPassword': socksPassword,
    'socksAuth': socksAuth,
    'xrayLogEnabled': xrayLogEnabled,
    'xrayLogLevel': xrayLogLevel.wireName,
    'xrayLogRetentionHours': xrayLogRetentionHours,
    if (lastUpdateCheckAt != null)
      'lastUpdateCheckAt': lastUpdateCheckAt!.millisecondsSinceEpoch,
    if (lastNotifiedCoreVersion != null)
      'lastNotifiedCoreVersion': lastNotifiedCoreVersion,
    if (pendingUpdate != null) 'pendingUpdate': pendingUpdate,
    'defaultsRevision': defaultsRevision,
  };

  factory Settings.fromJson(Map<String, dynamic> json) {
    final savedDns = json['dns'] as String?;
    final legacyDefault = savedDns == legacyDefaultDns;
    final savedTimeout = (json['pingTimeoutSeconds'] as num?)?.toInt();
    final savedPingUrl = json['pingUrl'] as String?;
    final hours =
        (json['subscriptionUpdateHours'] as num?)?.toInt() ??
        defaultSubscriptionUpdateHours;
    final retention =
        (json['xrayLogRetentionHours'] as num?)?.toInt() ??
        defaultLogRetentionHours;
    final savedRevision = (json['defaultsRevision'] as num?)?.toInt() ?? 0;
    final upgradeDefaults = savedRevision < currentDefaultsRevision;
    final geoHours =
        (json['geoAssetsUpdateHours'] as num?)?.toInt() ??
        defaultGeoAssetsUpdateHours;
    DateTime? savedDate(String key) {
      final value = json[key];
      if (value == null) return null;
      return DateTime.fromMillisecondsSinceEpoch((value as num).toInt());
    }

    String savedUrl(String key, String fallback) {
      final value = (json[key] as String?)?.trim();
      if (upgradeDefaults || value == null || value.isEmpty) return fallback;
      return value;
    }

    // Старый адрес по умолчанию не считается осознанным выбором пользователя.
    final oldDefaultDns =
        savedDns == null ||
        savedDns.isEmpty ||
        legacyDefault ||
        savedDns == '77.88.8.8' ||
        savedDns == defaultDns;
    final savedPort = (json['socksPort'] as num?)?.toInt();
    final savedPassword = json['socksPassword'] as String?;
    return Settings(
      tunnelMode: TunnelMode.fromName(json['tunnelMode'] as String?),
      useRustCore: (json['useRustCore'] as bool?) ?? false,
      subscriptionsLayout: SubscriptionsLayout.fromName(
        json['subscriptionsLayout'] as String?,
      ),
      routingMode: RoutingMode.fromName(json['routingMode'] as String?),
      allowedApps: ((json['allowedApps'] as List?) ?? const []).cast<String>(),
      bypassedApps: ((json['bypassedApps'] as List?) ?? const [])
          .cast<String>(),
      // Старое значение по умолчанию мигрирует на резервный адрес.
      dns: (savedDns == null || savedDns.isEmpty || legacyDefault)
          ? defaultDns
          : savedDns,
      // Раньше по умолчанию был фиксированный 77.88.8.8. Теперь DNS берётся
      // из подписки; пользователи со старым адресом переключаются один раз.
      dnsUsePanel: (upgradeDefaults && oldDefaultDns)
          ? true
          : (json['dnsUsePanel'] as bool? ?? true),
      dnsRoute: DnsRoute.fromName(json['dnsRoute'] as String?),
      bypassLan: (json['bypassLan'] as bool?) ?? true,
      geoAssetsAutoUpdate: upgradeDefaults
          ? true
          : ((json['geoAssetsAutoUpdate'] as bool?) ?? true),
      geoAssetsWifiOnly: upgradeDefaults
          ? true
          : ((json['geoAssetsWifiOnly'] as bool?) ?? true),
      geoAssetsRestartXray: upgradeDefaults
          ? true
          : ((json['geoAssetsRestartXray'] as bool?) ?? true),
      geoAssetsUpdateHours: geoHours < minGeoAssetsUpdateHours
          ? minGeoAssetsUpdateHours
          : (geoHours > maxGeoAssetsUpdateHours
                ? maxGeoAssetsUpdateHours
                : geoHours),
      geoipUrl: savedUrl('geoipUrl', defaultGeoipUrl),
      geositeUrl: savedUrl('geositeUrl', defaultGeositeUrl),
      geoAssetsPromptShown: upgradeDefaults
          ? false
          : ((json['geoAssetsPromptShown'] as bool?) ?? false),
      geoipUpdatedAt: savedDate('geoipUpdatedAt'),
      geositeUpdatedAt: savedDate('geositeUpdatedAt'),
      geoipSha256: json['geoipSha256'] as String?,
      geositeSha256: json['geositeSha256'] as String?,
      autoUpdateSubscriptions:
          (json['autoUpdateSubscriptions'] as bool?) ?? true,
      subscriptionUpdateHours: hours < minSubscriptionUpdateHours
          ? minSubscriptionUpdateHours
          : (hours > maxSubscriptionUpdateHours
                ? maxSubscriptionUpdateHours
                : hours),
      // HWID включаем и для уже установленных приложений, но только один раз:
      // последующий ручной выключатель остаётся в силе.
      sendHwid: upgradeDefaults ? true : (json['sendHwid'] as bool? ?? true),
      pingMode: PingMode.fromName(json['pingMode'] as String?),
      pingProfile: PingProfile.fromName(json['pingProfile'] as String?),
      pingTimeoutSeconds: savedTimeout == null
          ? minPingTimeout
          : (savedTimeout < minPingTimeout
                ? minPingTimeout
                : (savedTimeout > maxPingTimeout
                      ? maxPingTimeout
                      : savedTimeout)),
      pingUrl: (savedPingUrl == null || savedPingUrl.trim().isEmpty)
          ? defaultPingUrl
          : savedPingUrl.trim(),
      mtu: (json['mtu'] as num?)?.toInt() ?? 1500,
      socksPort:
          savedPort == null || savedPort < 1024 || savedPort > 65535
              ? defaultSocksPort()
              : savedPort,
      socksUsername:
          (json['socksUsername'] as String?) ?? defaultSocksUsername,
      socksPassword: savedPassword ?? defaultSocksPassword(),
      socksAuth: (json['socksAuth'] as bool?) ?? true,
      xrayLogEnabled: (json['xrayLogEnabled'] as bool?) ?? true,
      xrayLogLevel: XrayLogLevel.fromName(json['xrayLogLevel'] as String?),
      xrayLogRetentionHours: retention < minLogRetentionHours
          ? minLogRetentionHours
          : (retention > maxLogRetentionHours
                ? maxLogRetentionHours
                : retention),
      lastUpdateCheckAt: json['lastUpdateCheckAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (json['lastUpdateCheckAt'] as num).toInt(),
            ),
      lastNotifiedCoreVersion: json['lastNotifiedCoreVersion'] as String?,
      pendingUpdate: json['pendingUpdate'] as String?,
      defaultsRevision: currentDefaultsRevision,
    );
  }
}
