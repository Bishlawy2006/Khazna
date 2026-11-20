/// Small round logos shown next to each activity entry (assets/images/icons/).
///
/// Returns null for banks without a logo (Cash is drawn as an icon instead).
String? bankIconAsset(String? bankName) {
  final lower = (bankName ?? '').toLowerCase();
  if (lower.contains('ahly') ||
      lower.contains('national bank') ||
      RegExp(r'\bnbe\b').hasMatch(lower)) {
    return 'assets/images/icons/bank_ahly.png';
  }
  if (lower.contains('telda')) return 'assets/images/icons/bank_telda.png';
  if (lower.contains('mashreq')) return 'assets/images/icons/bank_mashreq.png';
  return null;
}
