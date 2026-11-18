import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/bank_model.dart';
import '../models/account_model.dart';
import '../models/activity_log_model.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'bank_detail_screen.dart';
import 'cash_screen.dart';
import 'all_transactions_screen.dart';
import 'activity_screen.dart';
import 'analysis_screen.dart';
import 'budget_screen.dart';
import 'essentials_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<BankModel> _banks = [];
  Map<int, List<AccountModel>> _accountsByBank = {};
  bool _isLoading = true;
  int _unreadActivityCount = 0;
  String _username = '';

  @override
  void initState() {
    super.initState();
    // Reaching Home means the user fully signed in (password + 2FA, or
    // the biometric unlock): remember it so a force-close does not log out.
    SessionService.markSignedIn();
    _loadData();
  }

  Future<void> _loadData() async {
    final allBanks = await DatabaseHelper.instance.getAllBanks();
    final Map<int, List<AccountModel>> accountsByBank = {};
    final filteredBanks = <BankModel>[];

    for (final bank in allBanks) {
      if (bank.name == 'Cash') continue; // Cash lives in its own screen
      final accounts =
          await DatabaseHelper.instance.getAccountsForBank(bank.id!);
      accountsByBank[bank.id!] = accounts;
      filteredBanks.add(bank);
    }

    final unread = await DatabaseHelper.instance.getUnreadActivityCount();
    final user = await DatabaseHelper.instance.getUser();

    setState(() {
      _banks = filteredBanks;
      _accountsByBank = accountsByBank;
      _isLoading = false;
      _unreadActivityCount = unread;
      _username = user?.username ?? '';
    });
  }

  double _bankTotal(int bankId) =>
      (_accountsByBank[bankId] ?? []).fold(0.0, (s, a) => s + a.balance);

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Khazna',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  _buildWelcomeCard(),
                  _buildSectionHeader('Your Banks'),
                  if (_banks.isEmpty)
                    _buildEmptyState()
                  else
                    ..._banks.map((b) => _buildBankCard(b)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBankDialog(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add Bank',
        child: const Icon(Icons.add),
      ),
    );
  }

  // ─── Welcome card ──────────────────────────────────────

  Widget _buildWelcomeCard() {
    final now = DateTime.now();
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr =
        '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome back,',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '$_username!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  color: Colors.white38, size: 13),
              const SizedBox(width: 6),
              Text(
                dateStr,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Section header ────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ─── Empty state ───────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.account_balance_outlined,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No banks yet.',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap + to add your first bank.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ─── Bank card ─────────────────────────────────────────

  Widget _buildBankCard(BankModel bank) {
    final accounts = _accountsByBank[bank.id!] ?? [];
    final total = _bankTotal(bank.id!);
    final isPositive = total >= 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(context, slideRoute(BankDetailScreen(bank: bank)));
            _loadData();
          },
          onLongPress: () => _showBankOptions(bank),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Bank icon — card image if matched, else default
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _cardImageForBank(bank.name) != null
                        ? Image.asset(
                            _cardImageForBank(bank.name)!,
                            fit: BoxFit.cover,
                          )
                        : const Icon(
                            Icons.account_balance,
                            color: AppColors.primary,
                            size: 22,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Bank name + account count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bank.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${accounts.length} account${accounts.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                // Balance + edit button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'EGP ${total.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isPositive
                            ? AppColors.success
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _showQuickEditSheet(bank),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_outlined,
                                size: 12, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
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
                  _drawerItem(Icons.home_outlined, 'Home', () {
                    Navigator.pop(context);
                  }),
                  _drawerItem(Icons.account_balance_outlined, 'Banks', () {
                    Navigator.pop(context);
                  }),
                  _drawerItem(Icons.payments_outlined, 'Cash', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const CashScreen()))
                        .then((_) => _loadData());
                  }),
                  _drawerItem(Icons.receipt_long_outlined, 'Transactions', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context, slideRoute(const AllTransactionsScreen()));
                  }),
                  _drawerItemWithBadge(
                    Icons.notifications_outlined,
                    'Activity',
                    _unreadActivityCount,
                    () {
                      Navigator.pop(context);
                      Navigator.push(context, slideRoute(const ActivityScreen()))
                          .then((_) => _loadData());
                    },
                  ),
                  _drawerItem(Icons.bar_chart_rounded, 'Analysis', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const AnalysisScreen()));
                  }),
                  _drawerItem(Icons.checklist_outlined, 'Essentials', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const EssentialsScreen()));
                  }),
                  _drawerItem(Icons.savings_outlined, 'Budgets', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const BudgetScreen()));
                  }),
                  const Divider(indent: 16, endIndent: 16, height: 20),
                  _drawerItem(Icons.settings_outlined, 'Settings', () {
                    Navigator.pop(context);
                    Navigator.push(context, slideRoute(const SettingsScreen()));
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

  Widget _drawerItemWithBadge(
      IconData icon, String label, int badgeCount, VoidCallback onTap) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          if (badgeCount > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
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
