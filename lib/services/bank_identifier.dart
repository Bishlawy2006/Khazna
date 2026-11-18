import '../models/bank_model.dart';
import 'notification_parser.dart';

/// Matches a raw SMS / notification text to one of the user's banks.
///
/// Some banks never print their own name in the SMS (El Ahly's card message
/// only carries the 19623 hotline; Mashreq's card message is generic English),
/// so each known bank has a list of message *signatures*: names, hotline
/// numbers and message templates.
///
/// The user creates banks by typing a name, so the stored name may be
/// "El Ahly", "NBE", "Mashreq"... [_Known.nameMatch] maps whatever they typed
/// to the right signature set.
///
/// Short Latin names use word boundaries so "nbe" does not match inside
/// another word, and the hotline is matched as a whole number so it cannot
/// match inside an amount like 119623.50.
class BankIdentifier {
  BankIdentifier._();

  static final List<_Known> _known = [
    _Known(
      nameMatch: RegExp(r'ahly|\bnbe\b|national bank|الأهلي|الاهلي',
          caseSensitive: false),
      signatures: [
        RegExp(r'\b(?:ahly|nbe)\b', caseSensitive: false),
        RegExp(r'national bank of egypt', caseSensitive: false),
        RegExp('البنك الأهلي|البنك الاهلي'),
        RegExp(r'(?<!\d)19623(?!\d)'), // NBE hotline (also printed as ١٩٦٢٣)
      ],
    ),
    _Known(
      nameMatch:
          RegExp(r'\bcib\b|commercial international|سي اي بي', caseSensitive: false),
      signatures: [
        RegExp(r'\bcib\b', caseSensitive: false),
        RegExp(r'commercial international', caseSensitive: false),
        RegExp('سي اي بي'),
      ],
    ),
    _Known(
      nameMatch: RegExp(r'telda', caseSensitive: false),
      signatures: [RegExp(r'telda', caseSensitive: false)],
    ),
    _Known(
      nameMatch: RegExp(r'mashreq|المشرق', caseSensitive: false),
      signatures: [
        RegExp(r'mashreq', caseSensitive: false),
        RegExp('المشرق'),
        // Card-purchase template, which has no bank name in it.
        RegExp(r'your card ending with \S+ has been used at',
            caseSensitive: false),
      ],
    ),
  ];

  /// Finds the first bank in [availableBanks] whose signature appears in
  /// [text]. Returns null when nothing matches.
  static BankModel? matchBank(String text, List<BankModel> availableBanks) {
    final normalized = NotificationParser.normalize(text);

    for (final bank in availableBanks) {
      final known =
          _known.where((k) => k.nameMatch.hasMatch(bank.name)).firstOrNull;
      final signatures = known?.signatures ??
          [RegExp(RegExp.escape(bank.name), caseSensitive: false)];
      if (signatures.any((s) => s.hasMatch(normalized))) {
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

class _Known {
  /// Matches the bank name as the user typed it.
  final RegExp nameMatch;

  /// Matches text inside an SMS from that bank.
  final List<RegExp> signatures;

  const _Known({required this.nameMatch, required this.signatures});
}
