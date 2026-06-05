import 'dart:async';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final UserModel user;

  const OtpVerificationScreen({super.key, required this.user});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  String? _errorMessage;

  // Email OTP resend cooldown
  bool _canResend = false;
  int _resendSecondsLeft = 60;
  Timer? _resendTimer;

  bool get _isEmail => widget.user.twoFactorMethod == 'email';

  @override
  void initState() {
    super.initState();
    if (_isEmail) _startResendCooldown();
  }

  @override
  void dispose() {
    for (final c in _digitControllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() {
      _canResend = false;
      _resendSecondsLeft = 60;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendSecondsLeft--);
      if (_resendSecondsLeft <= 0) {
        t.cancel();
        setState(() => _canResend = true);
      }
    });
  }

  String get _enteredCode =>
      _digitControllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_enteredCode.length == 6) {
      _verify();
    }
  }

  Future<void> _verify() async {
    final code = _enteredCode;
    if (code.length != 6) return;
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    bool isValid = false;

    if (_isEmail) {
      final session =
          await DatabaseHelper.instance.getActiveOtpSession(widget.user.id!);
      if (session == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Code expired. Please request a new one.';
        });
        return;
      }

      final sessionId = session['id'] as int;
      final storedHash = session['codeHash'] as String;
      final sessionFailed = session['failedAttempts'] as int;

      if (sessionFailed >= AuthService.maxOtpAttempts) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Too many wrong attempts. Request a new code.';
        });
        return;
      }

      isValid = AuthService.verifyOtp(code, storedHash);

      if (isValid) {
        await DatabaseHelper.instance.markOtpUsed(sessionId);
      } else {
        await DatabaseHelper.instance.incrementOtpFailedAttempts(sessionId);
      }
    } else {
      // TOTP
      isValid = AuthService.verifyTotpCode(widget.user.totpSecret!, code);
    }

    if (!mounted) return;

    if (isValid) {
      Navigator.pushAndRemoveUntil(
          context, slideRoute(const HomeScreen()), (r) => false);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Incorrect code. Please try again.';
      });
      for (final c in _digitControllers) { c.clear(); }
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend || !_isEmail) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    final otp = AuthService.generateOtp();
    final otpHash = AuthService.hashOtp(otp);
    await DatabaseHelper.instance.expireAllOtpSessions(widget.user.id!);
    await DatabaseHelper.instance.createOtpSession(widget.user.id!, otpHash);

    final sent = await EmailService.sendOtp(
      smtpHost: widget.user.smtpHost!,
      smtpPort: widget.user.smtpPort!,
      smtpEmail: widget.user.smtpEmail!,
      smtpPassword: widget.user.smtpPassword!,
      recipient: widget.user.smtpRecipient!,
      otpCode: otp,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (sent) {
      _startResendCooldown();
      for (final c in _digitControllers) { c.clear(); }
      _focusNodes[0].requestFocus();
    } else {
      setState(() => _errorMessage = 'Failed to resend code. Check email settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: AppColors.primary),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 48),
                _buildDigitRow(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _buildErrorBanner(),
                ],
                const SizedBox(height: 32),
                _buildVerifyButton(),
                if (_isEmail) ...[
                  const SizedBox(height: 20),
                  _buildResendRow(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isEmail = _isEmail;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primaryFaded,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            isEmail ? Icons.email_outlined : Icons.security,
            color: AppColors.primary,
            size: 30,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Two-Factor Verification',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Text(
          isEmail
              ? 'Enter the 6-digit code sent to\n${widget.user.smtpRecipient}'
              : 'Enter the 6-digit code from\nyour authenticator app',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildDigitRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) {
        return SizedBox(
          width: 46,
          height: 56,
          child: TextField(
            controller: _digitControllers[i],
            focusNode: _focusNodes[i],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            enabled: !_isLoading,
            onChanged: (v) => _onDigitChanged(i, v),
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary),
            decoration: InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorFaded,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton() {
    return FilledButton(
      onPressed: _isLoading ? null : _verify,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
          : const Text('Verify',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildResendRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Didn't receive a code? ",
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        TextButton(
          onPressed: _canResend ? _resendOtp : null,
          child: Text(
            _canResend
                ? 'Resend'
                : 'Resend in ${_resendSecondsLeft}s',
            style: TextStyle(
              fontSize: 13,
              color: _canResend ? AppColors.primary : AppColors.textHint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
