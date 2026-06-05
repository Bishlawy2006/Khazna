import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/account_model.dart';
import '../models/activity_log_model.dart';
import '../models/essential_model.dart';
import '../models/transaction_model.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class EssentialsScreen extends StatefulWidget {
  const EssentialsScreen({super.key});

  @override
  State<EssentialsScreen> createState() => _EssentialsScreenState();
}

class _EssentialsScreenState extends State<EssentialsScreen> {
  final _db = DatabaseHelper.instance;

  List<EssentialModel> _essentials = [];
  double _totalBalance = 0;
  double _savingsTarget = 0;
  bool _loading = true;

  // Current accounts available to pay from
  List<AccountModel> _currentAccounts = [];
  // accountId → "BankName · AccountName" (for display)
  Map<int, String> _accountLabels = {};
  // accountId → bank name (for activity log)
  Map<int, String> _accountBankNames = {};

  static String get _currentMonth {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String get _monthLabel {
    final now = DateTime.now();
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[now.month]} ${now.year}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final essentials = await _db.getEssentials();
    final balance    = await _db.getTotalBalance();
    final savStr     = await _db.getSetting('savings_target');

    // Build account maps for the account picker and display labels
    final allBanks = await _db.getAllBanks();
    final currentAccounts  = <AccountModel>[];
    final accountLabels    = <int, String>{};
    final accountBankNames = <int, String>{};

    for (final bank in allBanks) {
      final accounts = await _db.getAccountsForBank(bank.id!);
      for (final acc in accounts) {
        accountLabels[acc.id!] = '${bank.name} · ${acc.name}';
        accountBankNames[acc.id!] = bank.name;
        if (acc.type == 'current') {
          currentAccounts.add(acc);
        }
      }
    }

    if (mounted) {
      setState(() {
        _essentials        = essentials;
        _totalBalance      = balance;
        _savingsTarget     = double.tryParse(savStr ?? '0') ?? 0;
        _currentAccounts   = currentAccounts;
        _accountLabels     = accountLabels;
        _accountBankNames  = accountBankNames;
        _loading           = false;
      });
    }
  }

  // ─── Derived values ────────────────────────────────────

  double get _essentialsTotal =>
      _essentials.fold(0.0, (s, e) => s + e.amount);

  double get _paidTotal =>
      _essentials.where((e) => e.isPaidThisMonth).fold(0.0, (s, e) => s + e.amount);

  double get _unpaidTotal => _essentialsTotal - _paidTotal;

  bool get _allPaid =>
      _essentials.isNotEmpty && _essentials.every((e) => e.isPaidThisMonth);

  double get _balanceAfterEssentials => _totalBalance - _essentialsTotal;

  // ─── Mark as paid ──────────────────────────────────────

  Future<void> _handlePaid(EssentialModel e) async {
    if (_currentAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No current accounts found. Add a current account first.')));
      return;
    }

    // Reload fresh account balances for display in picker
    final freshAccounts = <AccountModel>[];
    for (final acc in _currentAccounts) {
      final fresh = await _db.getAccountById(acc.id!);
      if (fresh != null) freshAccounts.add(fresh);
    }

    if (!mounted) return;

    final picked = await showDialog<AccountModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay from which account?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: freshAccounts.map((acc) {
            final label = _accountLabels[acc.id] ?? acc.name;
            final balance = acc.balance;
            final canCover = balance >= e.amount;
            return ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryFaded,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_outlined,
                    color: AppColors.primary, size: 18),
              ),
              title: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(
                'EGP ${balance.toStringAsFixed(2)}${canCover ? '' : ' — insufficient'}',
                style: TextStyle(
                    fontSize: 12,
                    color: canCover
                        ? AppColors.textSecondary
                        : AppColors.error),
              ),
              onTap: () => Navigator.pop(ctx, acc),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );

    if (picked == null || !mounted) return;

    // Create the expense transaction
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final tx = TransactionModel(
      accountId: picked.id!,
      amount: e.amount,
      type: 'expense',
      category: e.name,
      date: today,
      note: 'from essentials',
    );

