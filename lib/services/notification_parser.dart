// ignore_for_file: prefer_interpolation_to_compose_strings
import '../models/transaction_model.dart';

/// Parses a raw bank SMS into a [TransactionModel].
///
/// Supported formats (one parser per format, all strict):
///   * El Ahly / NBE  — direct-debit card purchase  ("تم خصم ... عند ...")
///   * El Mashreq     — card purchase               ("... has been used at ... for EGP ...")
///   * El Mashreq     — Instapay sent / received    ("قمت بتحويل لحظي" / "استقبلت تحويل لحظي")
///   * Telda          — card purchase               ("You spent EGP 89 at <merchant>")
///   * Telda          — money received              ("@handle Sent you EGP 20")
///
/// Every message is split into: category, amount, date, time and place
/// (merchant, stored as the note). Telda alerts are push notifications that
/// Shortcuts cannot read; they reach the app through the Apple Wallet
/// "Transaction" automation, which rebuilds this same sentence.
///
/// CIB is not implemented yet (no samples).
///
/// Design rules:
///   * Strict over lenient: if anything about a message is unexpected the
///     parser returns null and the message is only logged as "received". A
///     missed transaction is annoying; a wrong amount silently corrupting a
///     balance is worse.
///   * Privacy: the SMS text is never stored. [TransactionModel.rawNotification]
///     holds a *fingerprint* (built from parsed fields, used to ignore the same
///     SMS being delivered twice), not the message.
class NotificationParser {
  NotificationParser._();

  /// Returns null if the text is not a recognised transaction message.
  ///
  /// [receivedAt] is used as the transaction date for formats that carry no
  /// date of their own (Mashreq card purchases).
  static TransactionModel? parse(
    String notificationText, {
    required int accountId,
    DateTime? receivedAt,
  }) {
    final text = normalize(notificationText);
    final now = receivedAt ?? DateTime.now();

    // Run EVERY format parser, not just until the first hit. Direction is the
    // one thing that must never be wrong (an income booked as an expense, or
    // the reverse, silently corrupts the balance), so if two parsers disagree
    // about whether money came in or went out, the message is rejected.
    final candidates = <_Parsed>[
      ?_parseNbeCardPurchase(text),
      ?_parseMashreqCardPurchase(text, now),
      ?_parseInstapaySent(text),
      ?_parseInstapayReceived(text),
      ?_parseTeldaPurchase(text, now),
      ?_parseTeldaReceived(text, now),
    ];
    if (candidates.isEmpty) return null;
    if (candidates.any((c) => c.type != candidates.first.type)) return null;
    final parsed = candidates.first;
    if (!(parsed.amount > 0)) return null;

    return TransactionModel(
      accountId: accountId,
      amount: parsed.amount,
      type: parsed.type,
      category: parsed.category,
      date: parsed.date,
      note: parsed.note,
      time: parsed.time,
      source: 'auto',
      rawNotification: parsed.fingerprint,
    );
  }

  // ───────────────────────── normalisation ─────────────────────────

