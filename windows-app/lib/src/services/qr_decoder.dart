import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Декодирование QR из файла.
///
/// `mobile_scanner` не поддерживает Windows, поэтому камера заменена на
/// выбор файла через `image_picker`, а изображение разбирается локально.
class QrDecoder {
  static Future<String?> decodeFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // QR часто сохраняют как 1-битный PNG. Без явного uint8 getBytes()
      // вернёт упакованные биты, а не 4 байта на пиксель.
      final converted = decoded.convert(
        numChannels: 4,
        format: img.Format.uint8,
      );
      final raw = converted.getBytes(order: img.ChannelOrder.argb);
      final pixels = Int32List(decoded.width * decoded.height);
      for (var i = 0; i < pixels.length; i++) {
        final offset = i * 4;
        pixels[i] = (raw[offset] << 24) |
            (raw[offset + 1] << 16) |
            (raw[offset + 2] << 8) |
            raw[offset + 3];
      }

      final source = RGBLuminanceSource(decoded.width, decoded.height, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final result = QRCodeReader().decode(bitmap);
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } on Object {
      return null;
    }
  }
}
