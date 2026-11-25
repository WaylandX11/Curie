import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/profile.dart';
import 'share_link_parser.dart';

/// Серверная часть «моста» для Windows.
///
/// В Android-версии все запросы идут в libXray через MethodChannel. На Windows
/// используется официальный `xray.exe`: версия берётся из CLI, сетевые проверки
/// — из Dart, а ссылки разбираются [ShareLinkParser]. Публичный контракт
/// `Xray.invoke` при этом остаётся тем же `{success, data, error}`.
class WindowsXray {
  static const String executableName = 'xray.exe';

  static String? findExecutable() {
    final explicit = Platform.environment['CURIE_XRAY_EXE'];
    if (explicit != null && explicit.isNotEmpty && File(explicit).existsSync()) {
      return explicit;
    }

    final dirs = <String>[
      _dirOf(Platform.resolvedExecutable),
      Directory.current.path,
      _join(Directory.current.path, 'tools', 'xray'),
      _join(_dirOf(Platform.resolvedExecutable), 'data', 'flutter_assets', 'tools'),
      _join(_dirOf(Platform.resolvedExecutable), 'tools', 'xray'),
    ];
    for (final dir in dirs) {
      final file = File(_join(dir, executableName));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  /// Обработка JSON-envelope из `Xray.invoke`.
  static Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> payload,
  ) async {
    switch (method) {
      case 'xrayVersion':
        return {'version': await version()};
      case 'getFreePorts':
        final count = (payload['count'] as num?)?.toInt() ?? 1;
        return {'ports': await freePorts(count)};
      case 'convertShareLinksToXrayJson':
        final text = (payload['text'] as String?)?.trim() ?? '';
        return {'outbounds': await convertShareLinks(text)};
      case 'pingBatch':
        final configs = (payload['configs'] as List?) ?? const [];
        final timeout = (payload['timeout'] as num?)?.toInt() ?? 5;
        final url = (payload['url'] as String?) ?? '';
        final warm = payload['warm'] == true;
        return {
          'results': await pingBatch(
            configs,
            timeoutSeconds: timeout,
            url: url,
            warm: warm,
          ),
        };
      default:
        throw WindowsXrayException('неизвестный метод Xray: $method');
    }
  }

  static Future<String> version() async {
    final executable = findExecutable();
    if (executable == null) {
      throw const WindowsXrayException(
        'xray.exe не найден. Положите его рядом с Curie.exe '
        'или задайте CURIE_XRAY_EXE.',
      );
    }
    final result = await Process.run(executable, ['version']);
    final output = (result.stdout as String?)?.trim() ?? '';
    final match = RegExp(r'Xray\s+(v?\d+\.\d+\.\d+(?:[.-][0-9A-Za-z]+)*)')
        .firstMatch(output);
    if (match != null) return 'Xray ${match.group(1)}';
    if (output.isNotEmpty) return output.split(RegExp(r'\r?\n')).first;
    throw WindowsXrayException(
      'xray version вернул ${result.exitCode}: ${result.stderr}',
    );
  }

  /// Кандидаты свободных localhost-портов. Как и в libXray, это не бронь:
  /// слушатели сразу закрываются, но шанс коллизии минимален.
  static Future<List<int>> freePorts(int count) async {
    if (count <= 0) return const [];
    final sockets = <ServerSocket>[];
    try {
      for (var i = 0; i < count; i++) {
        sockets.add(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
      }
      return sockets.map((socket) => socket.port).toList();
    } finally {
      for (final socket in sockets) {
        await socket.close();
      }
    }
  }

  static Future<List<Map<String, dynamic>>> convertShareLinks(String text) async {
    final outbounds = ShareLinkParser.parseText(text);
    if (outbounds.isEmpty) {
      throw const WindowsXrayException('не удалось разобрать ссылку');
    }
    return outbounds;
  }

  /// Замена `pingBatch` из libXray.
  ///
  /// libXray поднимает каждый outbound и делает запрос через него. Здесь
  /// измеряется TCP (для TLS — ещё и рукопожатие) до адреса узла: это те же
  /// данные, которые в UI показывает режим пинга TCP, и он не требует
  /// дополнительного процесса Xray на время замера.
  static Future<List<Map<String, dynamic>>> pingBatch(
    List<Object?> configs, {
    required int timeoutSeconds,
    required String url,
    required bool warm,
  }) async {
    final results = <Map<String, dynamic>>[];
    final timeout = Duration(seconds: timeoutSeconds > 0 ? timeoutSeconds : 5);

    for (final item in configs) {
      try {
        final probe = _probeTarget(item);
        if (probe == null) {
          results.add({
            'success': false,
            'error': 'нет адреса узла',
          });
          continue;
        }
        final ms = await _measure(
          address: probe.address,
          port: probe.port,
          serverName: probe.serverName,
          alpn: probe.alpn,
          timeout: timeout,
        );
        results.add({'success': true, 'delay': ms});
      } on Object catch (e) {
        results.add({'success': false, 'error': e.toString()});
      }
    }
    return results;
  }

  static ({String address, int port, String? serverName, List<String>? alpn})?
      _probeTarget(Object? item) {
    if (item is! Map) return null;
    final map = item.cast<String, dynamic>();
    final raw = map['xrayJson'] as String?;
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final config = decoded.cast<String, dynamic>();
    final outbounds = (config['outbounds'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    if (outbounds.isEmpty) return null;

    final tag = map['outboundTag'] as String?;
    final outbound = (tag == null
            ? null
            : outbounds.where((element) => element['tag'] == tag).firstOrNull) ??
        outbounds.first;

    final details = outboundDetails(outbound);
    final address = details.address?.trim();
    final port = details.port;
    if (address == null || address.isEmpty || port == null || port <= 0) {
      return null;
    }

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
    return (
      address: address,
      port: port,
      serverName: serverName?.trim(),
      alpn: alpnRaw is List ? alpnRaw.whereType<String>().toList() : null,
    );
  }

  static Future<int> _measure({
    required String address,
    required int port,
    required String? serverName,
    required List<String>? alpn,
    required Duration timeout,
  }) async {
    final watch = Stopwatch()..start();
    Socket? socket;
    try {
      final raw = await Socket.connect(address, port, timeout: timeout);
      socket = raw;
      if (serverName != null) {
        final remaining = timeout - watch.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('таймаут TLS', Duration.zero);
        }
        final secure = await SecureSocket.secure(
          raw,
          host: serverName.isEmpty ? address : serverName,
          onBadCertificate: (_) => true,
          supportedProtocols: alpn,
        ).timeout(remaining);
        socket = null;
        secure.destroy();
      }
      watch.stop();
      return watch.elapsedMilliseconds;
    } on Object {
      return timeout.inMilliseconds + 1000;
    } finally {
      socket?.destroy();
    }
  }

  static String _join(String a, String b, [String? c, String? d]) {
    var result = '$a${Platform.pathSeparator}$b';
    if (c != null) result += '${Platform.pathSeparator}$c';
    if (d != null) result += '${Platform.pathSeparator}$d';
    return result;
  }

  static String _dirOf(String filePath) {
    final separator = Platform.pathSeparator;
    final index = filePath.lastIndexOf(separator);
    return index <= 0 ? filePath : filePath.substring(0, index);
  }
}

class WindowsXrayException implements Exception {
  const WindowsXrayException(this.message);

  final String message;

  @override
  String toString() => message;
}
