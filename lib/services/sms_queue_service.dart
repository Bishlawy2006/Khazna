import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/activity_log_model.dart';
import 'auto_transaction_service.dart';

/// Drains the queue written by the iOS "Process Bank SMS" and "Add Entry"
/// App Intents
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
  static const _intentLogFileName = 'khazna_intent_log.txt';
  static bool _draining = false;

  /// Human-readable result of the most recent drain (diagnostics screen).
  static String lastReport = 'drain() not run yet';

  /// Snapshot of queue state for the diagnostics screen. No SMS content.
  static Future<String> debugSnapshot() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final queue = File('${dir.path}/$_queueFileName');
      final work = File('${dir.path}/$_queueFileName.processing');
      final log = File('${dir.path}/$_intentLogFileName');
      final b = StringBuffer('dir: ${dir.path}\n');
      b.writeln('queue file: ${await queue.exists() ? "EXISTS (${await queue.length()} bytes)" : "absent"}');
      b.writeln('.processing: ${await work.exists() ? "EXISTS (${await work.length()} bytes)" : "absent"}');
      b.writeln('last drain: $lastReport');
      b.writeln('--- intent log (last 8) ---');
      if (await log.exists()) {
        final lines = await log.readAsLines();
        b.writeln(lines.skip(lines.length > 8 ? lines.length - 8 : 0).join('\n'));
      } else {
        b.writeln('(no intent log: the Shortcut action has NEVER run perform())');
      }
      return b.toString();
    } catch (e) {
      return 'snapshot failed: $e';
    }
  }

  /// Writes a fake message straight into the queue, bypassing Shortcuts, so
  /// the Dart half of the pipeline can be tested on its own.
  static Future<void> enqueueTestMessage() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final queue = File('${dir.path}/$_queueFileName');
    final line = jsonEncode({
      'text': 'EGP diagnostics test message',
      'receivedAt': DateTime.now().toIso8601String(),
    });
    await queue.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  /// Processes every queued message. Returns how many became transactions.
  static Future<int> drain() async {
    if (!Platform.isIOS) {
      lastReport = 'skipped: not iOS';
      return 0;
    }
    if (_draining) {
      lastReport = 'skipped: a drain was already running';
      return 0;
    }
    _draining = true;
    lastReport = 'started ${DateTime.now()}';
    try {
      final dir = await getApplicationSupportDirectory();
      final queue = File('${dir.path}/$_queueFileName');
      final work = File('${dir.path}/$_queueFileName.processing');

      // Rename first so the intent keeps appending to a fresh queue file
      // while we work. A leftover .processing file means an earlier drain was
      // interrupted: finish it before touching the new queue.
      if (!await work.exists()) {
        if (!await queue.exists()) {
          lastReport = 'ran ${DateTime.now()}: queue empty';
          return 0;
        }
        await queue.rename(work.path);
      }

      var created = 0;
      var seen = 0;
      var failed = 0;
      var duplicates = 0;
      String? lastLineError;
      for (final line in await work.readAsLines()) {
        if (line.trim().isEmpty) continue;
        seen++;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final receivedAt =
              DateTime.tryParse(map['receivedAt'] as String? ?? '')?.toLocal();
          final SmsOutcome outcome;
          if (map['kind'] == 'entry') {
            // Quick "Add Entry" from the lock screen / Back Tap / Shortcuts.
            outcome = await AutoTransactionService.processQuickEntry(
              bankKey: map['bank'] as String,
              type: map['type'] as String,
              amount: (map['amount'] as num).toDouble(),
              note: map['note'] as String?,
              receivedAt: receivedAt,
            );
          } else {
            outcome = await AutoTransactionService.processNotification(
              map['text'] as String,
              receivedAt: receivedAt,
            );
          }
          switch (outcome) {
            case SmsOutcome.created:
              created++;
            case SmsOutcome.duplicate:
              duplicates++;
            case SmsOutcome.unparsed:
              await _logUnparsed();
          }
        } catch (e) {
          failed++;
          lastLineError = '$e';
          debugPrint('[SmsQueueService] bad queue line skipped: $e');
          // Still leave proof in Activity so a failure is never silent.
          try {
            await _logUnparsed();
          } catch (_) {}
        }
      }
      await work.delete();
      lastReport = 'ran ${DateTime.now()}: messages=$seen created=$created '
          'duplicates=$duplicates failed=$failed${lastLineError == null ? '' : ' ($lastLineError)'}';
      return created;
    } catch (e) {
      lastReport = 'drain FAILED: $e';
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
