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

  /// Menyimpan (atau memperbarui) keanggotaan seseorang pada satu resto.
  ///
  /// Target konfliknya disebut eksplisit karena tabel ini tidak lagi
  /// punya kunci utama: yang unik adalah pasangan (email, resto_id),
  /// dijaga oleh unique index — baris super_admin ber-resto_id NULL
  /// membuat pasangan itu tidak bisa dijadikan kunci utama. Tanpa
  /// onConflict, PostgREST akan mencari kunci utama yang sudah tidak ada
  /// dan penyimpanan gagal.
  Future<void> upsert(Employee employee) async {
    await _client
        .from('employees')
        .upsert(employee.toMap(), onConflict: 'email,resto_id');
  }

  /// Menghapus keanggotaan pada satu resto, bukan seluruh akunnya.
  ///
  /// Satu email kini bisa terdaftar di beberapa resto sekaligus, jadi
  /// menghapus berdasarkan email saja akan mengeluarkan orang itu dari
  /// semua cabang — termasuk yang tidak sedang diurus.
  Future<void> delete(String email, String? restoId) async {
    final query = _client.from('employees').delete().eq('email', email);
    if (restoId != null) {
      await query.eq('resto_id', restoId);
    } else {
      // super_admin tidak terikat resto; barisnya memang cuma satu.
      await query;
    }
  }
}
