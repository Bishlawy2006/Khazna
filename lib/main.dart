import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db/database_helper.dart';
import 'screens/main_shell.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'services/notification_service.dart';
import 'services/session_service.dart';
import 'services/sms_queue_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await NotificationService.initialize();
  await DatabaseHelper.instance.processAllCertificateInterest();
  await DatabaseHelper.instance.ensureCashAccountExists();

  // iOS: pick up SMS queued by the Shortcuts "Process Bank SMS" action,
  // now and every time the app returns to the foreground.
  await SmsQueueService.drain();
  WidgetsBinding.instance.addObserver(SmsQueueLifecycleObserver());

  runApp(const KhaznaApp());
}

class KhaznaApp extends StatelessWidget {
  const KhaznaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khazna',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.surface,
        cardTheme: const CardThemeData(
          elevation: 3,
          shadowColor: Color(0x18000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(88, 48),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(88, 48),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        dividerTheme: const DividerThemeData(space: 1, thickness: 1),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Widget? _screen;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tryResolve();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tryResolve();
  }

  /// Decide the first screen only while the app is in the foreground:
  /// Face ID cannot be shown when iOS launched us in the background
  /// (e.g. from the SMS Shortcut), so wait until we are resumed.
  void _tryResolve() {
    if (_screen != null || _resolving) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _resolving = true;
    _resolve().whenComplete(() => _resolving = false);
  }

  Future<void> _resolve() async {
    final user = await DatabaseHelper.instance.getUser();
    if (!mounted) return;
    if (user == null) {
      setState(() => _screen = const RegisterScreen());
      return;
    }

    // A remembered session skips the password screen; on iOS it first asks
    // for Face ID / Touch ID / passcode. Cancel or failure → normal login.
    final resume = await SessionService.tryResume();
    if (!mounted) return;
    setState(() {
      _screen = resume ? const MainShell() : const LoginScreen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _screen ??
        const Scaffold(
          backgroundColor: AppColors.surface,
          body: Center(child: CircularProgressIndicator()),
        );
  }
}
