import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_model.dart';
import '../models/activity_log_model.dart';
import '../models/transaction_model.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  AccountModel? _cashAccount;
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final account = await DatabaseHelper.instance.ensureCashAccountExists();
    final updated = await DatabaseHelper.instance.getAccountById(account.id!);
    final txs = await DatabaseHelper.instance
        .getTransactionsForAccount(account.id!);
    setState(() {
      _cashAccount = updated ?? account;
      _transactions = txs;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.cashGreen,
        foregroundColor: Colors.white,
        title: const Text('Cash', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildTransactionList()),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    final balance = _cashAccount?.balance ?? 0.0;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF2E7D32),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        children: [
          const Icon(Icons.payments_outlined, color: Colors.white54, size: 28),
          const SizedBox(height: 8),
          Text(
            'EGP ${fmtMoney(balance)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cash on Hand',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: 'Money Out',
                  icon: Icons.arrow_upward,
                  iconColor: Colors.red.shade300,
                  onTap: () =>
                      _showTransactionDialog(context, initialType: 'expense'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  label: 'Money In',
                  icon: Icons.arrow_downward,
                  iconColor: Colors.white,
                  onTap: () =>
                      _showTransactionDialog(context, initialType: 'income'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No cash transactions yet.',
              style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use Money In / Money Out above.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                  '${isIncome ? '+' : '-'} EGP ${fmtMoney(tx.amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isIncome ? Colors.green.shade700 : Colors.red,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'tap to edit',
                  style: TextStyle(color: Colors.grey, fontSize: 10),
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
    String initialType = 'expense',
    TransactionModel? existing,
  }) {
    final isEditing = existing != null;
    final amountCtrl = TextEditingController(
        text: isEditing ? existing.amount.toStringAsFixed(2) : '');
    final categoryCtrl =
        TextEditingController(text: isEditing ? existing.category : '');
    final noteCtrl =
        TextEditingController(text: isEditing ? (existing.note ?? '') : '');
    String selectedType = isEditing ? existing.type : initialType;
    DateTime selectedDate =
        isEditing ? DateTime.parse(existing.date) : DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(isEditing ? 'Edit Transaction' : 'Log Cash Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Type toggle
                Row(
                  children: [
                    Expanded(
                        child: _typeButton('Money Out', 'expense', selectedType,
                            () => setDs(() => selectedType = 'expense'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _typeButton('Money In', 'income', selectedType,
                            () => setDs(() => selectedType = 'income'))),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Amount (EGP)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: !isEditing,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(
                      labelText: 'What is it? (e.g. Groceries, Salary)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 12),
                // Date picker row
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
                        if (picked != null) setDs(() => selectedDate = picked);
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
                final amount = double.tryParse(amountCtrl.text.trim());
                final category = categoryCtrl.text.trim();
                if (amount == null || category.isEmpty) return;

                final tx = TransactionModel(
                  id: existing?.id,
                  accountId: _cashAccount!.id!,
                  amount: amount,
                  type: selectedType,
                  category: category,
                  date: selectedDate.toIso8601String().substring(0, 10),
                  note: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                  // Time of day only when entered for today (back-dated: unknown).
                  time: nowTimeIfToday(selectedDate),
                );

                final db = DatabaseHelper.instance;
                if (isEditing) {
                  await db.updateTransaction(existing, tx);
                  await db.logActivity(ActivityLogModel.transactionEdited(
                    type: tx.type,
                    oldAmount: existing.amount,
                    newAmount: tx.amount,
                    bankName: 'Cash',
                    accountName: 'Cash Wallet',
                    category: tx.category,
                  ));
                  await NotificationService.transactionEdited(
                    oldAmount: existing.amount,
                    newAmount: tx.amount,
                    category: tx.category,
                    bankName: 'Cash',
                    accountName: 'Cash Wallet',
                    note: tx.note,
                    date: tx.date,
                  );
                } else {
                  await db.insertTransaction(tx);
                  await db.logActivity(ActivityLogModel.transactionAdded(
                    type: tx.type,
                    amount: tx.amount,
                    bankName: 'Cash',
                    accountName: 'Cash Wallet',
                    category: tx.category,
                    note: tx.note,
                  ));
                  await NotificationService.transactionAdded(
                    type: tx.type,
                    amount: tx.amount,
                    category: tx.category,
                    bankName: 'Cash',
                    accountName: 'Cash Wallet',
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

  Future<void> _confirmDelete(BuildContext ctx, TransactionModel tx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Transaction'),
        content: const Text(
            'This will be removed and the cash balance will be corrected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
        bankName: 'Cash',
        accountName: 'Cash Wallet',
        category: tx.category,
      ));
      await NotificationService.transactionDeleted(
        amount: tx.amount,
        category: tx.category,
        bankName: 'Cash',
        accountName: 'Cash Wallet',
        note: tx.note,
        date: tx.date,
      );
      if (ctx.mounted) Navigator.pop(ctx);
      _loadData();
    }
  }
}
