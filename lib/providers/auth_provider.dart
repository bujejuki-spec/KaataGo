import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

enum EmployeeRole { superAdmin, admin, kasir, chef }

/// Maps between the Dart enum and the `employees.role` text values in
/// Postgres ("super_admin" uses a snake_case DB value, unlike the other
/// three, so it can't just rely on [EmployeeRole.name]).
const _roleDbValues = {
  EmployeeRole.superAdmin: 'super_admin',
  EmployeeRole.admin: 'admin',
  EmployeeRole.kasir: 'kasir',
  EmployeeRole.chef: 'chef',
};

/// Handles Google Sign-In (via Supabase Auth) and figures out the
/// signed-in account's role AND which restaurant they work at, both
/// checked against the `employees` table in Postgres (keyed by
/// lowercased email, with `role`: "super_admin" | "admin" | "kasir" |
/// "chef", and `resto_id`: which restaurant's data this account can
/// see/manage — null for super_admin, who isn't scoped to one resto).
///
/// No login at all, or a login that isn't a registered employee, is
/// treated as "customer" — self-order browsing doesn't require an
/// account.
class AuthProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _googleSignIn = GoogleSignIn(
    serverClientId: SupabaseConfig.googleWebClientId,
  );

  User? user;
  EmployeeRole? role;
  String? restoId;
  bool isCheckingRole = false;
  bool isInitializing = true;
  String? lastError;

  bool get isLoggedIn => user != null;
  bool get isEmployee => role != null;
  bool get isSuperAdmin => role == EmployeeRole.superAdmin;
  bool get isAdmin => role == EmployeeRole.admin;
  bool get isKasir => role == EmployeeRole.kasir;
  bool get isChef => role == EmployeeRole.chef;

  AuthProvider() {
    _bootstrap();
  }

  /// Supabase Auth persists the signed-in session across app restarts on
  /// its own — this just picks that back up on launch so an employee who
  /// never explicitly logged out goes straight back to their role's
  /// screen instead of seeing the Customer/Karyawan choice again.
  Future<void> _bootstrap() async {
    final current = _supabase.auth.currentUser;
    if (current != null) {
      user = current;
      await _checkEmployeeRole();
    }
    isInitializing = false;
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    lastError = null;
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // user cancelled

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        lastError = 'Gagal login: tidak ada ID token dari Google.';
        notifyListeners();
        return;
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      user = response.user;
      notifyListeners();

      await _checkEmployeeRole();
    } catch (e) {
      lastError = 'Gagal login: $e';
      notifyListeners();
    }
  }

  Future<void> _checkEmployeeRole() async {
    if (user?.email == null) {
      role = null;
      notifyListeners();
      return;
    }
    isCheckingRole = true;
    notifyListeners();

    try {
      final email = user!.email!.toLowerCase();
      debugPrint('[Auth] Checking employee role for: $email');
      final rows = await _supabase
          .from('employees')
          .select()
          .eq('email', email)
          .limit(1);
      debugPrint('[Auth] Rows: $rows');

      if (rows.isNotEmpty) {
        final row = rows.first;
        final active = row['active'] != false;
        final roleStr = row['role'] as String?;
        final restoIdValue = row['resto_id'] as String?;
        // super_admin isn't scoped to a single resto, so resto_id is
        // allowed to be null only for that role.
        final isSuperAdminRow = roleStr == _roleDbValues[EmployeeRole.superAdmin];
        if (active && roleStr != null && (restoIdValue != null || isSuperAdminRow)) {
          role = _roleDbValues.entries
              .firstWhere((e) => e.value == roleStr,
                  orElse: () => throw StateError('Unknown role: $roleStr'))
              .key;
          restoId = restoIdValue;
        } else {
          role = null;
          restoId = null;
        }
      } else {
        role = null;
        restoId = null;
      }
    } catch (e) {
      debugPrint('[Auth] ERROR checking employee role: $e');
      lastError = 'Gagal cek status karyawan: $e';
      role = null;
      restoId = null;
    }

    isCheckingRole = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
    user = null;
    role = null;
    restoId = null;
    notifyListeners();
  }
}
