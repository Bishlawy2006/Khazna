import 'package:flutter/material.dart';
import '../models/account_model.dart';
import '../models/certificate_model.dart';
import '../db/database_helper.dart';
import '../theme/app_theme.dart';

class CertificateDetailScreen extends StatefulWidget {
  final AccountModel account;
  final String bankName;

  const CertificateDetailScreen({
    super.key,
    required this.account,
    required this.bankName,
  });

  @override
  State<CertificateDetailScreen> createState() =>
      _CertificateDetailScreenState();
}

class _CertificateDetailScreenState extends State<CertificateDetailScreen> {
  CertificateModel? _certificate;
  bool _loading = true;

  final _principalController = TextEditingController();
  final _rateController = TextEditingController();
  DateTime? _openedDate;
  DateTime? _maturityDate;

  List<AccountModel> _bankAccounts = [];
  AccountModel? _selectedDepositAccount;

  bool get _isElAhly =>
      widget.bankName.toLowerCase().contains('ahly') ||
      widget.bankName.toLowerCase().contains('national bank');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _principalController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final cert = await DatabaseHelper.instance
        .getCertificateByAccountId(widget.account.id!);

    if (_isElAhly) {
      final accounts = await DatabaseHelper.instance
          .getAccountsForBank(widget.account.bankId);
      _bankAccounts = accounts.where((a) => a.type != 'certificate').toList();
    }

    setState(() {
      _certificate = cert;
      _loading = false;
    });
  }

  Future<void> _saveCertificate() async {
    final principal = double.tryParse(_principalController.text.trim());
    final rate = double.tryParse(_rateController.text.trim());

    if (principal == null || rate == null) {
      _showError('Enter a valid principal and interest rate.');
      return;
    }
    if (_openedDate == null || _maturityDate == null) {
      _showError('Select both the opened date and maturity date.');
      return;
    }
    if (_isElAhly && _selectedDepositAccount == null) {
      _showError('Select the account that will receive the interest.');
      return;
    }

    final depositAccountId =
        _isElAhly ? _selectedDepositAccount!.id! : widget.account.id!;

    DateTime calculateNextInterestDate(DateTime openedDate) {
      final today = DateTime.now();
      DateTime next = DateTime(
          openedDate.year, openedDate.month + 1, openedDate.day);
      while (!next.isAfter(today)) {
        next = DateTime(next.year, next.month + 1, next.day);
      }
      return next;
    }

    final nextInterest = calculateNextInterestDate(_openedDate!);

    final cert = CertificateModel(
      accountId: widget.account.id!,
      depositAccountId: depositAccountId,
      principal: principal,
      interestRate: rate / 100,
      openedDate: _openedDate!.toIso8601String().substring(0, 10),
      maturityDate: _maturityDate!.toIso8601String().substring(0, 10),
      nextInterestDate: nextInterest.toIso8601String().substring(0, 10),
      frequencyMonths: 1,
    );

    await DatabaseHelper.instance.insertCertificate(cert);
    await DatabaseHelper.instance
        .updateAccountBalance(widget.account.id!, principal);

    await _loadData();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickDate(bool isOpened) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isOpened) {
          _openedDate = picked;
        } else {
          _maturityDate = picked;
        }
      });
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
        title: Text(
          widget.account.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _certificate == null
              ? _buildForm()
              : _buildInfoView(),
    );
  }

  // ─── Form ──────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.workspace_premium, 'Certificate Details',
              'Enter the details for this investment certificate.'),
          const SizedBox(height: 20),

          TextField(
            controller: _principalController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Principal Amount (EGP)',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _rateController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Annual Interest Rate (%)',
              hintText: 'e.g. 19 for 19%',
              prefixIcon: Icon(Icons.percent),
            ),
          ),
          const SizedBox(height: 20),

          // Date pickers
          _dateTile(
            icon: Icons.calendar_today,
            label: _openedDate == null
                ? 'Select Opened Date'
                : 'Opened: ${_openedDate!.toIso8601String().substring(0, 10)}',
            isSet: _openedDate != null,
            onTap: () => _pickDate(true),
          ),
          const SizedBox(height: 10),
          _dateTile(
            icon: Icons.event_available,
            label: _maturityDate == null
                ? 'Select Maturity Date'
                : 'Matures: ${_maturityDate!.toIso8601String().substring(0, 10)}',
            isSet: _maturityDate != null,
            onTap: () => _pickDate(false),
          ),

          // El Ahly: deposit account selector
          if (_isElAhly && _bankAccounts.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Interest deposits into:',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AccountModel>(
              initialValue: _selectedDepositAccount,
              decoration: const InputDecoration(
                hintText: 'Select account',
                prefixIcon: Icon(Icons.account_balance_wallet),
              ),
              borderRadius: BorderRadius.circular(10),
              items: _bankAccounts
                  .map((a) => DropdownMenuItem(
                        value: a,
                        child: Text(a.name),
                      ))
                  .toList(),
              onChanged: (val) =>
                  setState(() => _selectedDepositAccount = val),
            ),
          ],

          // El Mashreq: info box
          if (!_isElAhly) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Interest will compound directly into this certificate\'s balance each month.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saveCertificate,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Certificate'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateTile({
    required IconData icon,
    required String label,
    required bool isSet,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSet
                ? AppColors.primary
                : Colors.grey.shade400,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: isSet
                    ? AppColors.primary
                    : Colors.grey),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSet ? AppColors.primary : Colors.grey,
                fontWeight:
                    isSet ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right,
                size: 18,
                color: isSet
                    ? AppColors.primary
                    : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ─── Info view (certificate already saved) ─────────────

  Widget _buildInfoView() {
    final cert = _certificate!;
    final monthly = cert.monthlyInterest;
    final ratePercent =
        (cert.interestRate * 100).toStringAsFixed(0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Monthly interest highlight card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
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
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.workspace_premium,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '$ratePercent% / year  •  ${cert.isMatured ? 'Matured' : 'Active'}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cert.isMatured
                            ? Colors.red.withValues(alpha: 0.25)
                            : Colors.green.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cert.isMatured ? 'MATURED' : 'ACTIVE',
                        style: TextStyle(
                          color: cert.isMatured
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Monthly Interest',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'EGP ${monthly.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Details card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 8),
            child: Column(
              children: [
                _infoRow(Icons.account_balance_wallet, 'Principal',
                    'EGP ${cert.principal.toStringAsFixed(2)}'),
                _divider(),
                _infoRow(Icons.percent, 'Annual Rate',
                    '$ratePercent%'),
                _divider(),
                _infoRow(Icons.date_range, 'Opened Date',
                    cert.openedDate),
                _divider(),
                _infoRow(Icons.event_available, 'Maturity Date',
                    cert.maturityDate),
                _divider(),
                _infoRow(
                  Icons.notifications_outlined,
                  'Next Interest Due',
                  cert.isMatured ? '—' : cert.nextInterestDate,
                  valueColor: cert.isMatured
                      ? Colors.grey
                      : AppColors.primary,
                ),
                _divider(),
                _infoRow(
                  _isElAhly
                      ? Icons.account_balance
                      : Icons.trending_up,
                  'Interest Goes To',
                  _isElAhly
                      ? 'Linked Current Account'
                      : 'This Certificate (compounds)',
                  valueColor: AppColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
      IconData icon, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon,
                  size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style:
              const TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 14, color: Colors.black54),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 32);
}
