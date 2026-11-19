import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'activity_screen.dart';
import 'all_transactions_screen.dart';
import 'analysis_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Hosts the five main sections behind one persistent bottom bar.
/// Sections are switched ONLY from this bar (no back arrows between them);
/// detail screens (bank, cash, budgets…) are still pushed on top with a back arrow.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.receipt_long_outlined, label: 'Transactions'),
    (icon: Icons.notifications_none_rounded, label: 'Activity'),
    (icon: Icons.bar_chart_rounded, label: 'Analysis'),
    (icon: Icons.tune_rounded, label: 'Settings'),
  ];

  void _go(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  // Only the active section is built, so each visit reloads fresh data
  // (new SMS-added transactions, balance edits, unread count…).
  Widget _page() {
    switch (_index) {
      case 1:
        return const AllTransactionsScreen();
      case 2:
        return const ActivityScreen();
      case 3:
        return const AnalysisScreen();
      case 4:
        return const SettingsScreen();
      default:
        return HomeScreen(onSwitchTab: _go);
    }
  }

  @override
  Widget build(BuildContext context) {
    // System back (Android) returns to Home first, then exits.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: _page(),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _buildNavBar(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.elevated,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            _navItem(i, _items[i].icon, _items[i].label),
        ],
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final selected = i == _index;
    final color = selected ? Colors.white : AppColors.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _go(i),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
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
}
