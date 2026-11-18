import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  static bool _ready = false;
  static int _notificationId = 0;
  static final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();

  static const _androidChannelId = 'khazna_channel';
  static const _androidChannelName = 'Khazna Notifications';

  // Diagnostics (shown on the iOS diagnostics screen).
  static String lastInitResult = 'initialize() not run yet';
  static String lastNotifyResult = 'notify() not called yet';

  /// iOS only: what the OS says about this app's notification permission.
  static Future<String> iosPermissionStatus() async {
    try {
      final ios = _flnp.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios == null) return 'iOS plugin implementation not found';
      final o = await ios.checkPermissions();
      if (o == null) return 'checkPermissions returned null';
      return 'enabled=${o.isEnabled}  alert=${o.isAlertEnabled}  '
          'sound=${o.isSoundEnabled}  badge=${o.isBadgeEnabled}';
    } catch (e) {
      return 'checkPermissions failed: $e';
    }
  }

  /// iOS only: asks the OS for permission again (no-op if already decided).
  static Future<String> iosRequestPermission() async {
    try {
      final ios = _flnp.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted =
          await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return 'requestPermissions → $granted';
    } catch (e) {
      return 'requestPermissions failed: $e';
    }
  }

  // ── Initialize once at startup ─────────────────────────
  static Future<void> initialize() async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await localNotifier.setup(
          appName: 'Khazna',
          shortcutPolicy: ShortcutPolicy.requireCreate,
        );
      } else if (Platform.isAndroid || Platform.isIOS) {
        const androidInit =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        // iOS needs its own settings: without them the plugin never
        // registers for iOS and the permission prompt is never shown.
        const iosInit = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        const initSettings =
            InitializationSettings(android: androidInit, iOS: iosInit);
        await _flnp.initialize(initSettings);

        const channel = AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: 'Transaction and account notifications',
          importance: Importance.high,
        );
        await _flnp
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        await _flnp
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _ready = true;
      lastInitResult = 'ok';
    } catch (e) {
      lastInitResult = 'FAILED: $e';
      debugPrint('[NotificationService] init failed: $e');
    }
  }

  // ── Show a system popup ─────────────────────────────────
  static Future<void> notify(String title, String body) async {
    if (!_ready) {
      lastNotifyResult = 'skipped: service not ready (init failed)';
      return;
    }
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final notification = LocalNotification(title: title, body: body);
        await notification.show();
      } else if (Platform.isAndroid || Platform.isIOS) {
        const androidDetails = AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: 'Transaction and account notifications',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );
        // iOS suppresses notifications while the app is open unless the
        // presentation options are set explicitly. Khazna fires these right
        // after the user taps "add", i.e. always in the foreground.
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        );
        await _flnp.show(
          _notificationId++,
          title,
          body,
          const NotificationDetails(android: androidDetails, iOS: iosDetails),
        );
        lastNotifyResult = 'show() completed at ${DateTime.now()}';
      }
    } catch (e) {
      lastNotifyResult = 'show() FAILED: $e';
      debugPrint('[NotificationService] notify failed: $e');
    }
  }

  // ── Typed helpers ──────────────────────────────────────

  static Future<void> transactionAdded({
    required String type,
    required double amount,
    required String category,
    required String bankName,
    required String accountName,
    String? note,
    String? date,
  }) {
    final action = type == 'income' ? 'Received' : 'Paid';
    final now = DateTime.now();
    final timeStr = '${_pad(now.hour)}:${_pad(now.minute)}';
    final dateLabel = date != null ? _fmtDate(date) : _fmtDateNow(now);
    final noteStr = (note != null && note.isNotEmpty) ? '  ·  $note' : '';
    return notify(
      '$action EGP ${amount.toStringAsFixed(2)}  ·  $category',
      '$bankName – $accountName\n$dateLabel at $timeStr$noteStr',
    );
  }

  static Future<void> transactionEdited({
    required double oldAmount,
    required double newAmount,
    required String category,
    required String bankName,
    required String accountName,
    String? note,
    String? date,
  }) {
    final now = DateTime.now();
    final timeStr = '${_pad(now.hour)}:${_pad(now.minute)}';
    final dateLabel = date != null ? _fmtDate(date) : _fmtDateNow(now);
    final noteStr = (note != null && note.isNotEmpty) ? '  ·  $note' : '';
    return notify(
      'Transaction updated  ·  $category',
      'EGP ${oldAmount.toStringAsFixed(2)} → EGP ${newAmount.toStringAsFixed(2)}'
          '\n$bankName – $accountName  ·  $dateLabel at $timeStr$noteStr',
    );
  }

  static Future<void> transactionDeleted({
    required double amount,
    required String category,
    required String bankName,
    required String accountName,
    String? note,
    String? date,
  }) {
    final now = DateTime.now();
    final timeStr = '${_pad(now.hour)}:${_pad(now.minute)}';
    final dateLabel = date != null ? _fmtDate(date) : _fmtDateNow(now);
    final noteStr = (note != null && note.isNotEmpty) ? '  ·  $note' : '';
    return notify(
      'Removed EGP ${amount.toStringAsFixed(2)}  ·  $category',
      '$bankName – $accountName  ·  $dateLabel at $timeStr$noteStr',
    );
  }

  static Future<void> balanceUpdated({
    required String bankName,
    required String accountName,
    required double oldBalance,
    required double newBalance,
  }) {
    final now = DateTime.now();
    final timeStr = '${_pad(now.hour)}:${_pad(now.minute)}';
    final dateLabel = _fmtDateNow(now);
    final diff = newBalance - oldBalance;
    final sign = diff >= 0 ? '+' : '';
    return notify(
      'Balance updated  ·  $accountName',
      '$bankName  ·  ${sign}EGP ${diff.toStringAsFixed(2)}'
          '  →  EGP ${newBalance.toStringAsFixed(2)}'
          '\n$dateLabel at $timeStr',
    );
  }

  // ── Private formatters ─────────────────────────────────

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmtDate(String iso) {
    final dt = DateTime.parse(iso);
    return '${dt.day} ${_months[dt.month]} ${dt.year}';
  }

  static String _fmtDateNow(DateTime dt) =>
      '${dt.day} ${_months[dt.month]} ${dt.year}';

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
