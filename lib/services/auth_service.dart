import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otp/otp.dart';

// Top-level so compute() can send it to a background isolate.
String _pbkdf2Work(Map<String, dynamic> args) {
  final password = utf8.encode(args['password'] as String);
  final salt = base64Url.decode(args['salt'] as String);
  final iterations = args['iterations'] as int;
  const keyLength = 32;

  final hmac = Hmac(sha256, password);
  final blockCount = (keyLength / 32).ceil();
  final result = <int>[];

  for (int i = 1; i <= blockCount; i++) {
    final saltWithIndex = [
      ...salt,
      (i >> 24) & 0xFF,
      (i >> 16) & 0xFF,
      (i >> 8) & 0xFF,
      i & 0xFF,
    ];
    var u = Uint8List.fromList(hmac.convert(saltWithIndex).bytes);
    final block = Uint8List.fromList(u);
    for (int j = 1; j < iterations; j++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int k = 0; k < block.length; k++) {
        block[k] ^= u[k];
      }
    }
    result.addAll(block);
  }

  return base64Url.encode(Uint8List.fromList(result.sublist(0, keyLength)));
}

class AuthService {
  static const int _saltLength = 32;
  static const int _iterations = 100000;
  static const int maxLoginAttempts = 5;
  static const int lockoutMinutes = 30;
  static const int otpExpiryMinutes = 10;
  static const int maxOtpAttempts = 3;

  // ─── Password ──────────────────────────────────────────

  static String generateSalt() {
    final random = Random.secure();
    final bytes =
        Uint8List.fromList(List.generate(_saltLength, (_) => random.nextInt(256)));
    return base64Url.encode(bytes);
  }

  static Future<String> hashPassword(String password, String salt) {
    return compute(_pbkdf2Work, {
      'password': password,
      'salt': salt,
      'iterations': _iterations,
    });
  }

  static Future<Uint8List> deriveRawKey(String password, String saltB64) async {
    final b64 = await compute(_pbkdf2Work, {
      'password': password,
      'salt': saltB64,
      'iterations': _iterations,
    });
    return base64Url.decode(b64);
  }

  static Future<bool> verifyPassword(
      String password, String salt, String storedHash) async {
    final computed = await hashPassword(password, salt);
    return _constantTimeEquals(computed, storedHash);
  }

  // XOR every char so timing is independent of match position.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ─── Email OTP ─────────────────────────────────────────

  static String generateOtp() {
    final random = Random.secure();
    return (100000 + random.nextInt(900000)).toString();
  }

  static String hashOtp(String otp) =>
      sha256.convert(utf8.encode(otp)).toString();

  static bool verifyOtp(String otp, String storedHash) =>
      _constantTimeEquals(hashOtp(otp), storedHash);

  // ─── TOTP (RFC 6238 / Google Authenticator) ────────────

  static String generateTotpSecret() {
    final random = Random.secure();
    final bytes =
        Uint8List.fromList(List.generate(20, (_) => random.nextInt(256)));
    return _base32Encode(bytes);
  }

  static bool verifyTotpCode(String secret, String code) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Allow ±1 time window (30 s each) to handle clock drift.
    for (int offset = -1; offset <= 1; offset++) {
      final t = now + (offset * 30000);
      final expected = OTP.generateTOTPCodeString(
        secret,
        t,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      if (_constantTimeEquals(expected.padLeft(6, '0'), code.padLeft(6, '0'))) {
        return true;
      }
    }
    return false;
  }

  static String totpQrUri(String username, String secret) {
    final encoded = Uri.encodeComponent('Khazna:$username');
    return 'otpauth://totp/$encoded?secret=$secret&issuer=Khazna&algorithm=SHA1&digits=6&period=30';
  }

  // ─── Lockout ───────────────────────────────────────────

  static bool isLockedOut(String? lockedUntil) {
    if (lockedUntil == null) return false;
    return DateTime.now().isBefore(DateTime.parse(lockedUntil));
  }

  static String newLockoutTimestamp() => DateTime.now()
      .add(const Duration(minutes: lockoutMinutes))
      .toIso8601String();

  static Duration remainingLockout(String? lockedUntil) {
    if (lockedUntil == null) return Duration.zero;
    final remaining = DateTime.parse(lockedUntil).difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ─── Base32 (RFC 4648, no padding) ────────────────────

  static String _base32Encode(Uint8List bytes) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final buf = StringBuffer();
    int bits = 0, value = 0;
    for (final byte in bytes) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        buf.write(alphabet[(value >> bits) & 31]);
      }
    }
    if (bits > 0) buf.write(alphabet[(value << (5 - bits)) & 31]);
    return buf.toString();
  }
}
