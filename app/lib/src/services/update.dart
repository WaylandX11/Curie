import 'dart:convert';
import 'dart:io';

/// Информация о последнем релизе на GitHub.
class GithubRelease {
  const GithubRelease({
    required this.version,
    required this.tag,
    required this.htmlUrl,
    required this.notes,
    required this.assets,
  });

  /// Версия без префикса `v` и суффикса (`alpha`, `beta`).
  final String version;
  final String tag;
  final String htmlUrl;
  final String notes;

  /// Ключ — суффикс APK: `universal`, `arm64`, `arm32`, `x64`.
  final Map<String, String> assets;

  /// Ссылка на APK под архитектуру устройства. Если подходящего ассета нет,
  /// возвращается universal — он есть всегда.
  String downloadUrlFor(String abi) {
    final key = GithubUpdate.assetKey(abi);
    return assets[key] ?? assets['universal'] ?? htmlUrl;
  }
}

/// Проверка обновлений без Google Play: смотрим публичные релизы GitHub.
class GithubUpdate {
  static const String _repo = 'WaylandX11/Curie';
  static const String _api =
      'https://api.github.com/repos/$_repo/releases?per_page=1';

  /// Без авторизации. GitHub даёт 60 запросов в час с IP — проверка только
  /// по кнопке и не чаще одного раза за сессию, этого хватает.
  static Future<GithubRelease?> fetchLatest() async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(Uri.parse(_api));
      request.headers
        ..set('User-Agent', 'Curie')
        ..set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
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
      client.close();
    }
  }

  /// Разбор ответа отдельно от сети — чтобы можно было покрыть тестами.
  static GithubRelease parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final raw = tag.startsWith('v') ? tag.substring(1) : tag;
    final version = raw.split('-').first;
    final assets = <String, String>{};
    for (final item in (json['assets'] as List<dynamic>?) ?? const []) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final name = (map['name'] as String?)?.toLowerCase() ?? '';
      final url = map['browser_download_url'] as String?;
      if (url == null) continue;
      if (name.endsWith('-universal.apk')) {
        assets['universal'] = url;
      } else if (name.endsWith('-arm64.apk')) {
        assets['arm64'] = url;
      } else if (name.endsWith('-arm32.apk')) {
        assets['arm32'] = url;
      } else if (name.endsWith('-x64.apk')) {
        assets['x64'] = url;
      }
    }
    return GithubRelease(
      version: version,
      tag: tag,
      htmlUrl: (json['html_url'] as String?) ?? '',
      notes: (json['body'] as String?)?.trim() ?? '',
      assets: assets,
    );
  }

  /// Версия вида `YY.MM.DD.HHMM` сравнивается как число из 10 цифр.
  static bool isNewer(String remote, String current) =>
      _number(remote) > _number(current);

  static int _number(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) return 0;
    return int.tryParse(digits.substring(0, 10)) ?? 0;
  }

  /// `Build.SUPPORTED_ABIS` из Android → ключ ассета.
  static String assetKey(String abi) {
    final value = abi.toLowerCase();
    if (value.contains('arm64') || value.contains('aarch64')) return 'arm64';
    if (value.contains('x86_64') || value.contains('amd64')) return 'x64';
    if (value.contains('arm')) return 'arm32';
    return 'universal';
  }
}
