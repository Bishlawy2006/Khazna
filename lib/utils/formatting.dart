/// Display helpers shared by every screen. No intl dependency.

/// 12345.5 -> "12,345.50"; with decimals: 0 -> "12,346". Negative values keep
/// their sign ("-1,200.00"); a value that rounds to zero never shows "-0.00".
String fmtMoney(double v, {int decimals = 2}) {
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0]
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final isZero = !RegExp(r'[1-9]').hasMatch(fixed);
  final sign = (v < 0 && !isZero) ? '-' : '';
  return decimals > 0 ? '$sign$whole.${parts[1]}' : '$sign$whole';
}

/// "HH:mm" of the current moment when [date] is today, otherwise null.
///
/// Used when a transaction is entered by hand: a time is only meaningful if
/// the entry is for today. A back-dated entry has no known time of day.
String? nowTimeIfToday(DateTime date) {
  final now = DateTime.now();
  final today = date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
  if (!today) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}';
}
