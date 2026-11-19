import 'dart:async';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';
import 'otp_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  UserModel? _user;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Lockout countdown
  Timer? _lockoutTimer;
  Duration _lockoutRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await DatabaseHelper.instance.getUser();
    if (!mounted) return;
    setState(() => _user = user);
    if (user != null && AuthService.isLockedOut(user.lockedUntil)) {
      _startLockoutCountdown(user.lockedUntil!);
    }
  }

  void _startLockoutCountdown(String lockedUntil) {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = AuthService.remainingLockout(lockedUntil);
      setState(() => _lockoutRemaining = remaining);
      if (remaining == Duration.zero) {
        _lockoutTimer?.cancel();
        _loadUser();
      }
    });
    _lockoutRemaining = AuthService.remainingLockout(lockedUntil);
  }

  Future<void> _login() async {
    if (_isLoading || _user == null) return;

    if (AuthService.isLockedOut(_user!.lockedUntil)) {
      setState(() {
        _errorMessage =
            'Account locked. Try again in ${_lockoutRemaining.inMinutes}m ${_lockoutRemaining.inSeconds.remainder(60)}s.';
      });
      return;
    }

    final enteredUsername = _usernameCtrl.text.trim();
    if (enteredUsername.toLowerCase() != _user!.username.toLowerCase()) {
      setState(() => _errorMessage = 'Incorrect username or password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isValid = await AuthService.verifyPassword(
      _passwordCtrl.text,
      _user!.salt,
      _user!.passwordHash,
    );

    if (!mounted) return;

    if (isValid) {
      // Reset failed attempts on successful password entry
      final clearedUser =
          _user!.copyWith(failedLoginAttempts: 0, clearLockedUntil: true);
      await DatabaseHelper.instance.updateUser(clearedUser);
      setState(() => _user = clearedUser);

      if (_user!.twoFactorEnabled) {
        await _proceedTo2FA();
      } else {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context, slideRoute(const MainShell()), (r) => false);
        }
      }
    } else {
      final newAttempts = _user!.failedLoginAttempts + 1;
      final lock = newAttempts >= AuthService.maxLoginAttempts;
      final updatedUser = _user!.copyWith(
        failedLoginAttempts: newAttempts,
        lockedUntil: lock ? AuthService.newLockoutTimestamp() : null,
      );
      await DatabaseHelper.instance.updateUser(updatedUser);
      setState(() {
        _user = updatedUser;
        _isLoading = false;
        if (lock) {
          _errorMessage =
              'Too many failed attempts. Account locked for ${AuthService.lockoutMinutes} minutes.';
          _startLockoutCountdown(updatedUser.lockedUntil!);
        } else {
          final remaining = AuthService.maxLoginAttempts - newAttempts;
          _errorMessage =
              'Incorrect password. $remaining attempt${remaining == 1 ? '' : 's'} remaining.';
        }
      });
    }
  }

  Future<void> _proceedTo2FA() async {
    final user = _user!;

    if (user.twoFactorMethod == 'email') {
      final otp = AuthService.generateOtp();
      final otpHash = AuthService.hashOtp(otp);

      await DatabaseHelper.instance.expireAllOtpSessions(user.id!);
      await DatabaseHelper.instance.createOtpSession(user.id!, otpHash);

      final sent = await EmailService.sendOtp(
        smtpHost: user.smtpHost!,
        smtpPort: user.smtpPort!,
        smtpEmail: user.smtpEmail!,
        smtpPassword: user.smtpPassword!,
        recipient: user.smtpRecipient!,
        otpCode: otp,
      );

      if (!mounted) return;

      if (!sent) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Failed to send login code. Check your email settings in Security.';
        });
        return;
      }
    }

    setState(() => _isLoading = false);
    if (mounted) {
      await Navigator.push(
          context, slideRoute(OtpVerificationScreen(user: user)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              28,
              40,
              28,
              MediaQuery.of(context).viewInsets.bottom + 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 40),
                _buildUsernameField(),
                const SizedBox(height: 16),
                _buildPasswordField(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorBanner(),
                ],
                const SizedBox(height: 32),
                _buildLoginButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.account_balance_wallet,
              color: Colors.white, size: 34),
        ),
        const SizedBox(height: 24),
        const Text(
          'Khazna',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primary),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sign in to continue',
          style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildUsernameField() {
    final isLocked = AuthService.isLockedOut(_user?.lockedUntil);
    return TextField(
      controller: _usernameCtrl,
      enabled: !isLocked && !_isLoading,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Username',
        prefixIcon:
            const Icon(Icons.person_outline, color: AppColors.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    final isLocked = AuthService.isLockedOut(_user?.lockedUntil);
    return TextField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      enabled: !isLocked && !_isLoading,
      onSubmitted: (_) => _login(),
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon:
            const Icon(Icons.lock_outline, color: AppColors.primary),
        suffixIcon: IconButton(
          icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
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
            child: Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    final isLocked = AuthService.isLockedOut(_user?.lockedUntil);
    return FilledButton(
      onPressed: (_isLoading || isLocked) ? null : _login,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
          : isLocked
              ? Text(
                  'Locked — ${_lockoutRemaining.inMinutes}m ${_lockoutRemaining.inSeconds.remainder(60)}s',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                )
              : const Text('Sign In',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}
