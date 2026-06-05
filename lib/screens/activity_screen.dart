import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/activity_log_model.dart';
import '../theme/app_theme.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _db = DatabaseHelper.instance;
  List<ActivityLogModel> _logs = [];
  String _filter = 'All'; // 'All', 'Income', 'Expense', 'Update', 'Deleted'
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _db.getActivityLogs();
    if (mounted) setState(() { _logs = logs; _loading = false; });
  }

  Future<void> _markAllRead() async {
    await _db.markAllActivityRead();
    _load();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all activity?'),
        content: const Text('This will permanently delete all activity history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.clearActivityLogs();
      _load();
    }
  }

  List<ActivityLogModel> get _filtered {
    if (_filter == 'All') return _logs;
    if (_filter == 'Income') return _logs.where((l) => l.type == 'income').toList();
    if (_filter == 'Expense') return _logs.where((l) => l.type == 'expense').toList();
    if (_filter == 'Update') return _logs.where((l) => l.type == 'update').toList();
    if (_filter == 'Deleted') return _logs.where((l) => l.action == 'deleted').toList();
    return _logs;
  }

  // Group logs by date label
  Map<String, List<ActivityLogModel>> get _grouped {
    final result = <String, List<ActivityLogModel>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final log in _filtered) {
      final dt = DateTime.parse(log.dateTime);
      final day = DateTime(dt.year, dt.month, dt.day);
      final String label;
      if (day == today) {
        label = 'Today';
      } else if (day == yesterday) {
        label = 'Yesterday';
      } else {
        label = '${dt.day} ${_monthName(dt.month)} ${dt.year}';
      }
      result.putIfAbsent(label, () => []).add(log);
    }
    return result;
  }

  String _monthName(int m) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m];
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final groupKeys = grouped.keys.toList();
    final unread = _logs.where((l) => !l.isRead).length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Activity', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (unread > 0)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, color: Colors.white70, size: 18),
              label: const Text('Mark all read', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) { if (v == 'clear') _clearAll(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear all history')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterBar(),
                Expanded(
                  child: _filtered.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: groupKeys.fold<int>(0, (sum, k) => sum + 1 + grouped[k]!.length),
                            itemBuilder: (ctx, i) {
                              int offset = 0;
                              for (final key in groupKeys) {
                                if (i == offset) return _dateHeader(key);
                                offset++;
                                final items = grouped[key]!;
                                if (i < offset + items.length) {
                                  return _logTile(items[i - offset]);
                                }
                                offset += items.length;
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar() {
    const filters = ['All', 'Income', 'Expense', 'Update', 'Deleted'];
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: filters.map((f) {
            final selected = _filter == f;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(f),
                selected: selected,
                onSelected: (_) => setState(() => _filter = f),
                selectedColor: AppColors.primaryFaded,
                checkmarkColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _dateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _logTile(ActivityLogModel log) {
    final isUnread = !log.isRead;
    final icon = _iconForAction(log.action, log.type);
    final iconColor = _colorForType(log.type);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isUnread ? AppColors.primaryFaded.withValues(alpha: 0.4) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isUnread
            ? Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3))
            : null,
        boxShadow: isUnread ? null : AppShadows.card,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          log.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              log.message,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(log.dateTime),
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.7)),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: isUnread
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            _filter == 'All' ? 'No activity yet' : 'No $_filter activity',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Your financial changes will appear here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  IconData _iconForAction(String action, String type) {
    if (action == 'deleted') return Icons.delete_outline_rounded;
    if (action == 'balance_updated') return Icons.account_balance_wallet_outlined;
    if (action == 'edited') return Icons.edit_outlined;
    if (type == 'income') return Icons.arrow_downward_rounded;
    if (type == 'expense') return Icons.arrow_upward_rounded;
    return Icons.receipt_long_outlined;
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'income': return AppColors.success;
      case 'expense': return AppColors.error;
      case 'deletion': return AppColors.error;
      default: return AppColors.primaryLight;
    }
  }

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
