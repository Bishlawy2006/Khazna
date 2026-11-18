import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

/// Remembers that the user is signed in, so force-closing the app does not
/// send them back to the password screen.
///
/// Security model
///   * The password (and 2FA) is still required for the FIRST sign-in and after
///     "Sign Out". Nothing about the password is stored here.
///   * On iOS the remembered session is additionally protected by Face ID /
///     Touch ID, with the iPhone passcode as the OS-provided fallback. That
///     replaces typing the password + 2FA code on every launch with something
///     at least as strong: the phone's own lock.
///   * If biometrics are switched off in Settings, or the phone has no passcode
///     at all, the session is remembered without a lock. Settings says so.
///   * Other platforms (Android / Windows): "stay signed in" works, but there
///     is no biometric lock yet (it needs extra Android setup).
///
/// Only two booleans and a timestamp are stored, in a small JSON file in the
/// app's private support directory.
class SessionService {
  SessionService._();

  static const _fileName = 'khazna_session.json';
  static final _auth = LocalAuthentication();

  // ─── storage ──────────────────────────────────────────

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (e) {
      debugPrint('[SessionService] read failed: $e');
      return {};
    }
  }

  static Future<void> _update(Map<String, dynamic> changes) async {
    try {
      final data = await _read()..addAll(changes);
      await (await _file()).writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('[SessionService] write failed: $e');
    }
  }

  // ─── settings (defaults: both ON) ─────────────────────

  static Future<bool> staySignedIn() async =>
      (await _read())['stay'] as bool? ?? true;

  static Future<bool> biometricLock() async =>
      (await _read())['biometric'] as bool? ?? true;

  static Future<void> setStaySignedIn(bool value) async {
    await _update({'stay': value});
    if (!value) await clear();
  }

  static Future<void> setBiometricLock(bool value) =>
      _update({'biometric': value});

  /// True if this phone can show a Face ID / Touch ID / passcode prompt.
  /// iOS only for now.
  static Future<bool> biometricAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  // ─── session lifecycle ────────────────────────────────

  /// Call once the user has fully signed in (password + 2FA).
  static Future<void> markSignedIn() =>
      _update({'signedIn': true, 'signedInAt': DateTime.now().toIso8601String()});

  /// Call on Sign Out. The user settings above are kept.
  static Future<void> clear() => _update({'signedIn': false});

  /// Prompts Face ID / Touch ID / passcode. False on cancel or any failure.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      debugPrint('[SessionService] auth failed: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('[SessionService] auth error: $e');
      return false;
    }
  }

  /// Decides at app launch whether to skip the password screen.
  /// Returns true only if a session is remembered AND (when a lock applies)
  /// the lock was passed.
  static Future<bool> tryResume() async {
    final data = await _read();
    if (data['signedIn'] != true) return false;
    if (!(data['stay'] as bool? ?? true)) return false;

    final wantsLock = data['biometric'] as bool? ?? true;
    if (wantsLock && await biometricAvailable()) {
      return authenticate('Unlock Khazna');
    }
    return true;
  }
}
