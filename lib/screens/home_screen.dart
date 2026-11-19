import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/bank_model.dart';
import '../models/account_model.dart';
import '../models/activity_log_model.dart';
import '../models/transaction_model.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'bank_detail_screen.dart';
import 'cash_screen.dart';
import 'budget_screen.dart';
import 'essentials_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Asks the MainShell to switch tab (0 Home, 1 Transactions, 2 Activity,
  /// 3 Analysis, 4 Settings). Pages are reached from the bottom bar only.
  final ValueChanged<int>? onSwitchTab;

  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<BankModel> _banks = [];
  Map<int, List<AccountModel>> _accountsByBank = {};
  bool _isLoading = true;
  int _unreadActivityCount = 0;
  String _username = '';

  // Dashboard figures, all derived from existing tables (no schema change).
  double _totalBalance = 0;
  double _cashBalance = 0;
  double _monthIncome = 0;
  double _monthSpent = 0;
  List<TransactionModel> _recent = [];
  Map<int, String> _bankNameByAccount = {};

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    // Reaching Home means the user fully signed in (password + 2FA, or
    // the biometric unlock): remember it so a force-close does not log out.
    SessionService.markSignedIn();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper.instance;
    final allBanks = await db.getAllBanks();
    final Map<int, List<AccountModel>> accountsByBank = {};
    final Map<int, String> bankNameByAccount = {};
    final filteredBanks = <BankModel>[];
    double total = 0;
    double cash = 0;

    for (final bank in allBanks) {
      final accounts = await db.getAccountsForBank(bank.id!);
      final isCash = bank.name == 'Cash';
      for (final a in accounts) {
        total += a.balance;
        if (isCash) cash += a.balance;
        if (a.id != null) bankNameByAccount[a.id!] = bank.name;
      }
      if (isCash) continue; // Cash lives in its own screen
      accountsByBank[bank.id!] = accounts;
      filteredBanks.add(bank);
    }

    // Newest first; id breaks ties between transactions on the same day.
    final txs = await db.getAllTransactions();
    txs.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
    });

    final now = DateTime.now();
    final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    double income = 0;
    double spent = 0;
    for (final t in txs) {
      if (!t.date.startsWith(monthPrefix)) continue;
      if (t.type == 'income') {
        income += t.amount;
      } else {
        spent += t.amount;
      }
    }

    final unread = await db.getUnreadActivityCount();
    final user = await db.getUser();

    if (!mounted) return;
    setState(() {
      _banks = filteredBanks;
      _accountsByBank = accountsByBank;
      _bankNameByAccount = bankNameByAccount;
      _totalBalance = total;
      _cashBalance = cash;
      _monthIncome = income;
      _monthSpent = spent;
      _recent = txs.take(3).toList();
      _isLoading = false;
      _unreadActivityCount = unread;
      _username = user?.username ?? '';
    });
  }

  double _bankTotal(int bankId) =>
      (_accountsByBank[bankId] ?? []).fold(0.0, (s, a) => s + a.balance);

  // ─── Formatting ────────────────────────────────────────

  /// 12345.5 -> "12,345.50" (no intl dependency needed).
  String _fmt(double v, {int decimals = 2}) {
    final parts = v.abs().toStringAsFixed(decimals).split('.');
    final whole = parts[0].replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final sign = v < 0 ? '-' : '';
    return decimals > 0 ? '$sign$whole.${parts[1]}' : '$sign$whole';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// "Today", "Yesterday" or "12 Nov" from a stored yyyy-MM-dd date.
  String _dateLabel(String raw) {
    final d = DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    if (d == null) return raw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${d.day} ${_months[d.month - 1]}';
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.surface,
      drawer: _buildDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.only(top: 12, bottom: 24),
                  children: [
                    _pad(_buildHeader()),
                    const SizedBox(height: 16),
                    _pad(_buildBalanceCard()),
                    const SizedBox(height: 20),
                    _pad(_buildQuickActions()),
                    const SizedBox(height: 24),
                    _buildBanksSection(),
                    const SizedBox(height: 24),
                    _pad(_buildRecentSection()),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _pad(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  // ─── Header ────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        _roundIconButton(
          Icons.menu_rounded,
          'Menu',
          () => _scaffoldKey.currentState?.openDrawer(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              Text(
                _username.isEmpty ? 'Welcome' : _username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        _roundIconButton(
          Icons.notifications_none_rounded,
          'Activity',
          () => widget.onSwitchTab?.call(2),
          badge: _unreadActivityCount,
        ),
      ],
    );
  }

  Widget _roundIconButton(IconData icon, String tooltip, VoidCallback onTap,
      {int badge = 0}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.divider)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 22, color: AppColors.textPrimary),
                if (badge > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Balance card ──────────────────────────────────────

  Widget _buildBalanceCard() {
    final net = _monthIncome - _monthSpent;
    final netLabel =
        '${net >= 0 ? '+' : '-'}${_fmt(net.abs(), decimals: 0)} this month';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total balance',
                  style: TextStyle(color: Color(0xFFC5CAE9), fontSize: 13),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  netLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: net >= 0 ? AppColors.primary : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'EGP ',
                  style: TextStyle(
                    color: Color(0xFFC5CAE9),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _fmt(_totalBalance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 14),
          Row(
            children: [
              _heroStat('Income', _fmt(_monthIncome, decimals: 0)),
              _heroStat('Spent', _fmt(_monthSpent, decimals: 0)),
              _heroStat('Cash', _fmt(_cashBalance, decimals: 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFFC5CAE9), fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick actions ─────────────────────────────────────

  Widget _buildQuickActions() {
    return Row(
      children: [
        _quickAction(Icons.add_rounded, 'Add bank',
            () => _showAddBankDialog(context)),
        _quickAction(
          Icons.payments_outlined,
          'Cash',
          () => Navigator.push(context, slideRoute(const CashScreen()))
              .then((_) => _loadData()),
        ),
        _quickAction(
          Icons.savings_outlined,
          'Budgets',
          () => Navigator.push(context, slideRoute(const BudgetScreen())),
        ),
        _quickAction(
          Icons.bar_chart_rounded,
          'Analysis',
          () => widget.onSwitchTab?.call(3),
        ),
      ],
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Icon(icon, size: 22, color: AppColors.primary),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Section header ────────────────────────────────────

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text(
              'See all',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  // ─── Banks (horizontal cards) ──────────────────────────

  Widget _buildBanksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pad(_buildSectionHeader('Your banks')),
        const SizedBox(height: 6),
        if (_banks.isEmpty)
          _pad(_buildEmptyState())
        else
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _banks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _buildBankCard(_banks[i]),
            ),
          ),
      ],
    );
  }

  // ─── Empty state ───────────────────────────────────────

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: [
          Icon(Icons.account_balance_outlined,
              size: 44, color: AppColors.textHint),
          SizedBox(height: 10),
          Text(
            'No banks yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Use "Add bank" above to get started.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ─── Bank card ─────────────────────────────────────────

  Widget _buildBankCard(BankModel bank) {
    final accounts = _accountsByBank[bank.id!] ?? [];
    final total = _bankTotal(bank.id!);
    final image = _cardImageForBank(bank.name);

    return SizedBox(
      width: 164,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.push(
                context, slideRoute(BankDetailScreen(bank: bank)));
            _loadData();
          },
          onLongPress: () => _showBankOptions(bank),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 38,
                        height: 26,
                        child: image != null
                            ? Image.asset(image, fit: BoxFit.cover)
                            : const ColoredBox(
                                color: AppColors.primaryFaded,
                                child: Icon(Icons.account_balance,
                                    size: 16, color: AppColors.primary),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bank.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${accounts.length} account${accounts.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'EGP ${_fmt(total)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: total >= 0
                              ? AppColors.textPrimary
                              : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Recent activity ───────────────────────────────────

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Recent activity',
          onSeeAll: () => widget.onSwitchTab?.call(1),
        ),
        if (_recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No transactions yet.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          ..._recent.map(_buildTxRow),
      ],
    );
  }

  Widget _buildTxRow(TransactionModel tx) {
    final isIncome = tx.type == 'income';
    final note = tx.note?.trim() ?? '';
    final title = note.isNotEmpty ? note : tx.category;
    final bank = _bankNameByAccount[tx.accountId] ?? '';
    final subtitle = [
      if (bank.isNotEmpty) bank,
      tx.time == null ? _dateLabel(tx.date) : '${_dateLabel(tx.date)} ${tx.time}',
      if (tx.source == 'auto') 'Auto',
    ].join(' · ');

    final IconData icon;
    if (isIncome) {
      icon = Icons.south_west_rounded;
    } else if (tx.category == 'Card Payment') {
      icon = Icons.credit_card_rounded;
    } else if (tx.category == 'Transfer') {
      icon = Icons.north_east_rounded;
    } else {
      icon = Icons.receipt_long_outlined;
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isIncome
                  ? AppColors.successFaded
                  : AppColors.primaryFaded,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon,
                size: 20,
                color: isIncome ? AppColors.success : AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIncome ? '+' : '-'}${_fmt(tx.amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isIncome ? AppColors.success : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick balance edit bottom sheet ──────────────────

  void _showQuickEditSheet(BankModel bank) {
    final accounts = _accountsByBank[bank.id!] ?? [];
    final controllers = <int, TextEditingController>{
      for (final a in accounts)
        a.id!: TextEditingController(text: a.balance.toStringAsFixed(2))
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Edit Balances',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      bank.name,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Update any account balance directly.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ...accounts.map((account) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            _iconForType(account.type),
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                              Text(
                                account.type.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 135,
                          child: TextField(
                            controller: controllers[account.id!],
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            decoration: InputDecoration(
                              prefixText: 'EGP ',
                              prefixStyle: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.normal,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () async {
                    final db = DatabaseHelper.instance;
                    for (final account in accounts) {
                      final val = double.tryParse(
                          controllers[account.id!]!.text.trim());
                      if (val != null && val != account.balance) {
                        await db.updateAccountBalance(account.id!, val);
                        await db.logActivity(ActivityLogModel.balanceUpdated(
                          bankName: bank.name,
                          accountName: account.name,
                          oldBalance: account.balance,
                          newBalance: val,
                        ));
                        await NotificationService.balanceUpdated(
                          bankName: bank.name,
                          accountName: account.name,
                          oldBalance: account.balance,
                          newBalance: val,
                        );
                      }
                    }
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    _loadData();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Changes',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Drawer ────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 14),
                Text(
                  _username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Personal Finance',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          // Nav items — scrollable so small windows never overflow
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _drawerItem(Icons.payments_outlined, 'Cash', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const CashScreen()))
                        .then((_) => _loadData());
                  }),
                  _drawerItem(Icons.checklist_outlined, 'Essentials', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const EssentialsScreen()));
                  }),
                  _drawerItem(Icons.savings_outlined, 'Budgets', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const BudgetScreen()));
                  }),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Khazna v1.0',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      horizontalTitleGap: 6,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }

  // ─── Helpers ───────────────────────────────────────────

  String? _cardImageForBank(String bankName) {
    final lower = bankName.toLowerCase();
    if (lower.contains('ahly') ||
        lower.contains('national bank') ||
        lower.contains('nbe')) {
      return 'assets/images/cards/nbe_card.png';
    } else if (lower.contains('cib')) {
      return 'assets/images/cards/cib_card.png';
    } else if (lower.contains('telda')) {
      return 'assets/images/cards/telda_card.png';
    } else if (lower.contains('mashreq')) {
      return 'assets/images/cards/elmashreq_card.png';
    }
    return null;
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'savings':
        return Icons.savings;
      case 'certificate':
        return Icons.workspace_premium;
      case 'cash':
        return Icons.payments;
      default:
        return Icons.account_balance_wallet;
    }
  }

  // ─── Bank options (long press) ─────────────────────────

  void _showBankOptions(BankModel bank) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              bank.name,
              style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose an action',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _optionTile(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Edit Balances',
              color: AppColors.primary,
              onTap: () {
                Navigator.pop(ctx);
                _showQuickEditSheet(bank);
              },
            ),
            const SizedBox(height: 8),
            _optionTile(
              icon: Icons.edit_outlined,
              label: 'Rename Bank',
              color: AppColors.primary,
              onTap: () {
                Navigator.pop(ctx);
                _showRenameBankDialog(bank);
              },
            ),
            const SizedBox(height: 8),
            _optionTile(
              icon: Icons.delete_outline,
              label: 'Delete Bank',
              subtitle: 'Removes all accounts and transactions',
              color: Colors.red,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteBank(bank);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameBankDialog(BankModel bank) {
    final ctrl = TextEditingController(text: bank.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Rename Bank'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Bank Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty || name == bank.name) {
                Navigator.pop(ctx);
                return;
              }
              await DatabaseHelper.instance
                  .updateBankName(bank.id!, name);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteBank(BankModel bank) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Bank'),
        content: Text(
            'Delete "${bank.name}" and all its accounts and transactions? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deleteBank(bank.id!);
      _loadData();
    }
  }

  // ─── Add bank dialog ───────────────────────────────────

  void _showAddBankDialog(BuildContext context) {
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Add Bank'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Bank Name',
            hintText: 'e.g. El Ahly, CIB, Telda',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await DatabaseHelper.instance
                  .insertBank(BankModel(name: name));
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
