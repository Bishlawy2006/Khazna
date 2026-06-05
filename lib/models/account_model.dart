class AccountModel {
  final int? id;
  final int bankId;
  final String name;
  final String type; // 'current', 'savings', 'certificate'
  final double balance;

  AccountModel({
    this.id,
    required this.bankId,
    required this.name,
    required this.type,
    required this.balance,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bankId': bankId,
        'name': name,
        'type': type,
        'balance': balance,
      };

  factory AccountModel.fromMap(Map<String, dynamic> map) => AccountModel(
        id: map['id'],
        bankId: map['bankId'],
        name: map['name'],
        type: map['type'],
        balance: map['balance'],
      );
}