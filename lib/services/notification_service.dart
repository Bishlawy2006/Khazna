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
        const initSettings = InitializationSettings(android: androidInit);
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
    } catch (e) {
      debugPrint('[NotificationService] init failed: $e');
    }
  }

  // ── Show a system popup ─────────────────────────────────
  static Future<void> notify(String title, String body) async {
    if (!_ready) return;
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
        await _flnp.show(
          _notificationId++,
          title,
          body,
          const NotificationDetails(android: androidDetails),
        );
      }
    } catch (e) {
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
