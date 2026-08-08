/// Mirrors a row in Postgres `employees` — an account allowed to sign in
/// as staff (rather than falling through to the customer flow), scoped
/// to one restaurant (except `super_admin`, which isn't scoped at all).
class Employee {
  final String email;
  final String role; // 'super_admin' | 'admin' | 'kasir' | 'chef'
  final String? restoId;
  final bool active;

  Employee({
    required this.email,
    required this.role,
    required this.restoId,
    this.active = true,
  });

  Map<String, dynamic> toMap() => {
        'email': email,
        'role': role,
        'resto_id': restoId,
        'active': active,
      };

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      email: map['email'] as String,
      role: map['role'] as String,
      restoId: map['resto_id'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }
}
