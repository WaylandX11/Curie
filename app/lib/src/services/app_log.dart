import 'package:material_ui/material_ui.dart';

class LogEntry {
  const LogEntry(this.time, this.tag, this.message);

  final DateTime time;
  final String tag;
  final String message;

  String format() {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    return '$t [$tag] $message';
  }
}

/// Кольцевой журнал в памяти: подключения, ошибки ядра, обновления подписок.
/// Ничего не пишет на диск и никуда не отправляет — нужен, чтобы пользователь
/// мог показать ошибку, не подключая отладчик.
class AppLog {
  static const int limit = 300;

  static final ValueNotifier<List<LogEntry>> entries = ValueNotifier(const []);

  static void add(String tag, String message) {
    final next = [...entries.value, LogEntry(DateTime.now(), tag, message)];
    entries.value = next.length > limit ? next.sublist(next.length - limit) : next;
  }

  static String dump() => entries.value.map((e) => e.format()).join('\n');

  static void clear() => entries.value = const [];
}
