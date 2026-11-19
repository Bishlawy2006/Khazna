import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';

class AllTransactionsScreen extends StatefulWidget {
  const AllTransactionsScreen({super.key});

  @override
  State<AllTransactionsScreen> createState() =>
      _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen> {
  List<TransactionModel> _transactions = [];
  Map<int, AccountModel> _accountsMap = {};
  bool _isLoading = true;

  // Filter state
  String _typeFilter = 'all'; // 'all' | 'income' | 'expense'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final allTxs =
        await DatabaseHelper.instance.getAllTransactions();

    final Map<int, AccountModel> accountsMap = {};
    for (final tx in allTxs) {
      if (!accountsMap.containsKey(tx.accountId)) {
        final acc =
            await DatabaseHelper.instance.getAccountById(tx.accountId);
        if (acc != null) accountsMap[tx.accountId] = acc;
      }
    }

    setState(() {
      _transactions = allTxs;
      _accountsMap = accountsMap;
      _isLoading = false;
    });
  }

  List<TransactionModel> get _filtered {
    if (_typeFilter == 'all') return _transactions;
    return _transactions
        .where((t) => t.type == _typeFilter)
        .toList();
  }

  double get _totalIncome => _transactions
      .where((t) => t.type == 'income')
      .fold(0.0, (s, t) => s + t.amount);

  double get _totalExpense => _transactions
      .where((t) => t.type == 'expense')
      .fold(0.0, (s, t) => s + t.amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'All Transactions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryHeader(),
                _buildFilterBar(),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  // ─── Summary header ────────────────────────────────────

  Widget _buildSummaryHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Row(
        children: [
          Expanded(
            child: _summaryTile(
              label: 'Total Income',
              amount: _totalIncome,
              icon: Icons.arrow_downward,
              color: Colors.green.shade300,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _summaryTile(
              label: 'Total Expenses',
              amount: _totalExpense,
              icon: Icons.arrow_upward,
              color: Colors.red.shade300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String label,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style:
                      const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'EGP ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filter bar ────────────────────────────────────────

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Text(
            '${_filtered.length} transaction${_filtered.length == 1 ? '' : 's'}',
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade500),
          ),
          const Spacer(),
          _filterChip('All', 'all'),
          const SizedBox(width: 6),
          _filterChip('Income', 'income'),
          const SizedBox(width: 6),
          _filterChip('Expense', 'expense'),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _typeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = value),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // ─── Date grouping ─────────────────────────────────────

  String _dateLabel(String dateStr) {
    final dt = DateTime.parse(dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  // Returns an ordered list of [String (date header) | TransactionModel]
  List<Object> get _groupedItems {
    final items = _filtered;
    final result = <Object>[];
    String? lastLabel;
    for (final tx in items) {
      final label = _dateLabel(tx.date);
      if (label != lastLabel) {
        result.add(label);
        lastLabel = label;
      }
      result.add(tx);
    }
    return result;
  }

  // ─── Transaction list ──────────────────────────────────

  Widget _buildList() {
    final items = _filtered;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _typeFilter == 'all'
                  ? 'No transactions yet.'
                  : 'No $_typeFilter transactions.',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final grouped = _groupedItems;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final item = grouped[index];
        if (item is String) return _buildDateHeader(item);
        return _buildTile(item as TransactionModel);
      },
    );
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildTile(TransactionModel tx) {
    final isIncome = tx.type == 'income';
    final account = _accountsMap[tx.accountId];
    final accountLabel = account != null
        ? account.name
        : 'Unknown Account';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isIncome
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isIncome ? Icons.arrow_downward : Icons.arrow_upward,
              color: isIncome ? Colors.green : Colors.red,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.category,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 11, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        accountLabel,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '•  ${tx.date}${tx.time != null ? ' ${tx.time}' : ''}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                if (tx.note != null && tx.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      tx.note!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIncome ? '+' : '-'} EGP ${tx.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color:
                  isIncome ? Colors.green.shade700 : Colors.red,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
