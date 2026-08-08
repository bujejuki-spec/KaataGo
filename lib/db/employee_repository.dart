import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';

/// CRUD for the `employees` table — used by the Super Admin's "Kelola
/// Karyawan" screen. Regular Admins don't get a UI for this yet (out of
/// scope for now); only Super Admin can add/edit/deactivate employees
/// across any restaurant, enforced both here and by RLS.
class EmployeeRepository {
  final _client = Supabase.instance.client;

  Future<List<Employee>> getAll() async {
    final rows = await _client.from('employees').select().order('email');
    return rows.map((r) => Employee.fromMap(r)).toList();
  }

  Future<List<Employee>> getByResto(String restoId) async {
    final rows = await _client
        .from('employees')
        .select()
        .eq('resto_id', restoId)
        .order('email');
    return rows.map((r) => Employee.fromMap(r)).toList();
  }

  Future<void> upsert(Employee employee) async {
    await _client.from('employees').upsert(employee.toMap());
  }

  Future<void> delete(String email) async {
    await _client.from('employees').delete().eq('email', email);
  }
}
