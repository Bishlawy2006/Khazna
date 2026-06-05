import '../models/transaction_model.dart';

/// Parses a raw bank notification / SMS text into a TransactionModel.
///
/// Future implementation will:
/// 1. Detect language (Arabic / English).
/// 2. Identify transaction type (payment, withdrawal, deposit, refund).
/// 3. Extract amount, currency, merchant, date, card last-4.
/// 4. Return a TransactionModel with source = 'auto'.
///
/// Returns null if the text cannot be parsed with confidence.
class NotificationParser {
  static TransactionModel? parse(String notificationText, {required int accountId}) {
    // TODO: implement regex/NLP parsing for each bank's notification format.
    //
    // Example patterns to handle:
    //   NBE:  "تم خصم 250 جنيه من حسابك لدى Starbucks"
    //   CIB:  "Your CIB card was charged EGP 250.00 at Starbucks"
    //   Telda:"Paid EGP 250 to Starbucks. Balance: EGP 4,750"
    //
    // When implemented, set source = 'auto' and rawNotification = notificationText.
    return null;
  }
}
