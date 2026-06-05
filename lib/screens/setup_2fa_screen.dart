import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../db/database_helper.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';
import '../theme/app_theme.dart';

enum _Step { chooseMethod, configureEmail, enterTestCode, configureTOTP }

// SMTP presets — hidden from user for preset providers
const _presets = {
  'gmail':   {'host': 'smtp.gmail.com',       'port': 587},
  'outlook': {'host': 'smtp.office365.com',   'port': 587},
};

class SetupTwoFactorScreen extends StatefulWidget {
  final UserModel user;
  const SetupTwoFactorScreen({super.key, required this.user});

  @override
  State<SetupTwoFactorScreen> createState() => _SetupTwoFactorScreenState();
}

class _SetupTwoFactorScreenState extends State<SetupTwoFactorScreen> {
  _Step _step = _Step.chooseMethod;
  bool _isLoading = false;
  String? _errorMessage;

  // Email
  String _provider = 'gmail';
  final _emailCtrl      = TextEditingController(); // sender email
  final _appPassCtrl    = TextEditingController(); // app password
  final _recipientCtrl  = TextEditingController(); // where to receive codes
  final _customHostCtrl = TextEditingController();
  final _customPortCtrl = TextEditingController(text: '587');
  bool _obscurePass = true;

  // Test code
  String? _testOtpHash;
  final _testCodeCtrl = TextEditingController();

