import 'profile.dart';

/// Сведения о подписке, которые панель отдаёт в заголовках ответа
/// (Remnawave, Marzneshin и совместимые).
class SubscriptionInfo {
  const SubscriptionInfo({
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire,
  });

  final int upload;
  final int download;

  /// 0 — безлимит.
  final int total;
  final DateTime? expire;

  int get used => upload + download;

  double? get usageRatio => total <= 0 ? null : (used / total).clamp(0, 1).toDouble();

  bool get isExpired => expire != null && expire!.isBefore(DateTime.now());

  /// `upload=1; download=2; total=3; expire=1700000000`
  static SubscriptionInfo? parse(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final parts = <String, String>{};
    for (final chunk in header.split(';')) {
      final pair = chunk.split('=');
      if (pair.length == 2) parts[pair[0].trim()] = pair[1].trim();
    }
    if (parts.isEmpty) return null;

    int number(String key) => int.tryParse(parts[key] ?? '') ?? 0;
    final expireSeconds = number('expire');

    return SubscriptionInfo(
      upload: number('upload'),
      download: number('download'),
      total: number('total'),
      expire: expireSeconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(expireSeconds * 1000)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'upload': upload,
        'download': download,
        'total': total,
        if (expire != null) 'expire': expire!.millisecondsSinceEpoch,
      };

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) => SubscriptionInfo(
        upload: (json['upload'] as num?)?.toInt() ?? 0,
        download: (json['download'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        expire: json['expire'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((json['expire'] as num).toInt()),
      );
}

class Subscription {
  /// Суффиксы, которыми панели задают формат ответа. Curie добавляет `/json`
  /// к своему запросу, но наружу (буфер, «Поделиться») отдаёт базовую ссылку.
  static const Set<String> formatSuffixes = {
    'json',
    'v2ray-json',
    'clash',
    'singbox',
    'mihomo',
    'stash',
    'info',
  };

  const Subscription({
    required this.url,
    required this.title,
    this.nodes = const [],
    this.updatedAt,
    this.updateIntervalHours = 12,
    this.info,
    this.announce,
    this.supportUrl,
    this.webPageUrl,
    this.lastError,
    this.lastErrorDetail,
    this.edits = const {},
    this.expanded = false,
  });

  final String url;
  final String title;
  final List<Profile> nodes;
  final DateTime? updatedAt;
  final int updateIntervalHours;
  final SubscriptionInfo? info;

  /// Текст объявления панели (`announce`), ссылка поддержки и сайта.
  final String? announce;
  final String? supportUrl;
  final String? webPageUrl;

  /// Код ошибки последнего обновления (локализуется в UI) и её подробности.
  final String? lastError;
  final String? lastErrorDetail;

  /// Правки узлов, сделанные пользователем через долгое нажатие.
  /// Ключ — `Profile.id`, значение — сохранённый JSON узла. Применяются
  /// поверх свежих узлов после обновления подписки.
  final Map<String, Map<String, dynamic>> edits;

  /// Развёрнутость списка узлов — состояние интерфейса, но оно живёт в
  /// зашифрованном хранилище и переживает перезапуск.
  final bool expanded;

  String get id => url;

  /// Ссылка для буфера/«Поделиться»: другие клиенты сами выбирают формат,
  /// поэтому служебный суффикс (`/json` и ему подобные) убирается.
  String get shareUrl {
    final raw = url.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty ||
        !formatSuffixes.contains(segments.last.toLowerCase())) {
      return raw;
    }
    return uri
        .replace(pathSegments: segments.sublist(0, segments.length - 1))
        .toString();
  }

  /// `overrideHours` приходит из пользовательской настройки и важнее значения
  /// панели (`profile-update-interval`).
  bool isStale({int? overrideHours}) {
    if (updatedAt == null) return true;
    final hours = overrideHours ?? updateIntervalHours;
    return DateTime.now().difference(updatedAt!).inHours >= hours;
  }

  /// Свежий узел панели + правка пользователя (если была).
  Profile applyEdit(Profile node) {
    final saved = edits[node.id];
    if (saved == null) return node;
    return Profile.fromJson(saved).copyWith(subscriptionUrl: node.subscriptionUrl);
  }

  Subscription copyWith({
    String? title,
    List<Profile>? nodes,
    DateTime? updatedAt,
    int? updateIntervalHours,
    SubscriptionInfo? info,
    String? announce,
    String? supportUrl,
    String? webPageUrl,
    String? lastError,
    String? lastErrorDetail,
    Map<String, Map<String, dynamic>>? edits,
    bool? expanded,
    bool clearError = false,
  }) =>
      Subscription(
        url: url,
        title: title ?? this.title,
        nodes: nodes ?? this.nodes,
        updatedAt: updatedAt ?? this.updatedAt,
        updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
        info: info ?? this.info,
        announce: announce ?? this.announce,
        supportUrl: supportUrl ?? this.supportUrl,
        webPageUrl: webPageUrl ?? this.webPageUrl,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastErrorDetail: clearError ? null : (lastErrorDetail ?? this.lastErrorDetail),
        edits: edits ?? this.edits,
        expanded: expanded ?? this.expanded,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
        'updateIntervalHours': updateIntervalHours,
        if (info != null) 'info': info!.toJson(),
        if (announce != null) 'announce': announce,
        if (supportUrl != null) 'supportUrl': supportUrl,
        if (webPageUrl != null) 'webPageUrl': webPageUrl,
        if (lastError != null) 'lastError': lastError,
        if (lastErrorDetail != null) 'lastErrorDetail': lastErrorDetail,
        if (edits.isNotEmpty)
          'edits': edits.map((key, value) => MapEntry(key, value)),
        'expanded': expanded,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        url: json['url'] as String,
        title: (json['title'] as String?) ?? '',
        nodes: ((json['nodes'] as List?) ?? const [])
            .map((e) => Profile.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((json['updatedAt'] as num).toInt()),
        updateIntervalHours: (json['updateIntervalHours'] as num?)?.toInt() ?? 12,
        info: json['info'] == null
            ? null
            : SubscriptionInfo.fromJson((json['info'] as Map).cast<String, dynamic>()),
        announce: json['announce'] as String?,
        supportUrl: json['supportUrl'] as String?,
        webPageUrl: json['webPageUrl'] as String?,
        lastError: json['lastError'] as String?,
        lastErrorDetail: json['lastErrorDetail'] as String?,
        edits: ((json['edits'] as Map?) ?? const {}).map(
          (key, value) => MapEntry(
            key.toString(),
            (value as Map).cast<String, dynamic>(),
          ),
        ),
        expanded: (json['expanded'] as bool?) ?? false,
      );
}