  static const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  static const _easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
  static final _bidiMarks =
      RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]');
  static final _whitespace = RegExp(r'\s+');

  /// Arabic-Indic digits → ASCII, Arabic separators → ASCII, strips invisible
  /// bidi marks and collapses whitespace. Shared with [BankIdentifier].
  static String normalize(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      var digit = _arabicIndic.indexOf(ch);
      if (digit < 0) digit = _easternArabicIndic.indexOf(ch);
      if (digit >= 0) {
        out.write(digit);
      } else if (ch == '٫') {
        out.write('.');
      } else if (ch == '٬') {
        out.write(',');
      } else {
        out.write(ch);
      }
    }
    return out
        .toString()
        .replaceAll(_bidiMarks, '')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  // ─────────────────────────── shared bits ───────────────────────────

  // 1,250.00 | 109 | 88.00   (no trailing punctuation captured)
  static const _amt = r'(\d[\d,]*(?:\.\d+)?)';
  static const _cur = r'(?:EGP|جم|جنيه)';

  static double? _amount(String raw) => double.tryParse(raw.replaceAll(',', ''));

  /// Builds 'yyyy-MM-dd' (the format the rest of the app stores) or null if
  /// the parts do not form a real calendar date.
  static String? _date(String d, String m, String y) {
    var year = int.parse(y);
    if (year < 100) year += 2000;
    final month = int.parse(m);
    final day = int.parse(d);
    final dt = DateTime(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  static String _dateOf(DateTime dt) => '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  static String _timeOf(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// 'HH:mm' or null when the parts are not a real time of day.
  static String? _time(String h, String m) {
    final hour = int.parse(h);
    final minute = int.parse(m);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  // ──────────────────────── El Ahly / NBE ────────────────────────
  //
  // تم خصم 109 EGP من بطاقة الخصم المباشر رقم .... باستخدام Mobile Payment
  // عند GUC - COPY MENSA 9 يوم 14/11/26 الساعه 12:26 المتاح 54.82EGP ...
  static final _nbePurchase = RegExp(
    'تم خصم $_amt ?$_cur'
    r'.*? عند (.+?) يوم (\d{1,2})/(\d{1,2})/(\d{2,4}) الساع[هة] (\d{1,2}):(\d{2})',
    dotAll: true,
  );

  static _Parsed? _parseNbeCardPurchase(String text) {
    final m = _nbePurchase.firstMatch(text);
    if (m == null) return null;
    final amount = _amount(m.group(1)!);
    // Groups: 1 amount, 2 merchant, 3 day, 4 month, 5 year, 6 hour, 7 minute.
    final date = _date(m.group(3)!, m.group(4)!, m.group(5)!);
    final time = _time(m.group(6)!, m.group(7)!);
    if (amount == null || date == null || time == null) return null;
    final merchant = m.group(2)!.trim();
    return _Parsed(
      amount: amount,
      type: 'expense',
      category: 'Card Payment',
      date: date,
      time: time,
      note: merchant,
      // No reference number in this format: date + minute + amount + merchant.
      fingerprint:
          'nbe|$amount|$date|${m.group(6)}:${m.group(7)}|$merchant',
    );
  }

  // ───────────────────────── El Mashreq ─────────────────────────
  //
  // Your Card ending with .... has been used at CIRCLE K TRED MORE for EGP 88.00
  //
  // No date or time in the message → the time the SMS reached the phone is
  // used. No reference number → no fingerprint (two identical purchases must
  // never be merged).
  static final _mashreqCard = RegExp(
    r'card ending with \S+ has been used at (.+?) for EGP ?' + _amt,
    caseSensitive: false,
  );

  static _Parsed? _parseMashreqCardPurchase(String text, DateTime receivedAt) {
    final m = _mashreqCard.firstMatch(text);
    if (m == null) return null;
    final amount = _amount(m.group(2)!);
    if (amount == null) return null;
    return _Parsed(
      amount: amount,
      type: 'expense',
      category: 'Card Payment',
      date: _dateOf(receivedAt),
      time: _timeOf(receivedAt),
      note: m.group(1)!.trim(),
    );
  }

  // ──────────────────── El Mashreq — Instapay (IPN) ────────────────────
  //
  // قمت بتحويل لحظي من 6..5 بمبلغ 225.50 جم عبر IPN يوم 12-11-2026
  // الساعة 21:01 رقم المعاملة ebca3042 ...
  static final _ipnSent = RegExp(
    r'قمت بتحويل لحظي من \S+ بمبلغ ' + _amt + r' ?' + _cur +
    r'.*? يوم (\d{1,2})-(\d{1,2})-(\d{2,4}) الساع[هة] (\d{1,2}):(\d{2})'
    r' رقم المعاملة (\w+)',
    dotAll: true,
  );

  // لقد استقبلت تحويل لحظي على 6..5 بمبلغ 1,250.00 جم عبر IPN من <name>
  // يوم 11-11-2026 الساعة 20:19 رقم المعاملة 1727e69b ...
  static final _ipnReceived = RegExp(
    r'استقبلت تحويل لحظي على \S+ بمبلغ ' + _amt + r' ?' + _cur +
    r'.*? يوم (\d{1,2})-(\d{1,2})-(\d{2,4}) الساع[هة] (\d{1,2}):(\d{2})'
    r' رقم المعاملة (\w+)',
    dotAll: true,
  );
  static final _ipnSender = RegExp(r' عبر IPN من (.+?) يوم ');

  static _Parsed? _parseInstapaySent(String text) {
    final m = _ipnSent.firstMatch(text);
    if (m == null) return null;
    final amount = _amount(m.group(1)!);
    final date = _date(m.group(2)!, m.group(3)!, m.group(4)!);
    final time = _time(m.group(5)!, m.group(6)!);
    if (amount == null || date == null || time == null) return null;
    return _Parsed(
      amount: amount,
      type: 'expense',
      category: 'Transfer',
      date: date,
      time: time,
      note: 'Instapay transfer',
      fingerprint: 'ipn|${m.group(7)}',
    );
  }

  static _Parsed? _parseInstapayReceived(String text) {
    final m = _ipnReceived.firstMatch(text);
    if (m == null) return null;
    final amount = _amount(m.group(1)!);
    final date = _date(m.group(2)!, m.group(3)!, m.group(4)!);
    final time = _time(m.group(5)!, m.group(6)!);
    if (amount == null || date == null || time == null) return null;
    final sender = _ipnSender.firstMatch(text)?.group(1)?.trim();
    return _Parsed(
      amount: amount,
      type: 'income',
      category: 'Transfer',
      date: date,
      time: time,
      note: (sender == null || sender.isEmpty)
          ? 'Instapay transfer'
          : 'Instapay from $sender',
      fingerprint: 'ipn|${m.group(7)}',
    );
  }

  // ───────────────────────────── Telda ─────────────────────────────
  //
  // You spent EGP 89 at German University in Cairo  Balance: EGP 184.01
  //
  // The same sentence is rebuilt by the Wallet "Transaction" automation as
  // "Telda: You spent EGP <Amount> at <Merchant>" (the currency prefix may be
  // doubled by Shortcuts, so repeated "EGP"/"E£" prefixes are tolerated).
  //
  // Telda alerts carry no date or time → the moment the alert reached the
  // phone is used. Only EGP purchases are accepted; "Declined" alerts and any
  // other currency are rejected rather than guessed.
  static final _teldaSpent = RegExp(
    r'you spent (?:(?:EGP|E£|LE)\s?)*' + _amt + r'(?:\s?EGP)? at (.+?)(?=\s+balance\b|\s*$)',
    caseSensitive: false,
  );
  static final _declined = RegExp(r'\bdeclined\b', caseSensitive: false);

  static _Parsed? _parseTeldaPurchase(String text, DateTime receivedAt) {
    if (_declined.hasMatch(text)) return null;
    final m = _teldaSpent.firstMatch(text);
    if (m == null) return null;
    final amount = _amount(m.group(1)!);
    final merchant = m.group(2)!.trim();
    if (amount == null || merchant.isEmpty) return null;
    final date = _dateOf(receivedAt);
    final time = _timeOf(receivedAt);
    return _Parsed(
      amount: amount,
      type: 'expense',
      category: 'Card Payment',
      date: date,
      time: time,
      note: merchant,
      // No reference number: date + minute + amount + merchant.
      fingerprint: 'telda|$amount|$date|$time|$merchant',
    );
  }

  // "@yassinashraf3110 Sent you EGP 20" — a Telda transfer arriving.
  // Like the purchase alert it has no date/time, so the receive moment is used.
  // Only EGP, only a clearly-formed "@handle sent you <amount>" is accepted.
  static final _teldaReceived = RegExp(
    r'(?:^|\s)@([\w.]+)\s+sent you\s+(?:(?:EGP|E£|LE)\s?)*' + _amt + r'(?!\d)(?:\s?EGP)?',
    caseSensitive: false,
  );

  static _Parsed? _parseTeldaReceived(String text, DateTime receivedAt) {
    final m = _teldaReceived.firstMatch(text);
    if (m == null) return null;
    final sender = m.group(1)!;
    final amount = _amount(m.group(2)!);
    if (amount == null) return null;
    final date = _dateOf(receivedAt);
    final time = _timeOf(receivedAt);
    return _Parsed(
      amount: amount,
      type: 'income',
      category: 'Transfer',
      date: date,
      time: time,
      note: 'From @$sender',
      fingerprint: 'telda_in|$amount|$date|$time|$sender',
    );
  }
}

/// Internal parse result before it becomes a [TransactionModel].
class _Parsed {
  final double amount;
  final String type; // 'income' | 'expense'
  final String category;
  final String date; // yyyy-MM-dd
  final String? time; // HH:mm
  final String? note;
  final String? fingerprint;

  const _Parsed({
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.time,
    this.note,
    this.fingerprint,
  });
}
