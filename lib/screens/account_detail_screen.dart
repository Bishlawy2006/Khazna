import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_model.dart';
import '../models/activity_log_model.dart';
import '../models/transaction_model.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class AccountDetailScreen extends StatefulWidget {
  final AccountModel account;
  final String? bankName;

  const AccountDetailScreen({super.key, required this.account, this.bankName});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  List<TransactionModel> _transactions = [];
  late AccountModel _account;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _loadData();
  }

  Future<void> _loadData() async {
    final txs = await DatabaseHelper.instance
        .getTransactionsForAccount(_account.id!);
    final updated =
        await DatabaseHelper.instance.getAccountById(_account.id!);

    setState(() {
      _transactions = txs;
      if (updated != null) _account = updated;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          _account.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildBalanceHeader(),
                _buildListHeader(),
                Expanded(child: _buildTransactionList()),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTransactionDialog(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add Transaction',
        child: const Icon(Icons.add),
      ),
    );
  }

  // ─── Balance header ────────────────────────────────────

  Widget _buildBalanceHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _account.type.toUpperCase(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'EGP ${_account.balance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _account.name,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: [
          const Text(
            'Transactions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const Spacer(),
          Text(
            '${_transactions.length} total',
            style:
                TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ─── Transaction list ──────────────────────────────────

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No transactions yet.',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap + to log one.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: _transactions.length,
      itemBuilder: (context, index) =>
          _buildTransactionTile(_transactions[index]),
    );
  }

  Widget _buildTransactionTile(TransactionModel tx) {
    final isIncome = tx.type == 'income';
    return GestureDetector(
      onTap: () => _showTransactionDialog(context, existing: tx),
      child: Container(
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
                  Text(
                    tx.date +
                        (tx.time != null ? ' ${tx.time}' : '') +
                        (tx.note != null ? '  •  ${tx.note}' : ''),
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isIncome ? '+' : '-'} EGP ${tx.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isIncome
                        ? Colors.green.shade700
                        : Colors.red,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'tap to edit',
                  style:
                      TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Transaction dialog (add + edit) ──────────────────

  void _showTransactionDialog(
    BuildContext context, {
    TransactionModel? existing,
  }) {
    final isEditing = existing != null;
    final amountCtrl = TextEditingController(
        text: isEditing ? existing.amount.toStringAsFixed(2) : '');
    final categoryCtrl = TextEditingController(
        text: isEditing ? existing.category : '');
    final noteCtrl = TextEditingController(
        text: isEditing ? (existing.note ?? '') : '');
    String selectedType = isEditing ? existing.type : 'expense';
    DateTime selectedDate =
        isEditing ? DateTime.parse(existing.date) : DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          title: Text(isEditing ? 'Edit Transaction' : 'Log Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Type toggle
                Row(
                  children: [
                    Expanded(
                        child: _typeButton('Expense', 'expense',
                            selectedType,
                            () => setDs(() => selectedType = 'expense'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _typeButton('Income', 'income',
                            selectedType,
                            () => setDs(() => selectedType = 'income'))),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Amount (EGP)'),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  autofocus: !isEditing,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Category',
                      hintText: 'e.g. Food, Salary'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 12),
                // Date row
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      selectedDate.toIso8601String().substring(0, 10),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDs(() => selectedDate = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (isEditing)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => _confirmDelete(ctx, existing),
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amount =
                    double.tryParse(amountCtrl.text.trim());
                final category = categoryCtrl.text.trim();
                if (amount == null || category.isEmpty) return;

                final tx = TransactionModel(
                  id: existing?.id,
                  accountId: _account.id!,
                  amount: amount,
                  type: selectedType,
                  category: category,
                  date: selectedDate
                      .toIso8601String()
                      .substring(0, 10),
                  note: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                );

                final db = DatabaseHelper.instance;
                if (isEditing) {
                  await db.updateTransaction(existing, tx);
                  await db.logActivity(ActivityLogModel.transactionEdited(
                    type: tx.type,
                    oldAmount: existing.amount,
                    newAmount: tx.amount,
                    bankName: widget.bankName ?? _account.name,
                    accountName: _account.name,
                    category: tx.category,
                  ));
                  await NotificationService.transactionEdited(
                    oldAmount: existing.amount,
                    newAmount: tx.amount,
                    category: tx.category,
                    bankName: widget.bankName ?? _account.name,
                    accountName: _account.name,
                    note: tx.note,
                    date: tx.date,
                  );
                } else {
                  await db.insertTransaction(tx);
                  await db.logActivity(ActivityLogModel.transactionAdded(
                    type: tx.type,
                    amount: tx.amount,
                    bankName: widget.bankName ?? _account.name,
                    accountName: _account.name,
                    category: tx.category,
                    note: tx.note,
                  ));
                  await NotificationService.transactionAdded(
                    type: tx.type,
                    amount: tx.amount,
                    category: tx.category,
                    bankName: widget.bankName ?? _account.name,
                    accountName: _account.name,
                    note: tx.note,
                    date: tx.date,
                  );
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeButton(
      String label, String value, String selected, VoidCallback onTap) {
    final active = selected == value;
    final color = value == 'expense' ? Colors.red : Colors.green;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext ctx, TransactionModel tx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Transaction'),
        content: const Text(
            'This transaction will be removed and the account balance corrected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = DatabaseHelper.instance;
      await db.deleteTransaction(tx);
      await db.logActivity(ActivityLogModel.transactionDeleted(
        type: tx.type,
        amount: tx.amount,
        bankName: widget.bankName ?? _account.name,
        accountName: _account.name,
        category: tx.category,
      ));
      await NotificationService.transactionDeleted(
        amount: tx.amount,
        category: tx.category,
        bankName: widget.bankName ?? _account.name,
        accountName: _account.name,
        note: tx.note,
        date: tx.date,
      );
      if (ctx.mounted) Navigator.pop(ctx);
      _loadData();
    }
  }
}
