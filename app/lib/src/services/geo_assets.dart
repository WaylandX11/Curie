import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../models/settings.dart';
import '../models/subscription.dart';
import 'app_log.dart';
import 'network_info.dart';
import 'pick_geo_file.dart';
import 'store.dart';
import 'subscription_parser.dart';
import 'vpn.dart';

enum GeoAssetKind { geoip, geosite }

extension GeoAssetKindName on GeoAssetKind {
  String get fileName =>
      this == GeoAssetKind.geoip ? 'geoip.dat' : 'geosite.dat';
}

class GeoAssetInfo {
  const GeoAssetInfo({
    required this.kind,
    required this.url,
    required this.exists,
    required this.size,
    this.updatedAt,
    this.sha256,
  });

  final GeoAssetKind kind;
  final String url;
  final bool exists;
  final int size;
  final DateTime? updatedAt;
  final String? sha256;
}

/// DAT-базы для правил `geoip:`/`geosite:` из подписки.
///
/// Файлы лежат в приватном каталоге приложения под фиксированными именами:
/// Xray находит их через `env."xray.location.asset"` в конфиге. Скачивание идёт
/// через локальный прокси туннеля, когда туннель поднят, и только по безлимитной
/// сети, если включён соответствующий переключатель.
class GeoAssets {
  static final ValueNotifier<bool> prompt = ValueNotifier(false);
  static final ValueNotifier<int> restartRequested = ValueNotifier(0);
  static final ValueNotifier<bool> busy = ValueNotifier(false);

  /// Прогресс по каждому файлу: 0..1. Ключ есть — скачивание идёт, поэтому
  /// интерфейс показывает не только «занято», но и сколько уже получено.
  static final ValueNotifier<Map<GeoAssetKind, double>> progress =
      ValueNotifier(const {});

  static final ValueNotifier<List<GeoAssetInfo>> status = ValueNotifier(
    const [],
  );

  /// Подстановки для тестов. В приложении остаются null.
  static String? directoryOverride;
  static Future<List<int>> Function(
    Uri uri,
    int proxyPort,
    void Function(int received, int? total) onProgress,
  )?
  fetchOverride;
  static Future<bool> Function(GeoAssetKind kind)? pickOverride;

  static const Duration _timeout = Duration(seconds: 45);
  static final RegExp _geoRule = RegExp(
    r'(geoip|geosite)\s*:',
    caseSensitive: false,
  );
  static final List<GeoAssetKind> _kinds = GeoAssetKind.values;

  static bool _autoBusy = false;
  static bool _wifiSkipLogged = false;

  static String defaultUrl(GeoAssetKind kind) => kind == GeoAssetKind.geoip
      ? Settings.defaultGeoipUrl
      : Settings.defaultGeositeUrl;

  static String urlFor(GeoAssetKind kind, Settings settings) =>
      kind == GeoAssetKind.geoip ? settings.geoipUrl : settings.geositeUrl;

  static DateTime? updatedAtFor(GeoAssetKind kind, Settings settings) =>
      kind == GeoAssetKind.geoip
      ? settings.geoipUpdatedAt
      : settings.geositeUpdatedAt;

  /// Обычные регулярные выражения Xray не требуют DAT-файлов — триггер только
  /// geoip:/geosite:.
  /// Подписка может прийти JSON, текстом ссылок или base64-обёрткой.
  static bool containsGeoRules(String body) {
    if (_geoRule.hasMatch(body)) return true;
    final decoded = SubscriptionParser.tryBase64(body);
    return decoded != null && decoded != body && _geoRule.hasMatch(decoded);
  }

