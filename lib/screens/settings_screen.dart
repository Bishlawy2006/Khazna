import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'setup_2fa_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await DatabaseHelper.instance.getUser();
    if (mounted) setState(() { _user = user; _isLoading = false; });
  }

  // ─── Security actions ──────────────────────────────────

  void _showChangePasswordDialog() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureOld = true, obscureNew = true, obscureConfirm = true;
    String? error;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change Password',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(
                  ctrl: oldCtrl,
                  label: 'Current Password',
                  obscure: obscureOld,
                  toggle: () =>
                      setDialogState(() => obscureOld = !obscureOld),
                ),
                const SizedBox(height: 12),
                _dialogField(
                  ctrl: newCtrl,
                  label: 'New Password',
                  obscure: obscureNew,
                  toggle: () =>
                      setDialogState(() => obscureNew = !obscureNew),
                ),
                const SizedBox(height: 12),
                _dialogField(
                  ctrl: confirmCtrl,
                  label: 'Confirm New Password',
                  obscure: obscureConfirm,
                  toggle: () =>
                      setDialogState(() => obscureConfirm = !obscureConfirm),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  _inlineError(error!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final old = oldCtrl.text;
                      final newPw = newCtrl.text;
                      final confirm = confirmCtrl.text;

                      if (newPw != confirm) {
                        setDialogState(
                            () => error = 'Passwords do not match.');
                        return;
                      }
                      if (newPw.length < 8) {
                        setDialogState(
                            () => error = 'At least 8 characters required.');
                        return;
                      }
                      if (!RegExp(r'[A-Z]').hasMatch(newPw)) {
                        setDialogState(() =>
                            error = 'Include at least one uppercase letter.');
                        return;
                      }
                      if (!RegExp(r'[0-9]').hasMatch(newPw)) {
                        setDialogState(
                            () => error = 'Include at least one number.');
                        return;
                      }

                      setDialogState(() { loading = true; error = null; });
                      final valid = await AuthService.verifyPassword(
                          old, _user!.salt, _user!.passwordHash);

                      if (!valid) {
                        setDialogState(() {
                          loading = false;
                          error = 'Current password is incorrect.';
                        });
                        return;
                      }

                      final salt = AuthService.generateSalt();
                      final hash = await AuthService.hashPassword(newPw, salt);
                      final updated =
                          _user!.copyWith(passwordHash: hash, salt: salt);
                      await DatabaseHelper.instance.updateUser(updated);

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      setState(() => _user = updated);
                      _showSnack('Password changed successfully.');
                    },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigate2FASetup() async {
    if (_user == null) return;
    final updated = await Navigator.push<UserModel>(
      context,
      slideRoute(SetupTwoFactorScreen(user: _user!)),
    );
    if (updated != null) {
      setState(() => _user = updated);
      _showSnack('Two-factor authentication enabled.');
    }
  }

  Future<void> _disable2FA() async {
    if (_user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable 2FA'),
        content: const Text(
            'This will remove your extra layer of security. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = _user!.copyWith(
      twoFactorEnabled: false,
      clearTwoFactorMethod: true,
      clearTotpSecret: true,
    );
    await DatabaseHelper.instance.updateUser(updated);
    setState(() => _user = updated);
    _showSnack('Two-factor authentication disabled.');
  }

  // ─── Data actions ──────────────────────────────────────

  Future<void> _exportVault() async {
    if (_user == null) return;

    final pwCtrl = TextEditingController();
    bool obscure = true;
    String? error;
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Backup Vault',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your vault will be encrypted with your password. Save the file somewhere safe (Google Drive, email, USB).',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                _dialogField(
                  ctrl: pwCtrl,
                  label: 'Your Password',
                  obscure: obscure,
                  toggle: () => setS(() => obscure = !obscure),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  _inlineError(error!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      setS(() { loading = true; error = null; });
                      final valid = await AuthService.verifyPassword(
                          pwCtrl.text, _user!.salt, _user!.passwordHash);
                      if (!valid) {
                        setS(() { loading = false; error = 'Incorrect password.'; });
                        return;
                      }
                      try {
                        final data = await DatabaseHelper.instance.exportAllData();
                        final path = await BackupService.exportVault(data, pwCtrl.text);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (path != null) {
                          _showSnack('Backup saved to:\n$path');
                        } else {
                          _showSnack('Backup ready — choose where to save it.');
                        }
                      } catch (e) {
                        setS(() { loading = false; error = 'Export failed: $e'; });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportTransactions() async {
    setState(() => _isLoading = true);
    try {
      final txs = await DatabaseHelper.instance.getAllTransactions();
      if (txs.isEmpty) {
        _showSnack('No transactions to export.');
        setState(() => _isLoading = false);
        return;
      }

      // Build accountId → name map
      final allBanks = await DatabaseHelper.instance.getAllBanks();
      final Map<int, String> accountNames = {};
      for (final bank in allBanks) {
        final accounts =
            await DatabaseHelper.instance.getAccountsForBank(bank.id!);
        for (final acc in accounts) {
          accountNames[acc.id!] = '${bank.name} – ${acc.name}';
        }
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory(p.join(docsDir.path, 'Khazna'));
      await exportDir.create(recursive: true);

      final now = DateTime.now();
      final filename =
          'transactions_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
      final file = File(p.join(exportDir.path, filename));

      final csv = StringBuffer();
      csv.writeln('Date,Account,Type,Category,Amount (EGP),Note');
      for (final tx in txs) {
        final account = accountNames[tx.accountId] ?? 'Unknown';
        final note = (tx.note ?? '').replaceAll('"', '""');
        final category = tx.category.replaceAll('"', '""');
        csv.writeln(
            '"${tx.date}","$account","${tx.type}","$category","${tx.amount.toStringAsFixed(2)}","$note"');
      }

      await file.writeAsString(csv.toString());

      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Exported to Documents\\Khazna\\$filename');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Export failed: $e');
      }
    }
  }

  Future<void> _clearActivityLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Activity History'),
        content: const Text(
            'This will permanently delete all activity log entries. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseHelper.instance.clearActivityLogs();
    _showSnack('Activity history cleared.');
  }

  void _signOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('You will need your password to sign in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushAndRemoveUntil(
                  context,
                  slideRoute(const LoginScreen()),
                  (r) => false);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _profileCard(),
                const SizedBox(height: 24),

                _sectionLabel('Security'),
                const SizedBox(height: 8),
                _settingsGroup([
                  _tile(
                    icon: Icons.lock_reset_outlined,
                    iconColor: AppColors.primary,
                    label: 'Change Password',
                    onTap: _showChangePasswordDialog,
                  ),
                  _twoFactorTile(),
                ]),

                const SizedBox(height: 24),

                _sectionLabel('Data'),
                const SizedBox(height: 8),
                _settingsGroup([
                  _tile(
                    icon: Icons.shield_outlined,
                    iconColor: AppColors.primary,
                    label: 'Backup Vault',
                    subtitle: 'Export encrypted backup to transfer to another device',
                    onTap: _exportVault,
                  ),
                  _tile(
                    icon: Icons.download_outlined,
                    iconColor: Colors.teal,
                    label: 'Export Transactions',
                    subtitle: 'Save all transactions as CSV to Documents',
                    onTap: _exportTransactions,
                  ),
                  _tile(
                    icon: Icons.history_outlined,
                    iconColor: Colors.orange,
                    label: 'Clear Activity Logs',
                    subtitle: 'Delete all activity history permanently',
                    onTap: _clearActivityLogs,
                  ),
                ]),

                const SizedBox(height: 24),

                _sectionLabel('App'),
                const SizedBox(height: 8),
                _settingsGroup([
                  _tile(
                    icon: Icons.payments_outlined,
                    iconColor: AppColors.primary,
                    label: 'Currency',
                    trailing: const Text('EGP',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),

                const SizedBox(height: 24),

                _sectionLabel('About'),
                const SizedBox(height: 8),
                _settingsGroup([
                  _tile(
                    icon: Icons.info_outline,
                    iconColor: Colors.grey,
                    label: 'Version',
                    trailing: const Text('1.0.0',
                        style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
                  _tile(
                    icon: Icons.shield_outlined,
                    iconColor: Colors.grey,
                    label: 'Privacy',
                    subtitle: 'All data stored locally on your device',
                  ),
                ]),

                const SizedBox(height: 24),

                // Sign Out button
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.errorFaded,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.logout,
                            color: AppColors.error, size: 18),
                      ),
                      title: const Text('Sign Out',
                          style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600)),
                      onTap: _signOut,
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ─── Profile card ──────────────────────────────────────

  Widget _profileCard() {
    final has2FA = _user?.twoFactorEnabled ?? false;
    final method = _user?.twoFactorMethod;
    return Container(
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
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _user?.username ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      has2FA ? Icons.verified_user : Icons.shield_outlined,
                      size: 13,
                      color:
                          has2FA ? Colors.greenAccent : Colors.white54,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      has2FA
                          ? '2FA: ${method == 'totp' ? 'Authenticator App' : 'Email OTP'}'
                          : '2FA: Not enabled',
                      style: TextStyle(
                          color:
                              has2FA ? Colors.greenAccent : Colors.white54,
                          fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2FA tile (dynamic) ────────────────────────────────

  Widget _twoFactorTile() {
    final enabled = _user?.twoFactorEnabled ?? false;
    return _tile(
      icon: Icons.security,
      iconColor: enabled ? AppColors.success : AppColors.textSecondary,
      label: 'Two-Factor Authentication',
      subtitle: enabled
          ? 'Enabled · ${_user!.twoFactorMethod == 'totp' ? 'Authenticator App' : 'Email OTP'}'
          : 'Not enabled — tap to set up',
      trailing: Switch(
        value: enabled,
        activeThumbColor: AppColors.success,
        onChanged: (_) =>
            enabled ? _disable2FA() : _navigate2FASetup(),
      ),
      onTap: enabled ? _disable2FA : _navigate2FASetup,
    );
  }

  // ─── Widget helpers ────────────────────────────────────

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1.0),
      ),
    );
  }

  Widget _settingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, indent: 52),
          ],
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool locked = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (locked)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Soon',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600)),
              )
            else if (trailing != null)
              trailing
            else if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  Widget _dialogField({
    required TextEditingController ctrl,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: Colors.grey),
          onPressed: toggle,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _inlineError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.errorFaded,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error))),
        ],
      ),
    );
  }
}
