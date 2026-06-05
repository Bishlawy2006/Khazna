import 'package:flutter/material.dart';

// ─── Colors ────────────────────────────────────────────────────────────────

class AppColors {
  static const primary       = Color(0xFF1A237E);
  static const primaryLight  = Color(0xFF3949AB);
  static const primaryFaded  = Color(0xFFE8EAF6);
  static const success       = Color(0xFF2E7D32);
  static const successFaded  = Color(0xFFE8F5E9);
  static const error         = Color(0xFFC62828);
  static const errorFaded    = Color(0xFFFFEBEE);
  static const warning       = Color(0xFFE65100);
  static const warningFaded  = Color(0xFFFFF3E0);
  static const surface       = Color(0xFFF5F7FA);
  static const card          = Colors.white;
  static const textPrimary   = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textHint      = Color(0xFF9CA3AF);
  static const divider       = Color(0xFFE5E7EB);
  static const cashGreen     = Color(0xFF2E7D32);
  static const incomeGreen   = Color(0xFF1B5E20);
  static const expenseRed    = Color(0xFFC62828);
}

// ─── Text Styles ────────────────────────────────────────────────────────────

class AppTextStyles {
  static const heading = TextStyle(
    fontSize: 26, fontWeight: FontWeight.bold,
    color: AppColors.textPrimary, letterSpacing: -0.3,
  );
  static const screenTitle = TextStyle(
    fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
  );
  static const sectionTitle = TextStyle(
    fontSize: 15, fontWeight: FontWeight.bold,
    color: AppColors.primary, letterSpacing: 0.1,
  );
  static const cardTitle = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.textPrimary,
  );
  static const bodyMedium = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
  );
  static const secondary = TextStyle(
    fontSize: 13, color: AppColors.textSecondary,
  );
  static const caption = TextStyle(
    fontSize: 11, color: AppColors.textHint,
  );
  static const label = TextStyle(
    fontSize: 11, fontWeight: FontWeight.bold,
    color: AppColors.textSecondary, letterSpacing: 0.8,
  );
  static const amountLarge = TextStyle(
    fontSize: 34, fontWeight: FontWeight.bold,
    color: Colors.white, letterSpacing: 0.3,
  );
  static const amountMedium = TextStyle(
    fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.2,
  );
}

// ─── Shadows ────────────────────────────────────────────────────────────────

class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x09000000), blurRadius: 8,  offset: Offset(0, 2)),
    BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
  static const elevated = [
    BoxShadow(color: Color(0x16000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static const primary = [
    BoxShadow(color: Color(0x4D1A237E), blurRadius: 18, offset: Offset(0, 8)),
  ];
  static const success = [
    BoxShadow(color: Color(0x4D2E7D32), blurRadius: 14, offset: Offset(0, 6)),
  ];
}

// ─── Reusable Decorations ───────────────────────────────────────────────────

class AppDeco {
  static const card = BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.all(Radius.circular(14)),
    boxShadow: AppShadows.card,
  );

  static const primaryGradient = BoxDecoration(
    gradient: LinearGradient(
      colors: [AppColors.primary, AppColors.primaryLight],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.all(Radius.circular(16)),
    boxShadow: AppShadows.primary,
  );

  static const successGradient = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.only(
      bottomLeft: Radius.circular(24),
      bottomRight: Radius.circular(24),
    ),
    boxShadow: AppShadows.success,
  );

  static BoxDecoration pill(Color color) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(20),
  );
}

// ─── Navigation ─────────────────────────────────────────────────────────────

Route<T> slideRoute<T>(Widget screen) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, _, _) => screen,
    transitionDuration: const Duration(milliseconds: 270),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)).animate(animation),
      child: child,
    ),
  );
}

// ─── AppBar helper ──────────────────────────────────────────────────────────

AppBar buildAppBar(String title, {List<Widget>? actions}) {
  return AppBar(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    title: Text(title, style: AppTextStyles.screenTitle),
    centerTitle: true,
    elevation: 0,
    actions: actions,
  );
}

// ─── Common Widgets ─────────────────────────────────────────────────────────

Widget sectionHeader(String title, {String? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
    child: Row(
      children: [
        Text(title, style: AppTextStyles.sectionTitle),
        if (trailing != null) ...[
          const Spacer(),
          Text(trailing, style: AppTextStyles.caption),
        ],
      ],
    ),
  );
}

Widget emptyState(IconData icon, String title, String subtitle) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(
              color: AppColors.primaryFaded,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 38, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: AppTextStyles.cardTitle, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(subtitle,
              style: AppTextStyles.secondary, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Widget handleBar() {
  return Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
