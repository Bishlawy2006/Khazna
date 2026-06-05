import '../db/database_helper.dart';
import '../models/activity_log_model.dart';
import '../models/bank_model.dart';
import 'bank_identifier.dart';
import 'notification_parser.dart';

/// Orchestrates the full pipeline for auto-parsed bank notifications.
///
/// Future flow:
///   Phone receives bank notification
///     → AutoTransactionService.processNotification(text)
///       → BankIdentifier.matchBank(text, banks)
///       → NotificationParser.parse(text, accountId)
///       → DatabaseHelper.insertTransaction(tx)
///       → DatabaseHelper.logActivity(log)
///       → UI refreshes
///
/// Currently a stub — processNotification returns false until parsing is built.
class AutoTransactionService {
  static final _db = DatabaseHelper.instance;

  /// Attempt to automatically process a bank notification string.
  /// Returns true if a transaction was created, false otherwise.
  static Future<bool> processNotification(String notificationText) async {
    // Step 1: Identify bank
    final banks = await _db.getAllBanks();
    final BankModel? bank =
        BankIdentifier.matchBank(notificationText, banks);
    if (bank == null) return false;

    // Step 2: Find the primary (current) account for this bank
    final accounts = await _db.getAccountsForBank(bank.id!);
    final account = accounts.where((a) => a.type == 'current').firstOrNull;
    if (account == null) return false;

    // Step 3: Parse the notification
    final tx = NotificationParser.parse(
      notificationText,
      accountId: account.id!,
    );
    if (tx == null) return false;

    // Step 4: Insert the transaction (balance updated automatically)
    await _db.insertTransaction(tx);

    // Step 5: Log the activity
    await _db.logActivity(
      ActivityLogModel.transactionAdded(
        type: tx.type,
        amount: tx.amount,
        bankName: bank.name,
        accountName: account.name,
        category: tx.category,
        note: '[Auto-parsed from notification]',
      ),
    );

    return true;
  }
}
