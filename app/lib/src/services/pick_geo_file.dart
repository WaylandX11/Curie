import 'package:file_picker/file_picker.dart';

/// Системный выбор `.dat` на Android. file_picker открывает системный
/// документ-пикер и возвращает локальный путь к скопированному файлу.
Future<String?> pickDatFilePath() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['dat'],
  );
  if (picked.isEmpty) return null;
  final path = picked.first.path;
  return (path == null || path.isEmpty) ? null : path;
}