  // TOTP
  late String _totpSecret;
  final _totpCodeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _totpSecret = AuthService.generateTotpSecret();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _appPassCtrl.dispose();
    _recipientCtrl.dispose();
    _customHostCtrl.dispose();
    _customPortCtrl.dispose();
    _testCodeCtrl.dispose();
    _totpCodeCtrl.dispose();
    super.dispose();
  }

  String get _smtpHost =>
      _provider == 'custom' ? _customHostCtrl.text.trim() : _presets[_provider]!['host'] as String;

  int get _smtpPort =>
      _provider == 'custom' ? (int.tryParse(_customPortCtrl.text.trim()) ?? 587) : _presets[_provider]!['port'] as int;

  // ─── Email flow ────────────────────────────────────────

  Future<void> _sendTestCode() async {
    final email     = _emailCtrl.text.trim();
    final password  = _appPassCtrl.text;
    final recipient = _recipientCtrl.text.trim().isEmpty ? email : _recipientCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in your email and app password.');
      return;
    }
    if (_provider == 'custom' && _customHostCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter the SMTP host.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    final testOtp = AuthService.generateOtp();
    _testOtpHash = AuthService.hashOtp(testOtp);

    final sent = await EmailService.sendOtp(
      smtpHost: _smtpHost,
      smtpPort: _smtpPort,
      smtpEmail: email,
      smtpPassword: password,
      recipient: recipient,
      otpCode: testOtp,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (sent) {
        _step = _Step.enterTestCode;
        _testCodeCtrl.clear();
        _errorMessage = null;
      } else {
        _errorMessage =
            'Failed to send. Check your email and app password.\n\n'
            'For Gmail: make sure you used an App Password (not your regular password). '
            'Go to myaccount.google.com → Security → App passwords to generate one.';
      }
    });
  }

  Future<void> _verifyAndEnable() async {
    final entered = _testCodeCtrl.text.trim();
    if (entered.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your email.');
      return;
    }
    if (_testOtpHash == null || !AuthService.verifyOtp(entered, _testOtpHash!)) {
      setState(() => _errorMessage = 'Incorrect code. Try sending again.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    final recipient = _recipientCtrl.text.trim().isEmpty
        ? _emailCtrl.text.trim()
        : _recipientCtrl.text.trim();

    final updated = widget.user.copyWith(
      twoFactorEnabled: true,
      twoFactorMethod: 'email',
      smtpHost: _smtpHost,
      smtpPort: _smtpPort,
      smtpEmail: _emailCtrl.text.trim(),
      smtpPassword: _appPassCtrl.text,
      smtpRecipient: recipient,
    );

    await DatabaseHelper.instance.updateUser(updated);
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pop(context, updated);
  }

  // ─── TOTP flow ─────────────────────────────────────────

  Future<void> _verifyTotpAndEnable() async {
    final code = _totpCodeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your app.');
      return;
    }
    if (!AuthService.verifyTotpCode(_totpSecret, code)) {
      setState(() => _errorMessage = 'Incorrect code. Make sure the clock on your phone is correct.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    final updated = widget.user.copyWith(
      twoFactorEnabled: true,
      twoFactorMethod: 'totp',
      totpSecret: _totpSecret,
    );

    await DatabaseHelper.instance.updateUser(updated);
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pop(context, updated);
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Set Up 2FA', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.chooseMethod:    return _buildChooseMethod();
      case _Step.configureEmail:  return _buildConfigureEmail();
      case _Step.enterTestCode:   return _buildEnterTestCode();
      case _Step.configureTOTP:   return _buildConfigureTOTP();
    }
  }

  // ─── Step 1: Choose ────────────────────────────────────

  Widget _buildChooseMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Text('Choose your 2FA method',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        const Text(
          'Every time you sign in, you will be asked for a second code in addition to your password.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 28),
        _methodCard(
          icon: Icons.email_outlined,
          title: 'Email Code',
          subtitle: 'Khazna sends a 6-digit code to your email each login. Works with Gmail, Outlook, or any email.',
          onTap: () => setState(() { _step = _Step.configureEmail; _errorMessage = null; }),
        ),
        const SizedBox(height: 14),
        _methodCard(
          icon: Icons.security,
          title: 'Authenticator App',
          subtitle: 'Use Google Authenticator, Authy, or Microsoft Authenticator. Works offline, no email needed.',
          onTap: () => setState(() { _step = _Step.configureTOTP; _errorMessage = null; }),
        ),
      ],
    );
  }

  Widget _methodCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: AppColors.primaryFaded, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Configure email ───────────────────────────

  Widget _buildConfigureEmail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backBtn(() => setState(() { _step = _Step.chooseMethod; _errorMessage = null; })),
        const SizedBox(height: 20),
        const Text('Email Code Setup',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 20),

        // Provider tabs
        _providerTabs(),
        const SizedBox(height: 20),

        // Instructions for preset providers
        if (_provider != 'custom') _providerInstructions(),
        if (_provider != 'custom') const SizedBox(height: 20),

        // Fields
        _field('Your Email Address', _emailCtrl, keyboardType: TextInputType.emailAddress,
            hint: _provider == 'gmail' ? 'you@gmail.com' : _provider == 'outlook' ? 'you@outlook.com' : 'you@example.com'),
        const SizedBox(height: 14),
        _field(
          _provider == 'gmail' ? 'Gmail App Password' : _provider == 'outlook' ? 'Outlook App Password' : 'Email Password / App Password',
          _appPassCtrl,
          obscure: true,
          hint: '16-character app password',
        ),
        const SizedBox(height: 14),
        _field('Send Codes To (optional)',  _recipientCtrl, keyboardType: TextInputType.emailAddress,
            hint: 'Leave blank to use same email above'),

        // Custom SMTP extras
        if (_provider == 'custom') ...[
          const SizedBox(height: 14),
          _field('SMTP Host', _customHostCtrl, hint: 'smtp.example.com'),
          const SizedBox(height: 14),
          _field('SMTP Port', _customPortCtrl, keyboardType: TextInputType.number, hint: '587'),
        ],

        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _errorBanner(),
        ],
        const SizedBox(height: 24),

        FilledButton.icon(
          onPressed: _isLoading ? null : _sendTestCode,
          icon: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_outlined, size: 18),
          label: const Text('Send Test Code to My Email'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _providerTabs() {
    return Row(
      children: [
        _tab('gmail', 'Gmail'),
        const SizedBox(width: 8),
        _tab('outlook', 'Outlook'),
        const SizedBox(width: 8),
        _tab('custom', 'Custom SMTP'),
      ],
    );
  }

  Widget _tab(String key, String label) {
    final selected = _provider == key;
    return GestureDetector(
      onTap: () => setState(() { _provider = key; _errorMessage = null; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.divider),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  Widget _providerInstructions() {
    if (_provider == 'gmail') {
      return _infoBox(
        icon: Icons.help_outline,
        color: AppColors.primary,
        bgColor: AppColors.primaryFaded,
        children: const [
          Text('How to get a Gmail App Password:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
          SizedBox(height: 6),
          Text(
            '1. Go to myaccount.google.com\n'
            '2. Security → enable 2-Step Verification (required)\n'
            '3. Security → App passwords\n'
            '4. Select "Mail" → Generate\n'
            '5. Copy the 16-character code and paste it below',
            style: TextStyle(fontSize: 13, color: AppColors.primary, height: 1.6),
          ),
        ],
      );
    }
    // Outlook
    return _infoBox(
      icon: Icons.help_outline,
      color: AppColors.primary,
      bgColor: AppColors.primaryFaded,
      children: const [
        Text('How to get an Outlook App Password:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
        SizedBox(height: 6),
        Text(
          '1. Go to account.microsoft.com\n'
          '2. Security → Advanced security options\n'
          '3. App passwords → Create new app password\n'
          '4. Copy the generated password and paste it below',
          style: TextStyle(fontSize: 13, color: AppColors.primary, height: 1.6),
        ),
      ],
    );
  }

  // ─── Step 3: Enter test code ───────────────────────────

  Widget _buildEnterTestCode() {
    final recipient = _recipientCtrl.text.trim().isEmpty
        ? _emailCtrl.text.trim()
        : _recipientCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backBtn(() => setState(() { _step = _Step.configureEmail; _errorMessage = null; })),
        const SizedBox(height: 20),
        const Text('Enter the Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'A 6-digit code was sent to $recipient.\nEnter it below to confirm everything is working.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _testCodeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofocus: true,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 12, color: AppColors.primary),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        if (_errorMessage != null) ...[const SizedBox(height: 16), _errorBanner()],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _verifyAndEnable,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirm & Enable 2FA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _isLoading ? null : () => setState(() { _step = _Step.configureEmail; _errorMessage = null; }),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Re-send Code'),
        ),
      ],
    );
  }

  // ─── Step 4: TOTP ──────────────────────────────────────

  Widget _buildConfigureTOTP() {
    final qrUri = AuthService.totpQrUri(widget.user.username, _totpSecret);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backBtn(() => setState(() { _step = _Step.chooseMethod; _errorMessage = null; })),
        const SizedBox(height: 20),
        const Text('Authenticator App Setup',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        const Text(
          'Open Google Authenticator (or Authy) on your phone and scan the QR code below.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),

        // QR code
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: QrImageView(data: qrUri, version: QrVersions.auto, size: 200, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 16),

        // Manual key (collapsible hint)
        _infoBox(
          icon: Icons.keyboard_outlined,
          color: AppColors.textSecondary,
          bgColor: const Color(0xFFF5F7FA),
          children: [
            const Text('Can\'t scan? Enter this key manually in your app:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(_totpSecret,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13, color: AppColors.primary,
                          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18, color: AppColors.primary),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _totpSecret));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Key copied'), duration: Duration(seconds: 2)));
                  },
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 24),
        const Text('Enter the 6-digit code shown in your app:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        TextField(
          controller: _totpCodeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 12, color: AppColors.primary),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        if (_errorMessage != null) ...[const SizedBox(height: 12), _errorBanner()],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _verifyTotpAndEnable,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verify & Enable 2FA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ─── Helpers ───────────────────────────────────────────

  Widget _field(String label, TextEditingController ctrl, {
    TextInputType? keyboardType,
    bool obscure = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          obscureText: obscure && _obscurePass,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textHint),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            suffixIcon: obscure
                ? IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.grey),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _backBtn(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back_ios, size: 14, color: AppColors.primary),
          SizedBox(width: 4),
          Text('Back', style: TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _infoBox({required IconData icon, required Color color, required Color bgColor, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorFaded,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(_errorMessage!, style: const TextStyle(fontSize: 13, color: AppColors.error, height: 1.5))),
        ],
      ),
    );
  }
}
