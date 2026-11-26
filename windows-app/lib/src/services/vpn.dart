import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/settings.dart';
import 'app_log.dart';
import 'windows_system.dart';
import 'windows_xray.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

/// Управление туннелем на Windows.
///
/// Android-версия получала статус пушами из `VpnService`. Здесь запускается
/// `xray.exe` с локальным `mixed` inbound, а статус и порты хранятся прямо в
/// этом классе. Публичные notifier'ы и [VpnException] сохранены — экран и
/// тесты не зависят от платформы.
class Vpn {
  static final ValueNotifier<VpnStatus> status = ValueNotifier(
    VpnStatus.disconnected,
  );
  static final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Локальный HTTP/SOCKS-прокси Xray, через который идут фоновые запросы.
  static final ValueNotifier<int> outboundProxyPort = ValueNotifier(0);
  static final ValueNotifier<int> metricsPort = ValueNotifier(0);
  static final ValueNotifier<DateTime?> connectedAt = ValueNotifier(null);

  static bool get isSupported => Platform.isWindows;

  /// Порт для обновлений: 0, когда туннель не работает.
  static int get tunnelProxyPort =>
      status.value == VpnStatus.connected ? outboundProxyPort.value : 0;

  static Future<void>? _ready;

  static Process? _process;
  static StreamSubscription<String>? _stdout;
  static StreamSubscription<String>? _stderr;
  static File? _configFile;
  static int _metricsPort = 0;
  static int _checkPort = 0;
  static DateTime? _startedAt;

  static Future<void> init() => _ready ??= _init();

  static Future<void> _init() async {
    // Если приложение завершилось аварийно, системный прокси мог остаться
    // включённым на уже закрытый порт.
    await WindowsSystemProxy.restoreIfStale();
    await refresh();
  }

  /// Перечитать состояние процесса. Вызывается при возврате в приложение.
  static Future<void> refresh() async {
    final process = _process;
    if (process == null) {
      _applyDisconnected();
      return;
    }
    try {
      final exit = await process.exitCode.timeout(
        const Duration(milliseconds: 200),
      );
      if (exit != 0 || !identical(_process, process)) {
        _applyDisconnected();
      }
    } on TimeoutException {
      // Процесс ещё жив — состояние уже актуально.
    }
  }

  static void _apply(Map<String, dynamic> args) {
    final next = _statusFromName(args['status'] as String?);
    final active = next == VpnStatus.connected;
    final started = (args['connectedAt'] as num?)?.toInt();

    // Сначала порты и время старта, затем статус: слушатели статуса
    // (TunnelMonitor и экран) должны сразу видеть готовую сессию.
    outboundProxyPort.value = active
        ? (args['check'] as num?)?.toInt() ?? 0
        : 0;
    metricsPort.value = active ? (args['metrics'] as num?)?.toInt() ?? 0 : 0;
    connectedAt.value = active && started != null && started > 0
        ? DateTime.fromMillisecondsSinceEpoch(started)
        : null;
    lastError.value = args['error'] as String?;
    status.value = next;
  }

  static void _applyDisconnected() {
    _apply(const {'status': 'disconnected'});
  }

  static Future<void> connect({
    required String config,
    required Settings settings,
  }) async {
    if (!isSupported) {
      throw const VpnException('unsupported', 'Windows-only build required');
    }

    await disconnect();
    _apply(const {'status': 'connecting'});

    try {
      final executable = WindowsXray.findExecutable();
      if (executable == null) {
        throw const VpnException(
          'xray_missing',
          'xray.exe не найден. Положите его рядом с Curie.exe '
              'или задайте переменную CURIE_XRAY_EXE.',
        );
      }

      final decoder = jsonDecode(config);
      if (decoder is! Map) {
        throw const VpnException(
          'bad_config',
          'конфиг Xray не является объектом',
        );
      }
      final reserved = <int>{
        _portFromMetrics(decoder['metrics']),
        ...?_portsFromInbounds(decoder['inbounds']),
      }..remove(0);
      final proxyPort = await _pickProxyPort(reserved);

      final adapted = adaptConfigForWindows(
        decoder.cast<String, dynamic>(),
        proxyPort: proxyPort,
      );
      _metricsPort = _portFromMetrics(adapted['metrics']);
      // Порт проверки ищем по тегу: в режимах с SOCKS5 он не первый inbound.
      _checkPort = portOfInbound(adapted['inbounds'], 'check');

      final temp = await Directory.systemTemp.createTemp('curie-xray-');
      final configFile = File(
        '${temp.path}${Platform.pathSeparator}config.json',
      );
      await configFile.writeAsString(jsonEncode(adapted), flush: true);
      _configFile = configFile;

      final process = await Process.start(executable, [
        'run',
        '-c',
        configFile.path,
      ], workingDirectory: _dirOf(executable));
      _process = process;
      _stdout = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => AppLog.add('xray', line));
      _stderr = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => AppLog.add('xray', line));

