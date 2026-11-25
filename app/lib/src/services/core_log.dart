import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Журнал самого ядра Xray.
///
/// libXray не умеет отдавать логи через `invoke`, поэтому конфиг пишет
/// `log.error` в приватный файл приложения. Файл читается только здесь и
/// очищается по времени; адреса в строках маскируются самим ядром.
class CoreLog {
  static const String fileName = 'curie-xray.log';
  static const int maxBytes = 2 * 1024 * 1024;

  static Future<File> file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  /// Путь для конфига Xray. Создаём каталог заранее: Go-писатель не создаёт его.
  static Future<String> ensurePath() async {
    final target = await file();
    final parent = target.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    return target.path;
  }

  static Future<List<String>> read({
    Duration retention = const Duration(hours: 24),
  }) async {
    final target = await file();
    if (!await target.exists()) return const [];
    final lines = await target.readAsLines();
    return applyRetention(lines, retention: retention);
  }

  /// Чистая функция: можно проверять без файловой системы.
  static List<String> applyRetention(
    List<String> lines, {
    Duration retention = const Duration(hours: 24),
    DateTime? now,
    int maxBytesLimit = maxBytes,
  }) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(retention);
    final fresh = <String>[];
    for (final line in lines) {
      final time = _timeOf(line);
      // Строки без распознанной даты (продолжение сообщения) оставляем:
      // выбросить их нельзя, а объём всё равно ограничен снизу.
      if (time == null || !time.isBefore(cutoff)) fresh.add(line);
    }

    var bytes = 0;
    var start = fresh.length;
    for (var i = fresh.length - 1; i >= 0; i--) {
      final lineBytes = _utf8Length(fresh[i]);
      // Перевод между строками считаем только если уже есть предыдущая строка:
      // у последней перевода ещё нет.
      final next = bytes == 0 ? lineBytes : bytes + 1 + lineBytes;
      if (next > maxBytesLimit) break;
      bytes = next;
      start = i;
    }
    return fresh.sublist(start);
  }

  static Future<void> prune({
    Duration retention = const Duration(hours: 24),
  }) async {
    final target = await file();
    if (!await target.exists()) return;
    final lines = await target.readAsLines();
    final kept = applyRetention(lines, retention: retention);
    if (kept.length == lines.length) return;
    await target.writeAsString('${kept.join('\n')}\n');
  }

  static Future<void> clear() async {
    final target = await file();
    if (await target.exists()) await target.writeAsString('');
  }

  static Future<String> dump({
    Duration retention = const Duration(hours: 24),
  }) async {
    final lines = await read(retention: retention);
    return lines.join('\n');
  }

  static DateTime? _timeOf(String line) {
    final match = RegExp(
      r'^(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(line);
    if (match == null) return null;
    return DateTime.tryParse(
      '${match.group(1)}-${match.group(2)}-${match.group(3)}'
      'T${match.group(4)}:${match.group(5)}:${match.group(6)}',
    );
  }

  static int _utf8Length(String value) => value.length +
      value.runes.where((r) => r > 0x7f).fold<int>(0, (sum, r) {
        if (r <= 0x7ff) return sum + 1;
        if (r <= 0xffff) return sum + 2;
        // Суррогатная пара уже занимает два UTF-16 юнита в `value.length`.
        return sum + 2;
      });
}
