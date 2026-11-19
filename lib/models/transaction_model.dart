class TransactionModel {
  final int? id;
  final int accountId;
  final double amount;
  final String type;      // 'income' or 'expense'
  final String category;
  final String date;
  final String? note;
  final String? time;            // 'HH:mm' when known (parsed notifications)
  final String source;           // 'manual' (default) or 'auto' (future parsed)
  final String? rawNotification; // Original bank notification text (future use)

  TransactionModel({
    this.id,
    required this.accountId,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.note,
    this.time,
    this.source = 'manual',
    this.rawNotification,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'accountId': accountId,
    'amount': amount,
    'type': type,
    'category': category,
    'date': date,
    'note': note,
    'time': time,
    'source': source,
    'rawNotification': rawNotification,
  };

  factory TransactionModel.fromMap(Map<String, dynamic> map) =>
      TransactionModel(
        id: map['id'] as int?,
        accountId: map['accountId'] as int,
        amount: map['amount'] as double,
        type: map['type'] as String,
        category: map['category'] as String,
        date: map['date'] as String,
        note: map['note'] as String?,
        time: map['time'] as String?,
        source: map['source'] as String? ?? 'manual',
        rawNotification: map['rawNotification'] as String?,
      );
}
