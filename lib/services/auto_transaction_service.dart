import '../db/database_helper.dart';
import '../models/account_model.dart';
import '../models/activity_log_model.dart';
import '../models/bank_model.dart';
import '../models/transaction_model.dart';
import 'bank_identifier.dart';
import 'notification_parser.dart';

/// What happened to one incoming bank SMS.
enum SmsOutcome {
  /// A transaction was created and the balance updated.
  created,

  /// Recognised, but already recorded earlier (same SMS delivered twice).
  duplicate,

  /// Not recognised or not parseable; nothing was written.
  unparsed,
}

/// Orchestrates the full pipeline for auto-parsed bank SMS:
///
///   SMS text
///     → BankIdentifier.matchBank        (which bank?)
///     → that bank's first 'current' account
///     → NotificationParser.parse        (amount / type / date / merchant)
///     → duplicate check (fingerprint)
///     → DatabaseHelper.insertTransaction (updates the balance)
///     → DatabaseHelper.logActivity
class AutoTransactionService {
  static final _db = DatabaseHelper.instance;

  /// Processes one SMS. [receivedAt] is when it reached the phone; it is used
  /// as the date for message formats that have none.
  static Future<SmsOutcome> processNotification(
    String notificationText, {
    DateTime? receivedAt,
  }) async {
    // Step 1: Identify bank
    final banks = await _db.getAllBanks();
    final BankModel? bank =
        BankIdentifier.matchBank(notificationText, banks);
    if (bank == null) return SmsOutcome.unparsed;

    // Step 2: Find the primary (current) account for this bank
    final accounts = await _db.getAccountsForBank(bank.id!);
    final account = accounts.where((a) => a.type == 'current').firstOrNull;
    if (account == null) return SmsOutcome.unparsed;

    // Step 3: Parse the message
    final tx = NotificationParser.parse(
      notificationText,
      accountId: account.id!,
      receivedAt: receivedAt,
    );
    if (tx == null) return SmsOutcome.unparsed;

    // Step 4: Ignore the same SMS arriving twice (e.g. Shortcut ran twice)
    final fingerprint = tx.rawNotification;
    if (fingerprint != null &&
        await _db.transactionFingerprintExists(fingerprint)) {
      return SmsOutcome.duplicate;
    }

    // Step 5: Insert the transaction (balance updated automatically)
    await _db.insertTransaction(tx);

    // Step 6: Log the activity
    await _db.logActivity(
      ActivityLogModel.transactionAdded(
        type: tx.type,
        amount: tx.amount,
        bankName: bank.name,
        accountName: account.name,
        // The Activity page shows this as the entry's name: prefer the place
        // (merchant / sender) over the generic category.
        category: (tx.note?.trim().isNotEmpty ?? false) ? tx.note!.trim() : tx.category,
        note: '[Auto-parsed from SMS]',
      ),
    );

    return SmsOutcome.created;
  }

  /// Logs one quick "Add Entry" (iOS App Intent) as a transaction.
  ///
  /// [bankKey] is 'cash', 'telda', 'ahly' or 'mashreq'; [type] is 'income' or
  /// 'expense'. [receivedAt] is when the shortcut ran, so the entry keeps the
  /// real date/time even if Khazna is opened much later.
  static Future<SmsOutcome> processQuickEntry({
    required String bankKey,
    required String type,
    required double amount,
    String? note,
    DateTime? receivedAt,
  }) async {
    // Defensive: the Swift side validates too, but the queue is just a file.
    if (!amount.isFinite || amount <= 0 || amount >= 10000000) {
      return SmsOutcome.unparsed;
    }
    if (type != 'income' && type != 'expense') return SmsOutcome.unparsed;

    final String bankName;
    final AccountModel account;
    if (bankKey == 'cash') {
      account = await _db.ensureCashAccountExists();
      bankName = 'Cash';
    } else {
      final bank = BankIdentifier.bankForKey(bankKey, await _db.getAllBanks());
      if (bank == null) return SmsOutcome.unparsed;
      final accounts = await _db.getAccountsForBank(bank.id!);
      account = accounts.where((a) => a.type == 'current').firstOrNull;
      if (account == null) return SmsOutcome.unparsed;
      bankName = bank.name;
    }

    final when = receivedAt ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final cleanNote = note?.trim();
    // Cash is spending; for a bank account a quick entry is a transfer
    // (money sent to / received from a person). The note can name who.
    final category = bankKey == 'cash' && type == 'expense' ? 'Cash' : 'Transfer';

    final tx = TransactionModel(
      accountId: account.id!,
      amount: amount,
      type: type,
      category: category,
      date: '${when.year}-${two(when.month)}-${two(when.day)}',
      time: '${two(when.hour)}:${two(when.minute)}',
      note: (cleanNote == null || cleanNote.isEmpty) ? null : cleanNote,
      source: 'auto',
    );
    // No fingerprint dedupe: two identical entries in a row are legitimate.
    await _db.insertTransaction(tx);
    await _db.logActivity(
      ActivityLogModel.transactionAdded(
        type: tx.type,
        amount: tx.amount,
        bankName: bankName,
        accountName: account.name,
        category: tx.note ?? category,
        note: '[Quick add]',
      ),
    );
    return SmsOutcome.created;
  }
}
