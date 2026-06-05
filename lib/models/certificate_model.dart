class CertificateModel {
  final int? id;
  final int accountId;       // the certificate account itself
  final int depositAccountId; // current account where interest goes
  final double principal;
  final double interestRate;  // e.g. 0.19 for 19%
  final String openedDate;
  final String maturityDate;
  final String nextInterestDate;
  final int frequencyMonths;  // 1 = monthly
  final bool isMatured;

  CertificateModel({
    this.id,
    required this.accountId,
    required this.depositAccountId,
    required this.principal,
    required this.interestRate,
    required this.openedDate,
    required this.maturityDate,
    required this.nextInterestDate,
    required this.frequencyMonths,
    this.isMatured = false,
  });

  double get monthlyInterest => (principal * interestRate) / 12;

  Map<String, dynamic> toMap() => {
        'id': id,
        'accountId': accountId,
        'depositAccountId': depositAccountId,
        'principal': principal,
        'interestRate': interestRate,
        'openedDate': openedDate,
        'maturityDate': maturityDate,
        'nextInterestDate': nextInterestDate,
        'frequencyMonths': frequencyMonths,
        'isMatured': isMatured ? 1 : 0,
      };

  factory CertificateModel.fromMap(Map<String, dynamic> map) =>
      CertificateModel(
        id: map['id'],
        accountId: map['accountId'],
        depositAccountId: map['depositAccountId'],
        principal: map['principal'],
        interestRate: map['interestRate'],
        openedDate: map['openedDate'],
        maturityDate: map['maturityDate'],
        nextInterestDate: map['nextInterestDate'],
        frequencyMonths: map['frequencyMonths'],
        isMatured: map['isMatured'] == 1,
      );
}