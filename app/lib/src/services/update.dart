import 'dart:convert';
import 'dart:io';

/// Информация о последнем релизе на GitHub.
class GithubRelease {
  const GithubRelease({
    required this.version,
    required this.tag,
    required this.htmlUrl,
    required this.notes,
    required this.downloadUrl,
    required this.coreVersion,
  });

  /// Версия без префикса `v` и суффикса (`alpha`, `beta`).
  final String version;
  final String tag;
  final String htmlUrl;
  final String notes;

  /// Ссылка на единственный APK релиза (universal). Если ассета нет,
  /// возвращается страница релиза — пользователь скачает вручную.
  final String downloadUrl;

  /// Версия Xray, указанная в тексте релиза. `null`, если релиз её не сообщает.
  final String? coreVersion;
}

/// Проверка обновлений без Google Play: смотрим публичные релизы GitHub.
class GithubUpdate {
  static const String _repo = 'WaylandX11/Curie';
  static const String _api =
      'https://api.github.com/repos/$_repo/releases?per_page=1';

  /// Без авторизации. GitHub даёт 60 запросов в час с IP — проверяем не чаще
  /// раза в сутки (и одну проверку по кнопке).
  ///
  /// Когда туннель поднят, Curie исключён из собственного TUN, поэтому запрос
  /// идёт через локальный HTTP-прокси Xray, а не мимо VPN.
  static Future<GithubRelease?> fetchLatest({int proxyPort = 0}) async {
    final client = HttpClient()
      ..findProxy = ((_) => proxyPort > 0
          ? 'PROXY 127.0.0.1:$proxyPort'
          : 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(_api));
      request.headers
        ..set('User-Agent', 'Curie')
        ..set('Accept', 'application/vnd.github+json');
      final response = await request
          .close()
          .timeout(const Duration(seconds: 30));
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw HttpException(
          'GitHub ${response.statusCode}',
          uri: Uri.parse(_api),
        );
      }
      final data = jsonDecode(body) as List<dynamic>;
      if (data.isEmpty || data.first is! Map) return null;
      return parseRelease((data.first as Map).cast<String, dynamic>());
    } finally {
      client.close(force: true);
    }
  }

  /// Разбор ответа отдельно от сети — чтобы можно было покрыть тестами.
  static GithubRelease parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final raw = tag.startsWith('v') ? tag.substring(1) : tag;
    final appVersion = raw.split('-').first;
    final htmlUrl = (json['html_url'] as String?) ?? '';
    final notes = (json['body'] as String?)?.trim() ?? '';

    var downloadUrl = htmlUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final item in assets) {
        if (item is! Map) continue;
        final map = item.cast<String, dynamic>();
        final name = (map['name'] as String?)?.toLowerCase() ?? '';
        final url = map['browser_download_url'] as String?;
        if (url != null && name.endsWith('-universal.apk')) {
          downloadUrl = url;
          break;
        }
      }
    }

    return GithubRelease(
      version: appVersion,
      tag: tag,
      htmlUrl: htmlUrl,
      notes: notes,
      downloadUrl: downloadUrl,
      coreVersion: parseCoreVersion(notes),
    );
  }

  /// Релиз сообщает версию ядра строкой вида `Xray-core: v26.11.9`.
  /// Поддерживаем и «libXray v…», и просто «Xray v…».
  static String? parseCoreVersion(String notes) {
    final match = RegExp(
      r'(?:Xray(?:-core)?|libXray)\s*[:：]?\s*v?(\d+\.\d+\.\d+(?:[.-][0-9A-Za-z]+)*)',
      caseSensitive: false,
    ).firstMatch(notes);
    return match?.group(1);
  }

  /// Версия вида `YY.MM.DD.HHMM` сравнивается как число из 10 цифр.
  static bool isNewer(String remote, String current) =>
      _number(remote) > _number(current);

  /// Версии ядра вида `26.11.9` сравниваются по частям.
  static bool isNewerCore(String remote, String current) =>
      _compareCore(_coreNumber(remote), _coreNumber(current)) > 0;

  static int _number(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) return 0;
    return int.tryParse(digits.substring(0, 10)) ?? 0;
  }

  static List<int> _coreNumber(String value) => value
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[.\-]'))
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);

  static int _compareCore(List<int> a, List<int> b) {
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }
}
