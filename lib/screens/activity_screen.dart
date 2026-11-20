import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/activity_log_model.dart';
import '../theme/app_theme.dart';
import '../utils/bank_icons.dart';
import '../utils/formatting.dart';

/// Activity feed: one calm line per event (bank logo, name, amount), grouped
/// by day. A single row of chips filters by bank; "All" shows everything.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _db = DatabaseHelper.instance;
  List<ActivityLogModel> _logs = [];
  String? _bank; // null = All
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _db.getActivityLogs();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
      // The selected bank may have no entries any more (e.g. history cleared).
      if (_bank != null && !logs.any((l) => l.bankName == _bank)) _bank = null;
    });
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
        content:
            const Text('This will permanently delete all activity history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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

  // ─── Data shaping ──────────────────────────────────────

  /// Banks that have at least one entry, most recently active first
  /// (the log list is already newest-first).
  List<String> get _banks {
    final seen = <String>[];
    for (final l in _logs) {
      final b = l.bankName;
      if (b != null && b.isNotEmpty && !seen.contains(b)) seen.add(b);
    }
    return seen;
  }

  List<ActivityLogModel> get _filtered =>
      _bank == null ? _logs : _logs.where((l) => l.bankName == _bank).toList();

  /// Flat list for the ListView: a String is a day header, a model is a row.
  List<Object> _items() {
    final items = <Object>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String? lastLabel;
    for (final log in _filtered) {
      final dt = DateTime.parse(log.dateTime);
      final day = DateTime(dt.year, dt.month, dt.day);
      final String label;
      if (day == today) {
        label = 'Today';
      } else if (day == yesterday) {
        label = 'Yesterday';
      } else {
        label = dt.year == now.year
            ? '${dt.day} ${_mon(dt.month)}'
            : '${dt.day} ${_mon(dt.month)} ${dt.year}';
      }
      if (label != lastLabel) {
        items.add(label);
        lastLabel = label;
      }
      items.add(log);
    }
    return items;
  }

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String _mon(int m) => _months[m];

  /// Short name of the entry: the place / category, not a sentence.
  String _titleOf(ActivityLogModel l) {
    final c = l.category?.trim();
    final hasCategory = c != null && c.isNotEmpty;
    switch (l.action) {
      case 'added':
        return hasCategory ? c : l.title;
      case 'edited':
        return hasCategory ? 'Edited $c' : 'Edited';
      case 'deleted':
        return hasCategory ? 'Deleted $c' : 'Deleted';
      case 'balance_updated':
        return 'Balance updated';
      default:
        return l.title;
    }
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final unread = _logs.where((l) => !l.isRead).length;
    final banks = _banks;
    final items = _items();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _header(unread),
                  if (banks.isNotEmpty) _chips(banks),
                  Expanded(
                    child: items.isEmpty
                        ? _empty()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              itemCount: items.length,
                              itemBuilder: (_, i) {
                                final it = items[i];
                                return it is String
                                    ? _dayHeader(it)
                                    : _row(it as ActivityLogModel);
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _header(int unread) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
      child: Row(
        children: [
          const Text(
            'Activity',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const Spacer(),
          if (unread > 0)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all_rounded,
                  color: AppColors.textPrimary),
            ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            onSelected: (v) {
              if (v == 'clear') _clearAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear all history')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chips(List<String> banks) {
    final labels = ['All', ...banks];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final label = labels[i];
          final selected = i == 0 ? _bank == null : _bank == label;
          return Semantics(
            button: true,
            selected: selected,
            label: label,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => setState(() => _bank = i == 0 ? null : label),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryFaded : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dayHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _row(ActivityLogModel log) {
    final isUnread = !log.isRead;
    final amount = log.amount;

    // Direction is shown by the sign and colour of the amount: green for money
    // in, plain ink for money out, grey for edits / deletes / balance changes.
    String? amountText;
    Color amountColor = AppColors.textSecondary;
    if (amount != null) {
      if (log.action == 'added') {
        final income = log.type == 'income';
        amountText = '${income ? '+' : '-'}${fmtMoney(amount)}';
        amountColor = income ? AppColors.success : AppColors.textPrimary;
      } else {
        amountText = fmtMoney(amount);
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          _bankTile(log.bankName),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _titleOf(log),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (amountText != null) ...[
            const SizedBox(width: 12),
            Text(
              amountText,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: amountColor,
                decoration:
                    log.action == 'deleted' ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Round bank logo; Cash gets a banknote icon, anything unknown a neutral bell.
  Widget _bankTile(String? bankName) {
    final asset = bankIconAsset(bankName);
    if (asset != null) {
      return Semantics(
        label: bankName,
        child: Container(
          width: 40,
          height: 40,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.divider),
          ),
          child: Image.asset(asset, fit: BoxFit.cover),
        ),
      );
    }
    final isCash = (bankName ?? '').toLowerCase().contains('cash');
    return Semantics(
      label: isCash ? 'Cash' : 'Activity',
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCash ? AppColors.successFaded : AppColors.primaryFaded,
        ),
        child: Icon(
          isCash ? Icons.payments_outlined : Icons.notifications_none_rounded,
          size: 20,
          color: isCash ? AppColors.success : AppColors.primaryLight,
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Text(
        _bank == null ? 'No activity yet' : 'No activity for $_bank',
        style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
      ),
    );
  }
}