      process.exitCode.then((code) {
        if (!identical(_process, process)) return;
        _cleanupProcess();
        if (status.value == VpnStatus.connected ||
            status.value == VpnStatus.connecting) {
          _apply({'status': 'error', 'error': 'Xray завершился с кодом $code'});
        }
        unawaited(WindowsSystemProxy.restore());
      });

      await _waitForListener(proxyPort);
      await WindowsSystemProxy.enable(
        port: proxyPort,
        mode: settings.routingMode.wireName,
      );

      _startedAt = DateTime.now();
      _apply({
        'status': 'connected',
        'check': _checkPort,
        'metrics': _metricsPort,
        'connectedAt': _startedAt!.millisecondsSinceEpoch,
      });
      // На Windows нет TUN-драйвера: все режимы заканчиваются системным
      // прокси, а SOCKS5 поднимается дополнительно, когда он выбран.
      AppLog.add(
        'vpn',
        'туннель поднят: proxy=$proxyPort check=$_checkPort metrics=$_metricsPort '
            'туннель=${settings.tunnelMode.wireName} '
            'режим=${settings.routingMode.wireName}',
      );
    } on VpnException {
      await _failStart();
      rethrow;
    } on Object catch (e) {
      await _failStart();
      throw VpnException('connect_failed', e.toString());
    }
  }

  static Future<void> _failStart() async {
    final process = _process;
    _process = null;
    await _cleanup();
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Не блокируем показ ошибки, если процесс не отвечает на kill.
      }
    }
    _apply({
      'status': 'error',
      'error': lastError.value ?? 'не удалось поднять туннель',
    });
  }

  static Future<void> disconnect() async {
    final process = _process;
    _process = null;
    _applyDisconnected();
    await WindowsSystemProxy.restore();
    await _cleanupProcess();

    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // Дочерний процесс не ответил — оставляем его; реестр уже восстановлен.
      }
    }
    _startedAt = null;
  }

  static Future<void> _cleanup() async {
    await WindowsSystemProxy.restore();
    await _cleanupProcess();
  }

  static Future<void> _cleanupProcess() async {
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    final file = _configFile;
    _configFile = null;
    if (file != null && file.existsSync()) {
      try {
        await file.parent.delete(recursive: true);
      } on Object {
        // Временный каталог удалится при перезагрузке — не мешаем отключению.
      }
    }
  }

  static Future<void> _waitForListener(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 400),
        );
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      } finally {
        socket?.destroy();
      }
    }
    throw const VpnException(
      'proxy_timeout',
      'Xray не открыл локальный прокси за 12 секунд',
    );
  }

  /// Android-конфиг содержит TUN inbound и ждёт `env."xray.tun.fd"` от Kotlin.
  /// На Windows вместо него поднимается `mixed` inbound на localhost, а
  /// маршруты с `inboundTag: ["tun"]` перенаправляются на новый тег.
  static Map<String, dynamic> adaptConfigForWindows(
    Map<String, dynamic> config, {
    required int proxyPort,
  }) {
    final adapted = Map<String, dynamic>.from(config);
    final inbounds =
        (config['inbounds'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    final result = <Map<String, dynamic>>[];
    for (final inbound in inbounds) {
      if (inbound['protocol'] == 'tun') {
        result.add({
          'tag': 'proxy',
          'port': proxyPort,
          'protocol': 'mixed',
          'listen': '127.0.0.1',
          'settings': <String, dynamic>{
            'auth': 'noauth',
            'udp': true,
            'userLevel': 0,
          },
          'sniffing':
              inbound['sniffing'] ??
              <String, dynamic>{
                'enabled': true,
                'destOverride': ['http', 'tls', 'quic'],
                'routeOnly': false,
              },
        });
      } else {
        result.add(inbound);
      }
    }
    if (!result.any((inbound) => inbound['tag'] == 'proxy')) {
      result.add({
        'tag': 'proxy',
        'port': proxyPort,
        'protocol': 'mixed',
        'listen': '127.0.0.1',
        'settings': <String, dynamic>{
          'auth': 'noauth',
          'udp': true,
          'userLevel': 0,
        },
      });
    }
    adapted['inbounds'] = result;
    // Каталог geoip.dat/geosite.dat должен дойти до ядра; убираем только
    // Android-дескриптор TUN, которого на Windows нет.
    final env =
        (config['env'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    env.remove('xray.tun.fd');
    if (env.isEmpty) {
      adapted.remove('env');
    } else {
      adapted['env'] = env;
    }

    final routing =
        (config['routing'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final rules =
        (routing['rules'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .map((rule) {
              final tags = rule['inboundTag'];
              if (tags is List && tags.contains('tun')) {
                return <String, dynamic>{
                  ...rule,
                  'inboundTag': ['proxy'],
                };
              }
              return rule;
            })
            .toList() ??
        <Map<String, dynamic>>[];
    adapted['routing'] = <String, dynamic>{...routing, 'rules': rules};
    return adapted;
  }

  /// Порт для системного прокси. Не должен совпадать с уже занятыми inbound'ами
  /// из конфига (метрики и локальная проверка): otherwise Xray не поднимется.
  static Future<int> _pickProxyPort(Set<int> reserved) async {
    final candidates = await WindowsXray.freePorts(8);
    for (final port in candidates) {
      if (port > 1024 && !reserved.contains(port)) return port;
    }
    var fallback = 10808;
    while (reserved.contains(fallback)) {
      fallback++;
    }
    return fallback;
  }

  static Set<int>? _portsFromInbounds(Object? inbounds) {
    if (inbounds is! List) return null;
    final ports = <int>{};
    for (final item in inbounds) {
      if (item is! Map) continue;
      final port = (item.cast<String, dynamic>()['port'] as num?)?.toInt();
      if (port != null && port > 0) ports.add(port);
    }
    return ports;
  }

  /// Порт локального HTTP-прокси для проверок и фоновых запросов.
  static int portOfInbound(Object? inbounds, String tag) {
    if (inbounds is! List) return 0;
    for (final item in inbounds) {
      if (item is! Map) continue;
      final inbound = item.cast<String, dynamic>();
      if (inbound['tag'] != tag) continue;
      return (inbound['port'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  static int _portFromMetrics(Object? metrics) {
    final map = (metrics as Map?)?.cast<String, dynamic>();
    final listen = (map?['listen'] as String?) ?? '';
    final match = RegExp(r':(\d+)$').firstMatch(listen);
    return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
  }

  static String _dirOf(String filePath) {
    final separator = Platform.pathSeparator;
    final index = filePath.lastIndexOf(separator);
    return index <= 0 ? filePath : filePath.substring(0, index);
  }

  static VpnStatus _statusFromName(String? name) => switch (name) {
    'connecting' => VpnStatus.connecting,
    'connected' => VpnStatus.connected,
    'disconnecting' => VpnStatus.disconnecting,
    'error' => VpnStatus.error,
    _ => VpnStatus.disconnected,
  };
}

class VpnException implements Exception {
  const VpnException(this.code, this.message);

  final String code;
  final String message;

  bool get isDenied => code == 'vpn_denied';

  @override
  String toString() => message;
}
