class BankModel {
  final int? id;
  final String name;

  BankModel({this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory BankModel.fromMap(Map<String, dynamic> map) =>
      BankModel(id: map['id'], name: map['name']);
}