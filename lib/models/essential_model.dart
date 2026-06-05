class EssentialModel {
  final int? id;
  final String name;
  final double amount;
  final String? paidMonth;        // "YYYY-MM" — auto-resets each new month
  final int? paidAccountId;       // which account the payment was deducted from
  final int? paidTransactionId;   // the transaction created (used for reversal)
  final String createdAt;

  const EssentialModel({
    this.id,
    required this.name,
    required this.amount,
    this.paidMonth,
    this.paidAccountId,
    this.paidTransactionId,
    required this.createdAt,
  });

  bool get isPaidThisMonth {
    if (paidMonth == null) return false;
    final now = DateTime.now();
    return paidMonth == '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'amount': amount,
        'paidMonth': paidMonth,
        'paidAccountId': paidAccountId,
        'paidTransactionId': paidTransactionId,
        'createdAt': createdAt,
      };

  factory EssentialModel.fromMap(Map<String, dynamic> m) => EssentialModel(
        id: m['id'] as int?,
        name: m['name'] as String,
        amount: (m['amount'] as num).toDouble(),
        paidMonth: m['paidMonth'] as String?,
        paidAccountId: m['paidAccountId'] as int?,
        paidTransactionId: m['paidTransactionId'] as int?,
        createdAt: m['createdAt'] as String,
      );

  EssentialModel copyWith({
    String? name,
    double? amount,
    String? paidMonth,
    bool clearPaid = false,
    int? paidAccountId,
    bool clearPaidAccount = false,
    int? paidTransactionId,
    bool clearPaidTransaction = false,
  }) =>
      EssentialModel(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        paidMonth: clearPaid ? null : (paidMonth ?? this.paidMonth),
        paidAccountId:
            clearPaidAccount ? null : (paidAccountId ?? this.paidAccountId),
        paidTransactionId: clearPaidTransaction
            ? null
            : (paidTransactionId ?? this.paidTransactionId),
        createdAt: createdAt,
      );
}
