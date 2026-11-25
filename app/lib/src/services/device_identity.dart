import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import '../generated/build_info.dart';
import 'store.dart';

/// Идентификатор устройства для панелей с лимитом устройств (Remnawave HWID).
///
/// Привязан к телефону: выводится через HMAC-SHA256 из ANDROID_ID (Android) или
/// identifierForVendor (iOS). Поэтому один и тот же телефон получает тот же ID
/// и после обновления, и после переустановки, а разные телефоны — разные ID.
/// Сам аппаратный идентификатор наружу не отправляется: панель видит только
/// подписанное приложением значение формата UUID.
///
/// Отправляется только если пользователь включил HWID в настройках. Сброс
/// намеренно не предусмотрен: ID должен оставаться постоянным.
class DeviceIdentity {
  static const MethodChannel _channel =
      MethodChannel('io.github.waylandx11.curie/bridge');

  /// Несекретная соль: отделяет HWID Curie от других потребителей device ID.
  static const String _pepper = 'io.github.waylandx11.curie/hwid/v1';

  static final Hmac _hmac = Hmac.sha256();

  /// Формат: 6B625E5A-26FD-9875-E216-BBFB088FD1AE.
  /// Панель принимает `[a-zA-Z0-9=-]{10,64}`, дефисы допустимы.
  static final RegExp _pattern = RegExp(
    r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
  );

  static bool isValid(String value) => _pattern.hasMatch(value.toUpperCase());

  /// Выводит стабильный идентификатор из аппаратного ID: одно и то же устройство
  /// всегда даёт один и тот же HWID.
  static Future<String> derive(String deviceIdSource) async {
    final mac = await _hmac.calculateMac(
      utf8.encode(deviceIdSource),
      secretKey: SecretKey(utf8.encode(_pepper)),
    );
    final hex = mac.bytes
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return _group(hex);
  }

  /// Переводит старый 32-символьный hex в новый формат, не меняя байты.
  static String? normalize(String value) {
    final hex = value.trim().toUpperCase().replaceAll('-', '');
    if (hex.length != 32 || RegExp(r'^[0-9A-F]{32}$').hasMatch(hex) == false) {
      return null;
    }
    return _group(hex);
  }

  static String _group(String hex) => [
        hex.substring(0, 8),
        hex.substring(8, 12),
        hex.substring(12, 16),
        hex.substring(16, 20),
        hex.substring(20, 32),
      ].join('-');

  /// ID телефона, если платформа его отдаёт. Null — тогда используем сохранённый
  /// или случайный ID (например, на неподдерживаемой платформе).
  static Future<String?> _deviceSource() async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<String>('androidId');
      }
      if (Platform.isIOS) {
        return (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } on Object {
      // Разрешений не нужно, но на кастомных прошивках метод может отсутствовать.
    }
    return null;
  }

  /// Стабильный ID: каждый раз сверяем его с телефоном и обновляем кэш, если
  /// устройство сменилось. Возвращает готовый HWID.
  static Future<String> ensureId() async {
    final source = await _deviceSource();
    if (source != null && source.trim().isNotEmpty) {
      final id = await derive(source.trim());
      final current = Store.instance.state.value.deviceId;
      if (current != id) {
        await Store.instance.update((state) => state.copyWith(deviceId: id));
      }
      return id;
    }

    // Нет аппаратного ID — держим уже сохранённый, при необходимости
    // переводим в текущий формат.
    final current = Store.instance.state.value.deviceId;
    if (current != null) {
      final normalized = normalize(current) ?? current;
      if (isValid(normalized)) {
        if (normalized != current) {
          await Store.instance.update((state) => state.copyWith(deviceId: normalized));
        }
        return normalized;
      }
    }

    final id = _randomId();
    await Store.instance.update((state) => state.copyWith(deviceId: id));
    return id;
  }

  /// Крайний случай: платформа не отдала аппаратный ID и сохранённого значения
  /// нет. Обычный HWID всегда выводится из устройства через [derive].
  static String _randomId() {
    final bytes = List<int>.generate(16, (_) => _secure.nextInt(256));
    return _group(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase());
  }

  static final Random _secure = Random.secure();

  /// Заголовки, которые ждёт панель. Пустой map, если HWID выключен.
  static Future<Map<String, String>> headers() async {
    if (!Store.instance.state.value.settings.sendHwid) return const {};

    final id = await ensureId();
    final headers = <String, String>{'x-hwid': id};

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        headers['x-device-os'] = 'Android';
        headers['x-ver-os'] = android.version.release;
        headers['x-device-model'] = '${android.manufacturer} ${android.model}'.trim();
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        headers['x-device-os'] = ios.systemName;
        headers['x-ver-os'] = ios.systemVersion;
        headers['x-device-model'] = ios.utsname.machine;
      }
      // Не PackageInfo: он может вернуть версию прежней установленной сборки.
      headers['x-app-version'] = buildStamp;
    } on Object {
      // Панели обязателен только x-hwid, остальное — по возможности.
    }

    return headers;
  }
}
