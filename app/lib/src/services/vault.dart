import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Шифрованное хранилище состояния.
///
/// Ключ AES-256-GCM лежит в Keystore/Keychain через flutter_secure_storage,
/// сами данные — отдельным файлом: подписки бывают большими, а preferences
/// для таких объёмов не предназначены. На диске не остаётся ничего открытого.
class Vault {
  Vault({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'curie.vault.key';
  static const _fileName = 'curie-state.bin';

  final FlutterSecureStorage _storage;
  final AesGcm _cipher = AesGcm.with256bits();

  SecretKey? _key;

  Future<SecretKey> _loadKey() async {
    final cached = _key;
    if (cached != null) return cached;

    final stored = await _storage.read(key: _keyName);
    if (stored != null) {
      final key = await _cipher.newSecretKeyFromBytes(base64Decode(stored));
      _key = key;
      return key;
    }

    final key = await _cipher.newSecretKey();
    final bytes = await key.extractBytes();
    await _storage.write(key: _keyName, value: base64Encode(bytes));
    _key = key;
    return key;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<Map<String, dynamic>> read() async {
    final file = await _file();
    if (!await file.exists()) return {};

    final bytes = await file.readAsBytes();
    // nonce (12) + ciphertext + mac (16)
    if (bytes.length < 12 + 16) return {};

    final nonce = bytes.sublist(0, 12);
    final mac = Mac(bytes.sublist(bytes.length - 16));
    final cipherText = bytes.sublist(12, bytes.length - 16);

    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: await _loadKey(),
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  Future<void> write(Map<String, dynamic> data) async {
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: await _loadKey(),
      nonce: nonce,
    );

    final bytes = Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);

    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
