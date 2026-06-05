import '../models/bank_model.dart';

/// Matches a raw notification text to a known bank.
/// Returns the bank name string, or null if no match found.
///
/// Future: each bank has its own SMS/notification signature patterns.
/// These will be populated as we add real notification parsing.
class BankIdentifier {
  static const _patterns = <String, List<String>>{
    'El Ahly':    ['ahly', 'nbe', 'national bank of egypt', 'البنك الأهلي'],
    'CIB':        ['cib', 'commercial international', 'سي اي بي'],
    'Telda':      ['telda'],
    'El Mashreq': ['mashreq', 'المشرق'],
  };

  /// Finds the best-matching bank from [availableBanks] given the
  /// notification [text]. Returns the matched bank or null.
  static BankModel? matchBank(String text, List<BankModel> availableBanks) {
    final lower = text.toLowerCase();

    for (final bank in availableBanks) {
      final keywords = _patterns[bank.name] ??
          [bank.name.toLowerCase()];
      if (keywords.any((k) => lower.contains(k))) {
        return bank;
      }
    }
    return null;
  }

  /// Returns the asset path for the card image of a given bank name.
  static String? cardImageForBank(String bankName) {
    final lower = bankName.toLowerCase();
    if (lower.contains('ahly') ||
        lower.contains('national bank') ||
        lower.contains('nbe')) {
      return 'assets/images/cards/nbe_card.png';
    } else if (lower.contains('cib')) {
      return 'assets/images/cards/cib_card.png';
    } else if (lower.contains('telda')) {
      return 'assets/images/cards/telda_card.png';
    } else if (lower.contains('mashreq')) {
      return 'assets/images/cards/elmashreq_card.png';
    }
    return null;
  }
}
