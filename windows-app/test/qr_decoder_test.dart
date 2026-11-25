import 'dart:convert';
import 'dart:io';

import 'package:curie_windows/src/services/qr_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a 1-bit PNG QR code from a file', () async {
    // Сгенерированный QR со ссылкой: vless://test@example.com
    const base64Png =
        'iVBORw0KGgoAAAANSUhEUgAAAZAAAAGQAQMAAAC6caSPAAAABlBMVEX///8AAABVwtN+'
        'AAAACXBIWXMAAA7EAAAOxAGVKw4bAAABV0lEQVR4nO3Yy46DMBBEUfPl/DmeCe1ylwm'
        'Rki19SyI80oddyUBrv2fvnteV+P3P1o+xeQ4I5DEki/AaDnj+1c7hYM1uA4GUJqqXKqa'
        'yGdlGvSAQiJF5FOOqFQQCua3YpMcch0AgkyhZs1GtHFMgkOLEY0zVUr0UCKQw+ZS5IH0'
        'fCOTxZF/q9XbsRdPiBIGUJVqEYlDnM9tt1SCQwmRF4ywe3fSrG8QxBFKU7N1L1WfmgD4'
        'UCEEghYkq5vtz02KkeNkgkCeQfXZF47bCZGfy3QUCKU+iXt25ypUrjPYQSHmSs4PngrS+'
        'wzQIBBKjWbR+zV3FIJBi5BrBM1mtfJR7DwRShuxLj7xsY1E6bIurEEhh4vVaSuYfBja7'
        'BQRSmlzrdfMA52sYBAJZyLnPhUjLUVAIBDJJbC0/p11feiCQ0kRZSA4pn576IJBCxKNx'
        'G2qG4hoEUpb8nj8zTLqH2yA97QAAAABJRU5ErkJggg==';

    final dir = await Directory.systemTemp.createTemp('curie-qr-test-');
    final file = File('${dir.path}${Platform.pathSeparator}qr.png');
    await file.writeAsBytes(base64Decode(base64Png));
    addTearDown(() => dir.delete(recursive: true));

    expect(await QrDecoder.decodeFile(file.path), 'vless://test@example.com');
  });

  test('returns null for a file without a QR code', () async {
    final dir = await Directory.systemTemp.createTemp('curie-qr-test-');
    final file = File('${dir.path}${Platform.pathSeparator}empty.png');
    // 1x1完全透明 PNG.
    await file.writeAsBytes(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAE'
      'BgH/alT9AAAAAElFTkSuQmCC',
    ));
    addTearDown(() => dir.delete(recursive: true));

    expect(await QrDecoder.decodeFile(file.path), isNull);
  });
}
