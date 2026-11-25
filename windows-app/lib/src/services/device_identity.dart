import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../generated/build_info.dart';
import 'store.dart';
import 'windows_system.dart';

/// Идентификатор устройства для панелей с лимитом устройств (Remnawave HWID).
///
/// Привязан к машине: на Windows выводится через HMAC-SHA256 из MachineGuid
/// из реестра. Сам аппаратный идентификатор наружу не отправляется: панель
/// видит только подписанное приложением значение формата UUID.
///
/// Отправляется только если пользователь включил HWID в настройках. Сброс
/// намеренно не предусмотрен: ID должен оставаться постоянным.
class DeviceIdentity {
  /// Несекретная соль: отделяет HWID Curie от других потребителей device ID.
  static const String _pepper = 'io.github.waylandx11.curie/hwid/v1';

  static final Hmac _hmac = Hmac.sha256();

  /// Формат: 6B625E5A-26FD-9875-E216-BBFB088FD1AE.
  static final RegExp _pattern = RegExp(
    r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
  );

  static bool isValid(String value) => _pattern.hasMatch(value.toUpperCase());

  /// Выводит стабильный идентификатор из аппаратного ID.
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

  /// Аппаратный ID Windows. Null — тогда используем сохранённый или случайный.
  static Future<String?> _deviceSource() async {
    if (!Platform.isWindows) return null;
    final guid = await WindowsRegistry.read(
      WindowsRegistry.cryptography,
      'MachineGuid',
    );
    final value = guid?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Стабильный ID: каждый раз сверяем его с машиной и обновляем кэш, если
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

    final current = Store.instance.state.value.deviceId;
    if (current != null) {
      final normalized = normalize(current) ?? current;
      if (isValid(normalized)) {
        if (normalized != current) {
          await Store.instance.update(
            (state) => state.copyWith(deviceId: normalized),
          );
        }
        return normalized;
      }
    }

    final id = _randomId();
    await Store.instance.update((state) => state.copyWith(deviceId: id));
    return id;
  }

  /// Крайний случай: платформа не отдала аппаратный ID и сохранённого значения
  /// нет. Обычный HWID всегда выводится из [derive].
  static String _randomId() {
    final bytes = List<int>.generate(16, (_) => _secure.nextInt(256));
    return _group(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase(),
    );
  }

  static final Random _secure = Random.secure();

  /// Заголовки, которые ждёт панель. Пустой map, если HWID выключен.
  static Future<Map<String, String>> headers() async {
    if (!Store.instance.state.value.settings.sendHwid) return const {};

    final id = await ensureId();
    final headers = <String, String>{'x-hwid': id};

    try {
      headers['x-device-os'] = 'Windows';
      final version = await WindowsRegistry.read(
        WindowsRegistry.windowsNt,
        'DisplayVersion',
      );
      final build = await WindowsRegistry.read(
        WindowsRegistry.windowsNt,
        'CurrentBuild',
      );
      final osVersion = version?.trim().isNotEmpty == true
          ? version!.trim()
          : (build?.trim() ?? '');
      if (osVersion.isNotEmpty) headers['x-ver-os'] = osVersion;

      final manufacturer = await WindowsRegistry.read(
        WindowsRegistry.systemInformation,
        'SystemManufacturer',
      );
      final model = await WindowsRegistry.read(
        WindowsRegistry.systemInformation,
        'SystemProductName',
      );
      final device = [
        manufacturer?.trim(),
        model?.trim(),
      ].where((part) => part != null && part.isNotEmpty).join(' ');
      if (device.isNotEmpty) headers['x-device-model'] = device;
      // Не PackageInfo: он может вернуть версию прежней установленной сборки.
      headers['x-app-version'] = buildStamp;
    } on Object {
      // Панели обязателен только x-hwid, остальное — по возможности.
    }

    return headers;
  }
}
