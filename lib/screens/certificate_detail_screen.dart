import 'package:flutter/material.dart';
import '../models/account_model.dart';
import '../models/certificate_model.dart';
import '../db/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';

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
  bool _editing = false;

  final _principalController = TextEditingController();
  final _rateController = TextEditingController();
  DateTime? _openedDate;
  DateTime? _maturityDate;
  int _frequencyMonths = 1;

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

  DateTime _calculateNextInterestDate(
      DateTime openedDate, int frequencyMonths) {
    final today = DateTime.now();
    DateTime next = DateTime(
        openedDate.year, openedDate.month + frequencyMonths, openedDate.day);
    while (!next.isAfter(today)) {
      next = DateTime(
          next.year, next.month + frequencyMonths, next.day);
    }
    return next;
  }

  void _startEdit() {
    final cert = _certificate!;
    _principalController.text = cert.principal.toString();
    _rateController.text = (cert.interestRate * 100).toStringAsFixed(2);
    _openedDate = DateTime.parse(cert.openedDate);
    _maturityDate = DateTime.parse(cert.maturityDate);
    _frequencyMonths = cert.frequencyMonths;
    if (_isElAhly) {
      for (final a in _bankAccounts) {
        if (a.id == cert.depositAccountId) {
          _selectedDepositAccount = a;
          break;
        }
      }
    }
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    setState(() => _editing = false);
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

    final nextInterest =
        _calculateNextInterestDate(_openedDate!, _frequencyMonths);
    final isMatured = nextInterest.isAfter(_maturityDate!);

    final cert = CertificateModel(
      id: _certificate?.id,
      accountId: widget.account.id!,
      depositAccountId: depositAccountId,
      principal: principal,
      interestRate: rate / 100,
      openedDate: _openedDate!.toIso8601String().substring(0, 10),
      maturityDate: _maturityDate!.toIso8601String().substring(0, 10),
      nextInterestDate: nextInterest.toIso8601String().substring(0, 10),
      frequencyMonths: _frequencyMonths,
      isMatured: isMatured,
    );

    if (_certificate == null) {
      await DatabaseHelper.instance.insertCertificate(cert);
      await DatabaseHelper.instance
          .updateAccountBalance(widget.account.id!, principal);
    } else {
      // Preserve any interest that has already accrued into the balance —
      // only shift the balance by how much the principal itself changed.
      final principalDelta = principal - _certificate!.principal;
      await DatabaseHelper.instance.updateCertificate(cert);
      if (principalDelta != 0) {
        final account =
            await DatabaseHelper.instance.getAccountById(widget.account.id!);
        if (account != null) {
          await DatabaseHelper.instance.updateAccountBalance(
              widget.account.id!, account.balance + principalDelta);
        }
      }
    }

    setState(() => _editing = false);
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
        actions: [
          if (!_loading && _certificate != null)
            IconButton(
              icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
              tooltip: _editing ? 'Cancel' : 'Edit certificate',
              onPressed: _editing ? _cancelEdit : _startEdit,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_certificate == null || _editing)
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
              Icons.workspace_premium,
              _editing ? 'Edit Certificate' : 'Certificate Details',
              _editing
                  ? 'Update any field — details recalculate automatically.'
                  : 'Enter the details for this investment certificate.'),
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
          const SizedBox(height: 20),

          const Text(
            'Interest payment frequency:',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _frequencyMonths,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.repeat),
            ),
            borderRadius: BorderRadius.circular(10),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Monthly')),
              DropdownMenuItem(value: 3, child: Text('Every 3 months')),
              DropdownMenuItem(value: 6, child: Text('Every 6 months')),
              DropdownMenuItem(value: 12, child: Text('Yearly')),
            ],
            onChanged: (val) =>
                setState(() => _frequencyMonths = val ?? 1),
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
              label: Text(_editing ? 'Save Changes' : 'Save Certificate'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancelEdit,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
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
                  'EGP ${fmtMoney(monthly)}',
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
                    'EGP ${fmtMoney(cert.principal)}'),
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
                _infoRow(Icons.repeat, 'Interest Frequency',
                    cert.frequencyMonths == 1
                        ? 'Monthly'
                        : 'Every ${cert.frequencyMonths} months'),
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
