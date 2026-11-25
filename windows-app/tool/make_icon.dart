import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Собирает Windows .ico из Android launcher-иконки.
///
/// Внутри ICO хранятся PNG-кадры — это поддерживается Windows Vista+ и
/// сохраняет прозрачность без ручного создания BMP DIB.
Future<void> main(List<String> args) async {
  final sourcePath = args.isEmpty
      ? r'..\app\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png'
      : args.first;
  final outputPath = args.length > 1
      ? args[1]
      : r'windows\runner\resources\app_icon.ico';

  final source = img.decodeImage(await File(sourcePath).readAsBytes());
  if (source == null) throw Exception('Не удалось прочитать PNG: $sourcePath');

  const sizes = [16, 24, 32, 48, 64, 128, 256];
  final frames = <(int size, Uint8List bytes)>[];
  for (final size in sizes) {
    final resized = img.copyResize(
      source,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    frames.add((size, img.encodePng(resized)));
  }

  final header = ByteData(6 + 16 * frames.length);
  header.setUint16(0, 0, Endian.little); // reserved
  header.setUint16(2, 1, Endian.little); // type: icon
  header.setUint16(4, frames.length, Endian.little);

  var offset = 6 + 16 * frames.length;
  for (var i = 0; i < frames.length; i++) {
    final entry = 6 + 16 * i;
    final (size, bytes) = frames[i];
    header.setUint8(entry, size == 256 ? 0 : size);
    header.setUint8(entry + 1, size == 256 ? 0 : size);
    header.setUint8(entry + 2, 0); // palette size
    header.setUint8(entry + 3, 0); // reserved
    header.setUint16(entry + 4, 1, Endian.little); // planes
    header.setUint16(entry + 6, 32, Endian.little); // bits per pixel
    header.setUint32(entry + 8, bytes.length, Endian.little);
    header.setUint32(entry + 12, offset, Endian.little);
    offset += bytes.length;
  }

  final output = BytesBuilder()
    ..add(header.buffer.asUint8List())
    ..add(frames.map((frame) => frame.$2).expand((bytes) => bytes).toList());
  await File(outputPath).writeAsBytes(output.takeBytes(), flush: true);

  stdout.writeln('$outputPath: ${frames.map((f) => f.$1).join(', ')}');
}
