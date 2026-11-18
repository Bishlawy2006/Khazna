import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/sms_queue_service.dart';

/// iOS-only troubleshooting screen (reachable from Settings → App).
///
/// Shows what is actually happening on the device for the two iOS features
/// that cannot be debugged from a PC: local notifications and the
/// Shortcuts → "Process Bank SMS" → queue → Khazna pipeline.
/// Never displays SMS content, only counts and statuses.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  String _notif = 'loading…';
  String _queue = 'loading…';
  String _action = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final perm = await NotificationService.iosPermissionStatus();
    final queue = await SmsQueueService.debugSnapshot();
    if (!mounted) return;
    setState(() {
      _notif = 'init: ${NotificationService.lastInitResult}\n'
          'permission: $perm\n'
          'last notify: ${NotificationService.lastNotifyResult}';
      _queue = queue;
    });
  }

  Future<void> _run(String label, Future<String> Function() job) async {
    setState(() => _action = '$label…');
    final result = await job();
    if (!mounted) return;
    setState(() => _action = '$label → $result');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iOS diagnostics'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heading('Notifications'),
          _box(_notif),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: () => _run('Test notification', () async {
                await NotificationService.notify(
                    'Khazna test', 'If you can read this, banners work.');
                return NotificationService.lastNotifyResult;
              }),
              child: const Text('Send test notification'),
            ),
            OutlinedButton(
              onPressed: () => _run('Request permission',
                  NotificationService.iosRequestPermission),
              child: const Text('Request permission'),
            ),
          ]),
          const SizedBox(height: 24),
          _heading('SMS pipeline'),
          _box(_queue),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: () => _run('Drain queue', () async {
                final n = await SmsQueueService.drain();
                return 'transactions created: $n';
              }),
              child: const Text('Drain queue now'),
            ),
            OutlinedButton(
              onPressed: () => _run('Test message', () async {
                await SmsQueueService.enqueueTestMessage();
                final n = await SmsQueueService.drain();
                return 'queued + drained (created: $n). '
                    'Check Activity for "Bank SMS received".';
              }),
              child: const Text('Queue a test message'),
            ),
          ]),
          if (_action.isNotEmpty) ...[
            const SizedBox(height: 16),
            _box(_action),
          ],
        ],
      ),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _box(String t) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(t,
            style: const TextStyle(fontFamily: 'Courier', fontSize: 12)),
      );
}
