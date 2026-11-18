import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/activity_log_model.dart';
import 'auto_transaction_service.dart';

/// Drains the SMS queue written by the iOS "Process Bank SMS" App Intent
/// (see ios/Runner/ProcessBankSMSIntent.swift) and feeds each message into
/// [AutoTransactionService].
///
/// Flow:
///   bank SMS → Shortcuts automation → App Intent appends a line to
///   khazna_sms_queue.jsonl → [drain] runs on app launch / resume →
///   AutoTransactionService.processNotification(text)
///
/// iOS only. On every other platform [drain] is a no-op.
class SmsQueueService {
  SmsQueueService._();

  static const _queueFileName = 'khazna_sms_queue.jsonl';
  static bool _draining = false;

  /// Processes every queued message. Returns how many became transactions.
  static Future<int> drain() async {
    if (!Platform.isIOS || _draining) return 0;
    _draining = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final queue = File('${dir.path}/$_queueFileName');
      final work = File('${dir.path}/$_queueFileName.processing');

      // Rename first so the intent keeps appending to a fresh queue file
      // while we work. A leftover .processing file means an earlier drain was
      // interrupted: finish it before touching the new queue.
      if (!await work.exists()) {
        if (!await queue.exists()) return 0;
        await queue.rename(work.path);
      }

      var created = 0;
      for (final line in await work.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final text = map['text'] as String;
          if (await AutoTransactionService.processNotification(text)) {
            created++;
          } else {
            await _logUnparsed();
          }
        } catch (e) {
          debugPrint('[SmsQueueService] bad queue line skipped: $e');
        }
      }
      await work.delete();
      return created;
    } catch (e) {
      debugPrint('[SmsQueueService] drain failed: $e');
      return 0;
    } finally {
      _draining = false;
    }
  }

  /// Visible proof in the Activity screen that a Shortcut reached the app.
  /// Deliberately does NOT store the SMS text (it contains balances and
  /// account digits) — only the fact that one arrived.
  static Future<void> _logUnparsed() {
    return DatabaseHelper.instance.logActivity(
      ActivityLogModel(
        action: 'sms_received',
        title: 'Bank SMS received',
        message: 'A bank SMS reached Khazna through Shortcuts but could not '
            'be turned into a transaction.',
        dateTime: DateTime.now().toIso8601String(),
        type: 'update',
      ),
    );
  }
}

/// Re-drains the queue whenever the app returns to the foreground, so SMS that
/// arrived while Khazna was in the background are picked up.
class SmsQueueLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(SmsQueueService.drain());
    }
  }
}