  static Future<String> assetDirectory() async {
    final override = directoryOverride;
    final base = override != null
        ? Directory(override)
        : await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}geo');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  static Future<File> file(GeoAssetKind kind) async {
    final directory = await assetDirectory();
    return File('$directory${Platform.pathSeparator}${kind.fileName}');
  }

  static Future<void> refreshStatus() async {
    final settings = Store.instance.state.value.settings;
    final info = <GeoAssetInfo>[];
    for (final kind in _kinds) {
      final target = await file(kind);
      final exists = await target.exists();
      info.add(
        GeoAssetInfo(
          kind: kind,
          url: urlFor(kind, settings),
          exists: exists,
          size: exists ? await target.length() : 0,
          updatedAt: updatedAtFor(kind, settings),
          sha256: kind == GeoAssetKind.geoip
              ? settings.geoipSha256
              : settings.geositeSha256,
        ),
      );
    }
    status.value = info;
  }

  /// Вызывается после загрузки подписки: первый раз с geo-правилами показываем
  /// предложение скачать базы, но не блокируем подключение.
  static Future<void> noteSubscription(Subscription subscription) async {
    if (!subscription.requiresGeoAssets) return;
    final settings = Store.instance.state.value.settings;
    if (settings.geoAssetsPromptShown) return;
    await Store.instance.update(
      (state) => state.copyWith(
        settings: state.settings.copyWith(geoAssetsPromptShown: true),
      ),
    );
    AppLog.add('geo', 'подписка использует geoip:/geosite:, нужны DAT-файлы');
    prompt.value = true;
  }

  /// Подписки, сохранённые до появления флага, всё равно узнаём по их конфигам.
  static Future<void> noticeStoredSubscriptions() async {
    final subscriptions = Store.instance.state.value.subscriptions;
    for (final subscription in subscriptions) {
      final needs =
          subscription.requiresGeoAssets ||
          subscription.nodes.any(
            (node) => _geoRule.hasMatch(node.configJson ?? ''),
          );
      if (needs) {
        await noteSubscription(subscription);
        return;
      }
    }
  }

  static void dismissPrompt() => prompt.value = false;

  static Future<void> resetUrl(GeoAssetKind kind) async {
    await Store.instance.update(
      (state) => state.copyWith(
        settings: state.settings.copyWith(
          geoipUrl: kind == GeoAssetKind.geoip ? defaultUrl(kind) : null,
          geositeUrl: kind == GeoAssetKind.geosite ? defaultUrl(kind) : null,
        ),
      ),
    );
    await refreshStatus();
  }

  static Future<bool> download(
    GeoAssetKind kind, {
    int proxyPort = 0,
    String? url,
    bool notifyRestart = true,
  }) async {
    final settings = Store.instance.state.value.settings;
    final raw = (url ?? urlFor(kind, settings)).trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !['http', 'https'].contains(uri.scheme)) {
      throw FormatException('Invalid geo file URL', raw);
    }
    final fetcher = fetchOverride;
    try {
      final bytes = fetcher != null
          ? await fetcher(
              uri,
              proxyPort,
              (received, total) => reportProgress(kind, received, total),
            )
          : await _fetch(
              uri,
              proxyPort,
              (received, total) => reportProgress(kind, received, total),
            );
      return await _install(kind, bytes, notifyRestart: notifyRestart);
    } finally {
      clearProgress(kind);
    }
  }

  /// Прогресс в 0..1. Когда сервер не прислал `Content-Length`, показываем
  /// indeterminate: в UI это нулевое значение с включённым индикатором.
  static void reportProgress(GeoAssetKind kind, int received, int? total) {
    final next = Map<GeoAssetKind, double>.from(progress.value);
    if (total != null && total > 0) {
      next[kind] = (received / total).clamp(0.0, 1.0).toDouble();
    } else {
      next[kind] = 0.0;
    }
    progress.value = next;
  }

  static void clearProgress(GeoAssetKind kind) {
    if (!progress.value.containsKey(kind)) return;
    final next = Map<GeoAssetKind, double>.from(progress.value)..remove(kind);
    progress.value = next;
  }

  static Future<Map<GeoAssetKind, String?>> downloadAll({
    int proxyPort = 0,
  }) async {
    final errors = <GeoAssetKind, String?>{};
    var changedAny = false;
    for (final kind in _kinds) {
      try {
        if (await download(kind, proxyPort: proxyPort, notifyRestart: false)) {
          changedAny = true;
        }
        errors[kind] = null;
      } on Object catch (e) {
        errors[kind] = '$e';
        AppLog.add('geo', '${kind.fileName}: не удалось обновить — $e');
      }
    }
    if (changedAny) _requestRestartIfNeeded();
    await refreshStatus();
    return errors;
  }

  static Future<bool> pickAndImport(GeoAssetKind kind) async {
    final picker = pickOverride;
    File file;
    if (picker != null) {
      if (!await picker(kind)) return false;
      file = await _pickedFile(kind);
    } else {
      final path = await pickDatFilePath();
      if (path == null || path.isEmpty) return false;
      file = File(path);
    }
    final bytes = await file.readAsBytes();
    return importBytes(kind, bytes);
  }

  static Future<bool> importBytes(GeoAssetKind kind, List<int> bytes) async {
    final changed = await _install(kind, bytes);
    await refreshStatus();
    return changed;
  }

  /// Плановое обновление. Возвращает true, если хотя бы один файл изменился.
  static Future<bool> maybeAutoUpdate({bool force = false}) async {
    if (_autoBusy || busy.value) return false;
    _autoBusy = true;
    try {
      final settings = Store.instance.state.value.settings;
      if (!force && !settings.geoAssetsAutoUpdate) return false;
      if (!await _hasGeoSubscriptions()) return false;

      if (!force && settings.geoAssetsWifiOnly) {
        if (!await NetworkInfo.isUnmetered()) {
          if (!_wifiSkipLogged) {
            AppLog.add('geo', 'обновление баз отложено: ждём Wi-Fi');
            _wifiSkipLogged = true;
          }
          return false;
        }
        _wifiSkipLogged = false;
      }

      if (!force && !isDue(settings)) return false;

      final proxyPort = Vpn.tunnelProxyPort;
      var changedAny = false;
      for (final kind in _kinds) {
        try {
          final changed = await download(
            kind,
            proxyPort: proxyPort,
            notifyRestart: false,
          );
          if (changed) {
            AppLog.add('geo', '${kind.fileName}: база обновлена');
            changedAny = true;
          }
        } on Object catch (e) {
          AppLog.add('geo', '${kind.fileName}: ошибка обновления — $e');
        }
      }
      if (changedAny) _requestRestartIfNeeded();
      await refreshStatus();
      return changedAny;
    } finally {
      _autoBusy = false;
    }
  }

  static bool isDue(Settings settings, {DateTime? now}) {
    final times = [settings.geoipUpdatedAt, settings.geositeUpdatedAt];
    if (times.any((time) => time == null)) return true;
    final earliest = times.reduce((a, b) => a!.isBefore(b!) ? a : b)!;
    return (now ?? DateTime.now()).difference(earliest).inHours >=
        settings.geoAssetsUpdateHours;
  }

  static String proxyFor(int port) =>
      port > 0 ? 'PROXY 127.0.0.1:$port' : 'DIRECT';

  /// Минимальная проверка protobuf-контейнера Xray: внешний список — field 1,
  /// внутри первой записи тоже field 1 (`country_code`). Отсекает HTML-страницы
  /// ошибки и битые/пустые файлы, но не разбирает всё содержимое базы.
  static bool isValidBytes(GeoAssetKind kind, List<int> bytes) {
    if (bytes.length < 12 || bytes[0] != 0x0a) return false;
    final listLength = _readVarint(bytes, 1);
    if (listLength <= 0) return false;
    var offset = 1;
    while (offset < bytes.length && (bytes[offset] & 0x80) != 0) {
      offset++;
    }
    offset++;
    if (offset >= bytes.length || offset + listLength > bytes.length) {
      return false;
    }
    if (bytes[offset] != 0x0a) return false;
    final nameLength = _readVarint(bytes, offset + 1);
    return nameLength > 0;
  }

  static int _readVarint(List<int> bytes, int offset) {
    var result = 0;
    var shift = 0;
    var index = offset;
    while (index < bytes.length && shift < 63) {
      final byte = bytes[index++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
    return -1;
  }

  static void _requestRestartIfNeeded() {
    final settings = Store.instance.state.value.settings;
    if (settings.geoAssetsRestartXray &&
        Vpn.status.value == VpnStatus.connected) {
      restartRequested.value++;
    }
  }

  static Future<bool> _hasGeoSubscriptions() async {
    for (final subscription in Store.instance.state.value.subscriptions) {
      if (subscription.requiresGeoAssets ||
          subscription.nodes.any(
            (node) => _geoRule.hasMatch(node.configJson ?? ''),
          )) {
        return true;
      }
    }
    return false;
  }

  static Future<List<int>> _fetch(
    Uri uri,
    int proxyPort,
    void Function(int received, int? total) onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = (_) => proxyFor(proxyPort);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final total = response.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response) {
        builder.add(chunk);
        received += chunk.length;
        onProgress(received, total > 0 ? total : null);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static Future<File> _pickedFile(GeoAssetKind kind) async {
    final directory = await assetDirectory();
    return File('$directory${Platform.pathSeparator}.picked-${kind.fileName}');
  }

  static Future<bool> _install(
    GeoAssetKind kind,
    List<int> bytes, {
    bool notifyRestart = true,
  }) async {
    if (!isValidBytes(kind, bytes)) {
      throw const FormatException('Invalid geo database format');
    }
    final digest = sha256.convert(bytes).toString();
    final target = await file(kind);
    final settings = Store.instance.state.value.settings;
    final previous = kind == GeoAssetKind.geoip
        ? settings.geoipSha256
        : settings.geositeSha256;
    if (await target.exists() && previous == digest) return false;

    busy.value = true;
    try {
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);

      final now = DateTime.now();
      await Store.instance.update(
        (state) => state.copyWith(
          settings: state.settings.copyWith(
            geoipUpdatedAt: kind == GeoAssetKind.geoip
                ? now
                : state.settings.geoipUpdatedAt,
            geositeUpdatedAt: kind == GeoAssetKind.geosite
                ? now
                : state.settings.geositeUpdatedAt,
            geoipSha256: kind == GeoAssetKind.geoip
                ? digest
                : state.settings.geoipSha256,
            geositeSha256: kind == GeoAssetKind.geosite
                ? digest
                : state.settings.geositeSha256,
          ),
        ),
      );
      if (notifyRestart) _requestRestartIfNeeded();
      return true;
    } finally {
      busy.value = false;
    }
  }
}
