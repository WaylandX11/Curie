import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

class LogEntry {
  const LogEntry(this.time, this.tag, this.message);

  final DateTime time;
  final String tag;
  final String message;

  Map<String, dynamic> toJson() => <String, dynamic>{
    't': time.millisecondsSinceEpoch,
    'g': tag,
    'm': message,
  };

  static LogEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final time = value['t'];
    final tag = value['g'];
    final message = value['m'];
    if (time is! int || tag is! String || message is! String) return null;
    return LogEntry(DateTime.fromMillisecondsSinceEpoch(time), tag, message);
  }

  String format() {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    return '$t [$tag] $message';
  }
}

/// Кольцевой журнал на 300 записей: подключения, ошибки ядра, обновления подписок.
///
/// Журнал шифрованно сохраняется в FlutterSecureStorage и переживает
/// пересоздание Flutter-движка: возврат в приложение больше не выглядит как
/// новый «запуск Curie». Никуда не отправляется.
class AppLog {
  static const int limit = 300;
  static const String _entriesKey = 'curie.app_log.entries.v1';
  static const String _tokenKey = 'curie.app_log.process_token.v1';
  static const MethodChannel _channel = MethodChannel(
    'io.github.waylandx11.curie/bridge',
  );

  static final FlutterSecureStorage _storage = FlutterSecureStorage();

  static final ValueNotifier<List<LogEntry>> entries = ValueNotifier(const []);

  static bool _initialized = false;
  static bool _freshStart = false;
  static String _processToken = 'desktop';
  static bool _dirty = false;
  static bool _writing = false;
  static Future<void> _writeChain = Future<void>.value();

  /// Восстанавливает журнал. Возвращает true, только если это реальный старт
  /// процесса: при простом пересоздании UI токен процесса не меняется.
  static Future<bool> init() async {
    if (_initialized) return _freshStart;
    _initialized = true;
    _processToken = await _currentProcessToken();

    List<LogEntry> restored = const [];
    String? storedToken;
    try {
      final raw = await _storage.read(key: _entriesKey);
      if (raw != null && raw.isNotEmpty) restored = _decode(raw);
      storedToken = await _storage.read(key: _tokenKey);
    } on Object catch (_) {
      // Хранилище недоступно — журнал работает в памяти, как и раньше.
    }

    if (restored.isNotEmpty) {
      final merged = <LogEntry>[...restored, ...entries.value]
        ..sort((a, b) => a.time.compareTo(b.time));
      entries.value = merged.length > limit
          ? merged.sublist(merged.length - limit)
          : merged;
    }

    _freshStart = storedToken != _processToken;
    if (_freshStart) _queuePersist();
    return _freshStart;
  }

  static Future<String> _currentProcessToken() async {
    if (!Platform.isAndroid) return 'desktop';
    try {
      return await _channel.invokeMethod<String>('processToken') ?? 'android';
    } on Object catch (_) {
      return 'android';
    }
  }

  static List<LogEntry> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(LogEntry.fromJson).whereType<LogEntry>().toList();
    } on Object catch (_) {
      return const [];
    }
  }

  static void add(String tag, String message) {
    final next = [...entries.value, LogEntry(DateTime.now(), tag, message)];
    entries.value = next.length > limit
        ? next.sublist(next.length - limit)
        : next;
    _queuePersist();
  }

  /// Точный заголовок должен попадать в журнал один раз за процесс, даже если
  /// из-за пересоздания движка сбросился флаг в user_agent.dart.
  static bool contains(String tag, String message) => entries.value.any(
    (entry) => entry.tag == tag && entry.message == message,
  );

  static String dump() => entries.value.map((e) => e.format()).join('\n');

  static void clear() {
    entries.value = const [];
    _queuePersist();
  }

  static void _queuePersist() {
    _dirty = true;
    if (_writing) return;
    _writing = true;
    _writeChain = _writeChain.then((_) async {
      while (_dirty) {
        _dirty = false;
        await _persist();
      }
      _writing = false;
    });
  }

  static Future<void> _persist() async {
    try {
      await _storage.write(
        key: _entriesKey,
        value: jsonEncode(entries.value.map((e) => e.toJson()).toList()),
      );
      await _storage.write(key: _tokenKey, value: _processToken);
    } on Object catch (_) {
      // Best effort: потеря журнала не должна ломать приложение.
    }
  }
}