    final txId = await _db.insertTransaction(tx);

    final bankName = _accountBankNames[picked.id] ?? '';

    // Log to activity
    await _db.logActivity(ActivityLogModel.transactionAdded(
      type: 'expense',
      amount: e.amount,
      bankName: bankName,
      accountName: picked.name,
      category: e.name,
      note: 'from essentials',
    ));

    // System notification
    await NotificationService.transactionAdded(
      type: 'expense',
      amount: e.amount,
      category: e.name,
      bankName: bankName,
      accountName: picked.name,
      note: 'from essentials',
      date: today,
    );

    // Mark essential as paid, store which account + which transaction
    final updated = e.copyWith(
      paidMonth: _currentMonth,
      paidAccountId: picked.id,
      paidTransactionId: txId,
    );
    await _db.updateEssential(updated);
    _load();
  }

  // ─── Mark as unpaid ────────────────────────────────────

  Future<void> _handleUnpaid(EssentialModel e) async {
    // If there's no linked transaction (edge case), just uncheck
    if (e.paidTransactionId == null) {
      await _db.updateEssential(e.copyWith(
          clearPaid: true,
          clearPaidAccount: true,
          clearPaidTransaction: true));
      _load();
      return;
    }

    final accountLabel = e.paidAccountId != null
        ? (_accountLabels[e.paidAccountId] ?? 'the account')
        : 'the account';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete the EGP ${e.amount.toStringAsFixed(2)} '
          'expense for "${e.name}" from $accountLabel and restore the balance.\n\n'
          'Are you sure you want to continue?',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Transaction'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Delete the linked transaction (restores account balance)
    final tx = await _db.getTransactionById(e.paidTransactionId!);
    if (tx != null) {
      await _db.deleteTransaction(tx);
    }

    // Clear the essential's paid state
    await _db.updateEssential(e.copyWith(
        clearPaid: true,
        clearPaidAccount: true,
        clearPaidTransaction: true));
    _load();
  }

  void _togglePaid(EssentialModel e) {
    if (e.isPaidThisMonth) {
      _handleUnpaid(e);
    } else {
      _handlePaid(e);
    }
  }

  // ─── Add / Edit dialog ─────────────────────────────────

  void _showAddEditDialog({EssentialModel? existing}) {
    final nameCtrl   = TextEditingController(text: existing?.name ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null ? existing.amount.toStringAsFixed(0) : '');
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Add Essential' : 'Edit Essential',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField(
                    ctrl: nameCtrl, label: 'Name', hint: 'e.g. Mobile Bill'),
                const SizedBox(height: 12),
                _dialogField(
                  ctrl: amountCtrl,
                  label: 'Amount (EGP)',
                  hint: '0.00',
                  prefix: 'EGP ',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                if (existing == null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      'Mobile Bill', 'Internet', 'Electricity', 'Water',
                      'Rent', 'Fuel', 'Barber', 'Gym', 'Insurance',
                    ].map((s) => GestureDetector(
                      onTap: () => nameCtrl.text = s,
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
                    )).toList(),
                  ),
                ],
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
                final name   = nameCtrl.text.trim();
                final amount = double.tryParse(amountCtrl.text.trim());
                if (name.isEmpty) {
                  setD(() => error = 'Name is required.');
                  return;
                }
                if (amount == null || amount <= 0) {
                  setD(() => error = 'Enter a valid amount.');
                  return;
                }
                final model = EssentialModel(
                  id: existing?.id,
                  name: name,
                  amount: amount,
                  paidMonth: existing?.paidMonth,
                  paidAccountId: existing?.paidAccountId,
                  paidTransactionId: existing?.paidTransactionId,
                  createdAt: existing?.createdAt ??
                      DateTime.now().toIso8601String(),
                );
                if (existing == null) {
                  await _db.insertEssential(model);
                } else {
                  await _db.updateEssential(model);
                }
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

  Future<void> _delete(EssentialModel e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Essential'),
        content: Text('Remove "${e.name}" from your essentials list?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteEssential(e.id!);
      _load();
    }
  }

  Future<void> _setSavingsTarget(double value) async {
    await _db.setSetting('savings_target', value.toString());
    setState(() => _savingsTarget = value);
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Essentials',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add Essential',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  _buildBalanceCard(),
                  const SizedBox(height: 16),
                  if (_essentials.isEmpty)
                    _buildEmpty()
                  else ...[
                    _buildEssentialsList(),
                    const SizedBox(height: 12),
                    _buildStatusCard(),
                  ],
                  const SizedBox(height: 16),
                  _buildSavingsCard(),
                ],
              ),
            ),
    );
  }

  // ─── Balance card ──────────────────────────────────────

  Widget _buildBalanceCard() {
    final paid  = _essentials.where((e) => e.isPaidThisMonth).length;
    final total = _essentials.length;
    final pct   = total > 0 ? paid / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 7)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Current Accounts Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_monthLabel,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'EGP ${_fmt(_totalBalance)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (total > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Essentials: $paid of $total paid',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(
                    'EGP ${_fmt(_paidTotal)} / EGP ${_fmt(_essentialsTotal)}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _allPaid ? Colors.greenAccent : Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Essentials list ───────────────────────────────────

  Widget _buildEssentialsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            'ESSENTIALS — $_monthLabel'.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 0.8),
          ),
        ),
        ..._essentials.map((e) => _buildEssentialCard(e)),
      ],
    );
  }

  Widget _buildEssentialCard(EssentialModel e) {
    final paid          = e.isPaidThisMonth;
    final paidFromLabel = (paid && e.paidAccountId != null)
        ? _accountLabels[e.paidAccountId]
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: paid ? AppColors.successFaded : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: paid
              ? AppColors.success.withValues(alpha: 0.35)
              : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _togglePaid(e),
          onLongPress: () => _showEssentialOptions(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Paid toggle circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: paid ? AppColors.success : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          paid ? AppColors.success : AppColors.textHint,
                      width: 2,
                    ),
                  ),
                  child: paid
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(width: 14),
                // Name + "Paid from" label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: paid
                              ? AppColors.success
                              : AppColors.textPrimary,
                          decoration:
                              paid ? TextDecoration.lineThrough : null,
                          decorationColor: AppColors.success,
                        ),
                      ),
                      if (paidFromLabel != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.account_balance_outlined,
                                size: 11, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(
                              'Paid from: $paidFromLabel',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.success),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Amount
                Text(
                  'EGP ${_fmt(e.amount)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: paid
                        ? AppColors.success
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEssentialOptions(EssentialModel e) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            handleBar(),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: AppColors.primary),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddEditDialog(existing: e);
              },
            ),
            ListTile(
              leading: Icon(
                e.isPaidThisMonth
                    ? Icons.remove_done_outlined
                    : Icons.check_circle_outline,
                color: e.isPaidThisMonth
                    ? AppColors.textSecondary
                    : AppColors.success,
              ),
              title: Text(e.isPaidThisMonth
                  ? 'Mark as unpaid'
                  : 'Mark as paid'),
              onTap: () {
                Navigator.pop(ctx);
                _togglePaid(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.error),
              title: const Text('Remove',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(e);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Status card ───────────────────────────────────────

  Widget _buildStatusCard() {
    return _allPaid ? _buildAllDoneCard() : _buildProgressCard();
  }

  Widget _buildAllDoneCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success,
            AppColors.success.withValues(alpha: 0.75)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.success.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text('All Essentials Covered!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white30, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Remaining balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                'EGP ${_fmt(_balanceAfterEssentials)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final unpaidCount = _essentials.where((e) => !e.isPaidThisMonth).length;
    final canCover = _totalBalance >= _essentialsTotal;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: canCover
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.error.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                canCover
                    ? Icons.pending_outlined
                    : Icons.warning_amber_rounded,
                color: canCover ? AppColors.warning : AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '$unpaidCount essential${unpaidCount == 1 ? '' : 's'} remaining',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: canCover ? AppColors.warning : AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _summaryRow('Still to pay', 'EGP ${_fmt(_unpaidTotal)}',
              AppColors.textPrimary),
          const SizedBox(height: 6),
          _summaryRow('Current accounts balance',
              'EGP ${_fmt(_totalBalance)}', AppColors.primary),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('After all essentials',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              Text(
                'EGP ${_fmt(_balanceAfterEssentials)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _balanceAfterEssentials >= 0
                        ? AppColors.success
                        : AppColors.error),
              ),
            ],
          ),
          if (!canCover) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.errorFaded,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 15, color: AppColors.error),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your balance may not fully cover all essentials.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Savings card ──────────────────────────────────────

  Widget _buildSavingsCard() {
    final afterEssentials = _balanceAfterEssentials;
    final freelySpendable = afterEssentials - _savingsTarget;
    final savingsPct = afterEssentials > 0
        ? (_savingsTarget / afterEssentials).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.savings_outlined,
                  color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text('Savings & Investments',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available after essentials',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                Text(
                  'EGP ${_fmt(afterEssentials)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: afterEssentials >= 0
                          ? AppColors.primary
                          : AppColors.error),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Monthly savings target',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3)),
          const SizedBox(height: 8),
          _SavingsTargetField(
              initialValue: _savingsTarget, onChanged: _setSavingsTarget),
          const SizedBox(height: 16),
          if (_savingsTarget > 0 && afterEssentials > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 18,
                child: Row(
                  children: [
                    Flexible(
                      flex: (savingsPct * 100).round().clamp(1, 99),
                      child: Container(
                        color: AppColors.primary,
                        alignment: Alignment.center,
                        child: savingsPct > 0.15
                            ? const Text('Save',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold))
                            : null,
                      ),
                    ),
                    Flexible(
                      flex:
                          ((1 - savingsPct) * 100).round().clamp(1, 99),
                      child: Container(
                        color:
                            AppColors.success.withValues(alpha: 0.25),
                        alignment: Alignment.center,
                        child: (1 - savingsPct) > 0.15
                            ? Text('Spend',
                                style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold))
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          const Divider(height: 1),
          const SizedBox(height: 12),
          _summaryRow('To save / invest', 'EGP ${_fmt(_savingsTarget)}',
              AppColors.primary,
              bold: true),
          const SizedBox(height: 8),
          _summaryRow('Freely spendable', 'EGP ${_fmt(freelySpendable)}',
              freelySpendable >= 0 ? AppColors.success : AppColors.error,
              bold: true),
          if (_savingsTarget > afterEssentials && afterEssentials > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningFaded,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 15, color: AppColors.warning),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your savings target exceeds what\'s available after essentials.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.checklist_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No essentials yet',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            'Add your fixed monthly payments — bills, subscriptions, fuel — and track which ones you\'ve taken care of.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddEditDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add First Essential'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color valueColor,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: valueColor)),
      ],
    );
  }

  Widget _dialogField({
    required TextEditingController ctrl,
    required String label,
    String? hint,
    String? prefix,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);
}

// ─── Inline savings target field ───────────────────────────────────────────

class _SavingsTargetField extends StatefulWidget {
  final double initialValue;
  final ValueChanged<double> onChanged;

  const _SavingsTargetField(
      {required this.initialValue, required this.onChanged});

  @override
  State<_SavingsTargetField> createState() => _SavingsTargetFieldState();
}

class _SavingsTargetFieldState extends State<_SavingsTargetField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.initialValue > 0
          ? widget.initialValue.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final val = double.tryParse(_ctrl.text.trim()) ?? 0;
    widget.onChanged(val);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onEditingComplete: _commit,
      onTapOutside: (_) => _commit(),
      decoration: InputDecoration(
        hintText: '0 — set how much to save each month',
        prefixText: 'EGP ',
        suffixText: '/month',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
