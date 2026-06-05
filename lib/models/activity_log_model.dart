class ActivityLogModel {
  final int? id;
  final String action;      // 'added', 'edited', 'deleted', 'balance_updated'
  final String title;       // Short one-line title
  final String message;     // Full descriptive message
  final double? amount;
  final String? bankName;
  final String? accountName;
  final String? category;
  final String dateTime;    // ISO 8601 full datetime
  final String type;        // 'income', 'expense', 'update', 'deletion'
  final bool isRead;

  ActivityLogModel({
    this.id,
    required this.action,
    required this.title,
    required this.message,
    this.amount,
    this.bankName,
    this.accountName,
    this.category,
    required this.dateTime,
    required this.type,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'action': action,
    'title': title,
    'message': message,
    'amount': amount,
    'bankName': bankName,
    'accountName': accountName,
    'category': category,
    'dateTime': dateTime,
    'type': type,
    'isRead': isRead ? 1 : 0,
  };

  factory ActivityLogModel.fromMap(Map<String, dynamic> map) =>
      ActivityLogModel(
        id: map['id'] as int?,
        action: map['action'] as String,
        title: map['title'] as String,
        message: map['message'] as String,
        amount: map['amount'] as double?,
        bankName: map['bankName'] as String?,
        accountName: map['accountName'] as String?,
        category: map['category'] as String?,
        dateTime: map['dateTime'] as String,
        type: map['type'] as String,
        isRead: (map['isRead'] as int? ?? 0) == 1,
      );

  // ─── Factory helpers ──────────────────────────────────

  static ActivityLogModel transactionAdded({
    required String type,
    required double amount,
    required String bankName,
    required String accountName,
    required String category,
    String? note,
  }) {
    final now = DateTime.now();
    final dtStr = now.toIso8601String();
    final timeStr = '${_fmt2(now.hour)}:${_fmt2(now.minute)}';
    final dateStr = '${now.day} ${_month(now.month)} ${now.year}';

    final action = type == 'income' ? 'Received' : 'Paid';
    final prep   = type == 'income' ? 'into' : 'from';
    final noteStr = note != null && note.isNotEmpty ? ' · $note' : '';

    return ActivityLogModel(
      action: 'added',
      title: '$action EGP ${amount.toStringAsFixed(2)} — $category',
      message:
          'You $action EGP ${amount.toStringAsFixed(2)} $prep $bankName – $accountName'
          ' at $category on $dateStr at $timeStr$noteStr.',
      amount: amount,
      bankName: bankName,
      accountName: accountName,
      category: category,
      dateTime: dtStr,
      type: type,
    );
  }

  static ActivityLogModel transactionEdited({
    required String type,
    required double oldAmount,
    required double newAmount,
    required String bankName,
    required String accountName,
    required String category,
  }) {
    final now = DateTime.now();
    return ActivityLogModel(
      action: 'edited',
      title: 'Edited: $category in $accountName',
      message:
          'Edited transaction in $bankName – $accountName: $category'
          ' EGP ${oldAmount.toStringAsFixed(2)} → EGP ${newAmount.toStringAsFixed(2)}.',
      amount: newAmount,
      bankName: bankName,
      accountName: accountName,
      category: category,
      dateTime: now.toIso8601String(),
      type: 'update',
    );
  }

  static ActivityLogModel transactionDeleted({
    required String type,
    required double amount,
    required String bankName,
    required String accountName,
    required String category,
  }) {
    final now = DateTime.now();
    return ActivityLogModel(
      action: 'deleted',
      title: 'Deleted: $category EGP ${amount.toStringAsFixed(2)}',
      message:
          'Deleted transaction: $category EGP ${amount.toStringAsFixed(2)}'
          ' from $bankName – $accountName.',
      amount: amount,
      bankName: bankName,
      accountName: accountName,
      category: category,
      dateTime: now.toIso8601String(),
      type: 'deletion',
    );
  }

  static ActivityLogModel balanceUpdated({
    required String bankName,
    required String accountName,
    required double oldBalance,
    required double newBalance,
  }) {
    final now = DateTime.now();
    final diff = newBalance - oldBalance;
    final diffStr = diff >= 0
        ? '+EGP ${diff.toStringAsFixed(2)}'
        : '-EGP ${diff.abs().toStringAsFixed(2)}';
    return ActivityLogModel(
      action: 'balance_updated',
      title: 'Balance updated: $accountName ($diffStr)',
      message:
          'Balance updated for $bankName – $accountName:'
          ' EGP ${oldBalance.toStringAsFixed(2)} → EGP ${newBalance.toStringAsFixed(2)}.',
      amount: newBalance,
      bankName: bankName,
      accountName: accountName,
      dateTime: now.toIso8601String(),
      type: 'update',
    );
  }

  // ─── Helpers ──────────────────────────────────────────

  static String _fmt2(int n) => n.toString().padLeft(2, '0');

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static String _month(int m) => _months[m];
}
