import '../db/database_helper.dart';
import '../models/activity_log_model.dart';
import '../models/bank_model.dart';
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
        category: tx.category,
        note: '[Auto-parsed from SMS]',
      ),
    );

    return SmsOutcome.created;
  }
}
