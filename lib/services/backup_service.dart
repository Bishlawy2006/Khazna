import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'auth_service.dart';

class BackupService {
  static const List<int> _magic = [0x4B, 0x5A, 0x4E, 0x41]; // "KZNA"
  static const int _version = 1;

  static String _randomSaltB64() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    return base64Url.encode(bytes);
  }

  /// Encrypt [data] with [password] and share (Android) or save to Documents (Windows).
  /// Returns the saved file path on desktop platforms, null on mobile.
  static Future<String?> exportVault(
      Map<String, dynamic> data, String password) async {
    final plainBytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));

    final saltB64 = _randomSaltB64();
    final keyBytes = await AuthService.deriveRawKey(password, saltB64);
    final iv = enc.IV.fromSecureRandom(16);

    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);

    // File layout: magic(4) | version(1) | salt(32) | iv(16) | ciphertext
    final out = BytesBuilder();
    out.add(_magic);
    out.addByte(_version);
    out.add(base64Url.decode(saltB64));
    out.add(iv.bytes);
    out.add(encrypted.bytes);

    final now = DateTime.now();
    final name =
        'khazna_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.khazna';

    if (Platform.isAndroid || Platform.isIOS) {
      final tmp = await getTemporaryDirectory();
      final file = File(p.join(tmp.path, name));
      await file.writeAsBytes(out.toBytes());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'Khazna Vault Backup',
      );
      return null;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'Khazna'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(out.toBytes());
      return file.path;
    }
  }

  /// Decrypt a `.khazna` file and return its data.
  /// Throws a human-readable exception on failure.
  static Future<Map<String, dynamic>> importVault(
      String filePath, String password) async {
    final bytes = await File(filePath).readAsBytes();

    if (bytes.length < 4 + 1 + 32 + 16 + 16) {
      throw Exception('Invalid or corrupted backup file.');
    }
    for (int i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) throw Exception('Not a valid Khazna backup file.');
    }
    if (bytes[4] != _version) {
      throw Exception('Unsupported backup version (${bytes[4]}).');
    }

    final saltB64 = base64Url.encode(bytes.sublist(5, 37));
    final iv = enc.IV(Uint8List.fromList(bytes.sublist(37, 53)));
    final cipherBytes = enc.Encrypted(Uint8List.fromList(bytes.sublist(53)));

    final keyBytes = await AuthService.deriveRawKey(password, saltB64);
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));

    try {
      final decrypted = encrypter.decryptBytes(cipherBytes, iv: iv);
      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Incorrect password or corrupted backup.');
    }
  }
}
