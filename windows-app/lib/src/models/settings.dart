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
  /// Само значение по умолчанию теперь — DNS из подписки (`dnsUsePanel`).
  static const defaultDns = '77.88.8.8';

  /// Значение по умолчанию в старых версиях — нужно только для миграции.
  static const legacyDefaultDns = '1.1.1.1';

  /// Ревизия значений по умолчанию: когда она увеличивается, новые значения
  /// применяются один раз и к уже сохранённым настройкам.
  static const int currentDefaultsRevision = 2;

  /// Тестовая страница для замера через узел.
  static const defaultPingUrl = 'https://www.gstatic.com/generate_204';
  static const minPingTimeout = 5;
  static const maxPingTimeout = 15;

  /// Ручной интервал автообновления подписок. Панель всё равно сообщает свой
  /// `profile-update-interval`, но пользовательский выбор важнее.
  static const defaultSubscriptionUpdateHours = 1;
  static const minSubscriptionUpdateHours = 1;
  static const maxSubscriptionUpdateHours = 168;

  /// Журнал ядра пишется в приватный каталог приложения и очищается по времени.
  static const defaultLogRetentionHours = 24;
  static const minLogRetentionHours = 1;
  static const maxLogRetentionHours = 168;

  const Settings({
    this.routingMode = RoutingMode.all,
    this.allowedApps = const [],
    this.bypassedApps = const [],
    this.dns = defaultDns,
    this.dnsUsePanel = true,
    this.dnsRoute = DnsRoute.tunnel,
    this.bypassLan = true,
    this.autoUpdateSubscriptions = true,
    this.subscriptionUpdateHours = defaultSubscriptionUpdateHours,
    this.sendHwid = true,
    this.pingMode = PingMode.proxy,
    this.pingProfile = PingProfile.single,
    this.pingTimeoutSeconds = minPingTimeout,
    this.pingUrl = defaultPingUrl,
    this.mtu = 1500,
    this.xrayLogEnabled = true,
    this.xrayLogLevel = XrayLogLevel.warning,
    this.xrayLogRetentionHours = defaultLogRetentionHours,
    this.lastUpdateCheckAt,
    this.lastNotifiedCoreVersion,
    this.pendingUpdate,
    this.defaultsRevision = currentDefaultsRevision,
  });

  final RoutingMode routingMode;
  final List<String> allowedApps;
  final List<String> bypassedApps;
  final String dns;

  /// true — брать серверы из JSON подписки. Это значение по умолчанию:
  /// адрес из панели учитывает её белые списки и настройки провайдера.
  final bool dnsUsePanel;
  final DnsRoute dnsRoute;
  final bool bypassLan;
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

  Settings copyWith({
    RoutingMode? routingMode,
    List<String>? allowedApps,
    List<String>? bypassedApps,
    String? dns,
    bool? dnsUsePanel,
    DnsRoute? dnsRoute,
    bool? bypassLan,
    bool? autoUpdateSubscriptions,
    int? subscriptionUpdateHours,
    bool? sendHwid,
    PingMode? pingMode,
    PingProfile? pingProfile,
    int? pingTimeoutSeconds,
    String? pingUrl,
    int? mtu,
    bool? xrayLogEnabled,
    XrayLogLevel? xrayLogLevel,
    int? xrayLogRetentionHours,
    DateTime? lastUpdateCheckAt,
    String? lastNotifiedCoreVersion,
    String? pendingUpdate,
    bool clearPendingUpdate = false,
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
        subscriptionUpdateHours:
            subscriptionUpdateHours ?? this.subscriptionUpdateHours,
        sendHwid: sendHwid ?? this.sendHwid,
        pingMode: pingMode ?? this.pingMode,
        pingProfile: pingProfile ?? this.pingProfile,
        pingTimeoutSeconds: pingTimeoutSeconds ?? this.pingTimeoutSeconds,
        pingUrl: pingUrl ?? this.pingUrl,
        mtu: mtu ?? this.mtu,
        xrayLogEnabled: xrayLogEnabled ?? this.xrayLogEnabled,
        xrayLogLevel: xrayLogLevel ?? this.xrayLogLevel,
        xrayLogRetentionHours: xrayLogRetentionHours ?? this.xrayLogRetentionHours,
        lastUpdateCheckAt: lastUpdateCheckAt ?? this.lastUpdateCheckAt,
        lastNotifiedCoreVersion:
            lastNotifiedCoreVersion ?? this.lastNotifiedCoreVersion,
        pendingUpdate: clearPendingUpdate ? null : (pendingUpdate ?? this.pendingUpdate),
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
        'subscriptionUpdateHours': subscriptionUpdateHours,
        'sendHwid': sendHwid,
        'pingMode': pingMode.wireName,
        'pingProfile': pingProfile.wireName,
        'pingTimeoutSeconds': pingTimeoutSeconds,
        'pingUrl': pingUrl,
        'mtu': mtu,
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
    final savedUrl = json['pingUrl'] as String?;
    final hours = (json['subscriptionUpdateHours'] as num?)?.toInt() ??
        defaultSubscriptionUpdateHours;
    final retention = (json['xrayLogRetentionHours'] as num?)?.toInt() ??
        defaultLogRetentionHours;
    final savedRevision = (json['defaultsRevision'] as num?)?.toInt() ?? 0;
    final upgradeDefaults = savedRevision < currentDefaultsRevision;
    // Старый адрес по умолчанию не считается осознанным выбором пользователя.
    final oldDefaultDns = savedDns == null ||
        savedDns.isEmpty ||
        legacyDefault ||
        savedDns == defaultDns;
    return Settings(
      routingMode: RoutingMode.fromName(json['routingMode'] as String?),
      allowedApps: ((json['allowedApps'] as List?) ?? const []).cast<String>(),
      bypassedApps: ((json['bypassedApps'] as List?) ?? const []).cast<String>(),
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
      autoUpdateSubscriptions: (json['autoUpdateSubscriptions'] as bool?) ?? true,
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
              : (savedTimeout > maxPingTimeout ? maxPingTimeout : savedTimeout)),
      pingUrl: (savedUrl == null || savedUrl.trim().isEmpty)
          ? defaultPingUrl
          : savedUrl.trim(),
      mtu: (json['mtu'] as num?)?.toInt() ?? 1500,
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
