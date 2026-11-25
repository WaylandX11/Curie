/// Приложение из списка Android — для раздельного туннелирования.
///
/// Иконки в модель не входят: список полный (все установленные пакеты), и
/// картинку каждая строка просит отдельно через `Apps.icon`.
class AppInfo {
  const AppInfo({
    required this.packageName,
    required this.label,
    this.system = false,
  });

  final String packageName;
  final String label;
  final bool system;

  factory AppInfo.fromMap(Map<String, dynamic> map) => AppInfo(
        packageName: map['package'] as String,
        label: (map['label'] as String?) ?? (map['package'] as String),
        system: (map['system'] as bool?) ?? false,
      );
}
