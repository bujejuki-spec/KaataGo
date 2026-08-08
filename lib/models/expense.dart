class Expense {
  final String id;
  final String restoId;
  final int amount;
  final String description;
  final String? glCode;
  final String createdBy;
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.restoId,
    required this.amount,
    required this.description,
    this.glCode,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'amount': amount,
        'description': description,
        if (glCode != null) 'gl_code': glCode,
        'created_by': createdBy,
      };

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      amount: (map['amount'] as num).toInt(),
      description: map['description'] as String,
      glCode: map['gl_code'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
