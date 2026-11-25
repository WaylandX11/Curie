import 'dart:io';

/// Узкие обёртки над Windows Registry через `reg.exe`.
///
/// Не используем FFI: в портативной Dart-части нужен только доступ к двум
/// разделам (MachineGuid и настройки системного прокси), а `reg.exe` есть в
/// любой поддерживаемой Windows. Ошибки чтения означают «значения нет» —
/// это нормальный путь для не-Windows окружения и тестов.
class WindowsRegistry {
  static const String internetSettings =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const String cryptography = r'HKLM\SOFTWARE\Microsoft\Cryptography';
  static const String windowsNt =
      r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion';
  static const String systemInformation =
      r'HKLM\SYSTEM\CurrentControlSet\Control\SystemInformation';

  static Future<String?> read(String key, String name) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('reg', ['query', key, '/v', name]);
      if (result.exitCode != 0) return null;
      final output = result.stdout as String;
      for (final line in output.split(RegExp(r'\r?\n'))) {
        final parts = line.trim().split(RegExp(r'\s+'));
        // Формат: MachineGuid    REG_SZ    value
        if (parts.length >= 3 && parts[0] == name) {
          return parts.sublist(2).join(' ').trim();
        }
      }
    } on Object {
      // reg.exe недоступен — считаем, что значения нет.
    }
    return null;
  }

  static Future<bool> writeString(String key, String name, String value) =>
      _write(key, name, 'REG_SZ', value);

  static Future<bool> writeDword(String key, String name, int value) =>
      _write(key, name, 'REG_DWORD', value.toString());

  static Future<bool> delete(String key, String name) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'delete',
        key,
        '/v',
        name,
        '/f',
      ]);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  static Future<bool> _write(
    String key,
    String name,
    String type,
    String value,
  ) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'add',
        key,
        '/v',
        name,
        '/t',
        type,
        '/d',
        value,
        '/f',
      ]);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }
}

/// Системный HTTP-прокси Windows.
///
/// Xray на Windows поднимает локальный `mixed` inbound, поэтому достаточно
/// поставить `127.0.0.1:<port>` в HKCU. Раздельное туннелирование по списку
/// приложений на Windows не поддерживается: `Apps.isSupported == false`,
/// здесь сохраняются только пользовательские исключения адресов.
class WindowsSystemProxy {
  static final Map<String, String?> _saved = {};

  static Future<void> enable({
    required int port,
    required String mode,
  }) async {
    if (!Platform.isWindows) return;

    if (_saved.isEmpty) {
      _saved['ProxyEnable'] =
          await WindowsRegistry.read(WindowsRegistry.internetSettings, 'ProxyEnable');
      _saved['ProxyServer'] =
          await WindowsRegistry.read(WindowsRegistry.internetSettings, 'ProxyServer');
      _saved['ProxyOverride'] =
          await WindowsRegistry.read(WindowsRegistry.internetSettings, 'ProxyOverride');
    }

    await WindowsRegistry.writeString(
      WindowsRegistry.internetSettings,
      'ProxyServer',
      '127.0.0.1:$port',
    );
    await WindowsRegistry.writeDword(
      WindowsRegistry.internetSettings,
      'ProxyEnable',
      1,
    );
    // Не затираем пользовательские исключения. Если их нет, оставляем локальные
    // адреса вне прокси, иначе ломается доступ к самому Xray и локальным сервисам.
    final override =
        await WindowsRegistry.read(WindowsRegistry.internetSettings, 'ProxyOverride');
    if (override == null || override.trim().isEmpty) {
      await WindowsRegistry.writeString(
        WindowsRegistry.internetSettings,
        'ProxyOverride',
        '<local>',
      );
    }
    _refresh();
  }

  static Future<void> restore() async {
    if (!Platform.isWindows || _saved.isEmpty) return;

    final enable = _saved['ProxyEnable'];
    final server = _saved['ProxyServer'];
    final override = _saved['ProxyOverride'];

    await WindowsRegistry.writeDword(
      WindowsRegistry.internetSettings,
      'ProxyEnable',
      _parseDword(enable),
    );
    if (server == null) {
      await WindowsRegistry.delete(WindowsRegistry.internetSettings, 'ProxyServer');
    } else {
      await WindowsRegistry.writeString(
        WindowsRegistry.internetSettings,
        'ProxyServer',
        server,
      );
    }
    if (override == null) {
      await WindowsRegistry.delete(WindowsRegistry.internetSettings, 'ProxyOverride');
    } else {
      await WindowsRegistry.writeString(
        WindowsRegistry.internetSettings,
        'ProxyOverride',
        override,
      );
    }
    _saved.clear();
    _refresh();
  }

  /// Приложение могло завершиться аварийно, не успев вернуть настройки.
  /// Включаем прокси только если в реестре всё ещё нашّ адрес Curie.
  static Future<void> restoreIfStale() async {
    if (!Platform.isWindows) return;
    final server =
        await WindowsRegistry.read(WindowsRegistry.internetSettings, 'ProxyServer');
    if (server == null || !server.contains('127.0.0.1:')) return;
    final enable =
        await WindowsRegistry.read(WindowsRegistry.internetSettings, 'ProxyEnable');
    if (enable == null || _parseDword(enable) == 0) return;
    await WindowsRegistry.writeDword(
      WindowsRegistry.internetSettings,
      'ProxyEnable',
      0,
    );
    _refresh();
  }

  /// `reg query` печатает DWORD как `0x1`, а `int.tryParse` такое не ест.
  static int _parseDword(String? value) {
    if (value == null) return 0;
    final text = value.trim();
    if (text.toLowerCase().startsWith('0x')) {
      return int.tryParse(text.substring(2), radix: 16) ?? 0;
    }
    return int.tryParse(text) ?? 0;
  }

  static void _refresh() {
    // Мгновенно обновляет настройки у части приложений; остальные прочитают
    // реестр при следующем запуске. Ошибка не должна ломать отключение.
    unawaitedSafe(() => Process.run('rundll32', [
          'user32.dll,UpdatePerUserSystemParameters',
        ]));
  }
}

void unawaitedSafe(Future<Object?> Function() action) {
  action().catchError((Object _) => null);
}
