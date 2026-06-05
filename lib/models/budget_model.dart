class BudgetModel {
  final int? id;
  final String category;
  final double monthlyLimit;
  final String createdAt;

  const BudgetModel({
    this.id,
    required this.category,
    required this.monthlyLimit,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'category': category,
        'monthlyLimit': monthlyLimit,
        'createdAt': createdAt,
      };

  factory BudgetModel.fromMap(Map<String, dynamic> m) => BudgetModel(
        id: m['id'] as int?,
        category: m['category'] as String,
        monthlyLimit: (m['monthlyLimit'] as num).toDouble(),
        createdAt: m['createdAt'] as String,
      );
}
