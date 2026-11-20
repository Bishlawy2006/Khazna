import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/budget_model.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';

const _commonCategories = [
  'Food', 'Transport', 'Shopping', 'Bills', 'Health',
  'Entertainment', 'Education', 'Subscriptions', 'Other',
];

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _db = DatabaseHelper.instance;
  List<BudgetModel> _budgets = [];
  Map<String, double> _monthSpending = {};
  Set<String> _usedCategories = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final budgets = await _db.getBudgets();
    final txs = await _db.getAllTransactions();
    final now = DateTime.now();
    final spending = <String, double>{};
    final used = <String>{};

    for (final tx in txs) {
      used.add(tx.category);
      if (tx.type != 'expense') continue;
      final d = DateTime.parse(tx.date);
      if (d.year == now.year && d.month == now.month) {
        spending[tx.category] = (spending[tx.category] ?? 0) + tx.amount;
      }
    }

    if (mounted) {
      setState(() {
        _budgets = budgets;
        _monthSpending = spending;
        _usedCategories = used;
        _loading = false;
      });
    }
  }

  // ─── Add / Edit dialog ─────────────────────────────────

  void _showDialog({BudgetModel? existing}) {
    final catCtrl = TextEditingController(text: existing?.category ?? '');
    final limitCtrl = TextEditingController(
        text: existing != null ? existing.monthlyLimit.toStringAsFixed(0) : '');
    String? error;

    // Suggestions: common categories + categories from transactions,
    // minus ones already budgeted (except the one being edited).
    final alreadyBudgeted = _budgets.map((b) => b.category).toSet();
    if (existing != null) alreadyBudgeted.remove(existing.category);

    final suggestions = {
      ..._commonCategories,
      ..._usedCategories,
    }.where((c) => !alreadyBudgeted.contains(c)).toList()..sort();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Add Budget' : 'Edit Budget',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category field
                const Text('Category',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: catCtrl,
                  enabled: existing == null, // can't rename existing category
                  decoration: InputDecoration(
                    hintText: 'e.g. Food',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                if (existing == null && suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: suggestions.take(12).map((s) {
                      return GestureDetector(
                        onTap: () => catCtrl.text = s,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primaryFaded,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(s,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                // Monthly limit field
                const Text('Monthly Limit (EGP)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: limitCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: 'EGP ',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final cat = catCtrl.text.trim();
                final limit = double.tryParse(limitCtrl.text.trim());
                if (cat.isEmpty) {
                  setD(() => error = 'Category is required.');
                  return;
                }
                if (limit == null || limit <= 0) {
                  setD(() => error = 'Enter a valid limit greater than 0.');
                  return;
                }
                final budget = BudgetModel(
                  id: existing?.id,
                  category: cat,
                  monthlyLimit: limit,
                  createdAt: existing?.createdAt ??
                      DateTime.now().toIso8601String(),
                );
                await _db.upsertBudget(budget);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BudgetModel budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Budget'),
        content:
            Text('Remove the budget limit for "${budget.category}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteBudget(budget.id!);
      _load();
    }
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Monthly Budgets',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add Budget',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _budgets.isEmpty ? _buildEmpty() : _buildList(),
            ),
    );
  }

  Widget _buildList() {
    // Summary stats
    int onTrack = 0, near = 0, over = 0;
    for (final b in _budgets) {
      final spent = _monthSpending[b.category] ?? 0;
      final pct = spent / b.monthlyLimit;
      if (pct > 1.0) {
        over++;
      } else if (pct > 0.75) {
        near++;
      } else {
        onTrack++;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildSummaryCard(onTrack, near, over),
        const SizedBox(height: 16),
        ..._budgets.map((b) => _buildBudgetCard(b)),
      ],
    );
  }

  Widget _buildSummaryCard(int onTrack, int near, int over) {
    final now = DateTime.now();
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${months[now.month]} ${now.year}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              _statChip('$onTrack On Track', Colors.greenAccent),
              const SizedBox(width: 8),
              if (near > 0) ...[
                _statChip('$near Near Limit', Colors.orangeAccent),
                const SizedBox(width: 8),
              ],
              if (over > 0)
                _statChip('$over Over Budget', Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildBudgetCard(BudgetModel budget) {
    final spent = _monthSpending[budget.category] ?? 0;
    final pct = (spent / budget.monthlyLimit).clamp(0.0, double.infinity);
    final isOver = pct > 1.0;
    final isNear = pct > 0.75 && !isOver;

    final barColor = isOver
        ? AppColors.error
        : isNear
            ? AppColors.warning
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isOver
            ? Border.all(color: AppColors.error.withValues(alpha: 0.4))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Category icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_categoryIcon(budget.category),
                      color: barColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(budget.category,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.textPrimary)),
                      Text(
                        isOver
                            ? 'Over by EGP ${fmtMoney(spent - budget.monthlyLimit)}'
                            : 'EGP ${fmtMoney(budget.monthlyLimit - spent)} remaining',
                        style: TextStyle(
                            fontSize: 12,
                            color: isOver ? AppColors.error : AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                // Actions
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textSecondary),
                  onPressed: () => _showDialog(existing: budget),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppColors.error),
                  onPressed: () => _delete(budget),
                  tooltip: 'Delete',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: barColor.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            // Spent / limit
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('EGP ${fmtMoney(spent)} spent',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: barColor)),
                Text('Limit: EGP ${fmtMoney(budget.monthlyLimit)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 20),
            const Text('No budgets yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Set monthly limits per category to track your spending and get warnings when you\'re close.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _showDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Budget'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(220, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':           return Icons.restaurant_outlined;
      case 'transport':      return Icons.directions_car_outlined;
      case 'shopping':       return Icons.shopping_bag_outlined;
      case 'bills':          return Icons.receipt_outlined;
      case 'health':         return Icons.favorite_border;
      case 'entertainment':  return Icons.movie_outlined;
      case 'education':      return Icons.school_outlined;
      case 'subscriptions':  return Icons.subscriptions_outlined;
      default:               return Icons.category_outlined;
    }
  }
}
