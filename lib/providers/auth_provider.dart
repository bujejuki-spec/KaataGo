import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/push_service.dart';

import '../supabase_config.dart';

enum EmployeeRole { superAdmin, owner, admin, kasir, chef, finance }

/// Which door the sign-in came through, so the account can be checked
/// against what the person actually picked.
///
/// Without this, "Customer" and "Resto" were only labels on two buttons:
/// whichever email you handed over decided where you ended up, so staff
/// tapping Customer landed in the staff app and a customer tapping Resto
/// landed in the customer app.
enum LoginIntent { customer, employee }

/// Maps between the Dart enum and the `employees.role` text values in
/// Postgres ("super_admin" uses a snake_case DB value, unlike the
/// others, so it can't just rely on [EmployeeRole.name]).
const _roleDbValues = {
  EmployeeRole.superAdmin: 'super_admin',
  EmployeeRole.owner: 'owner',
  EmployeeRole.admin: 'admin',
  EmployeeRole.kasir: 'kasir',
  EmployeeRole.chef: 'chef',
  EmployeeRole.finance: 'finance',
};

/// Nilai peran seperti yang tertulis di database.
///
/// Dipakai juga saat mendaftarkan perangkat untuk notifikasi push, yang
/// mencocokkan peran sebagai teks — dan `EmployeeRole.name` diam-diam
/// menghasilkan "superAdmin", bukan "super_admin".
extension EmployeeRoleDb on EmployeeRole {
  String get dbValue => _roleDbValues[this]!;
}

const _roleDisplayLabels = {
  EmployeeRole.superAdmin: 'Super Admin',
  EmployeeRole.owner: 'Owner',
  EmployeeRole.admin: 'Admin',
  EmployeeRole.kasir: 'Kasir',
  EmployeeRole.chef: 'Chef',
  EmployeeRole.finance: 'Finance',
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
/// What the `employees` lookup found, kept as a value so a sign-in can be
/// judged against the caller's intent before any of it is committed to
/// [AuthProvider]'s fields.
class _EmployeeLookup {
  final EmployeeRole? role;

  /// Semua resto yang dipegang akun ini. Seorang pemilik dua cabang
  /// punya satu baris `employees` per resto, jadi hasilnya bisa lebih
  /// dari satu.
  final List<String> restoIds;

  final String? name;

  /// Set when the account resolves to an employee whose resto has been
  /// switched off, or when the lookup itself failed — either way the
  /// message is meant for the login screen.
  final String? blockedReason;

  const _EmployeeLookup({
    this.role,
    this.restoIds = const [],
    this.name,
    this.blockedReason,
  });

  bool get isEmployee => role != null;
}

class AuthProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _googleSignIn = GoogleSignIn(
    serverClientId: SupabaseConfig.googleWebClientId,
  );

  User? user;
  EmployeeRole? role;

  /// Resto yang sedang dibuka. Semua layar membaca ini, jadi berpindah
  /// resto cukup mengubah satu nilai — asalkan layarnya dibangun ulang,
  /// yang dijamin RootScreen lewat key-nya.
  String? restoId;

  /// Seluruh resto yang boleh dia kelola. Satu isi untuk kebanyakan
  /// karyawan; lebih dari satu untuk Admin/Finance/Owner yang memegang
  /// beberapa cabang.
  List<String> restoIds = const [];

  String? employeeName;
  bool isCheckingRole = false;
  bool isInitializing = true;
  String? lastError;

  bool get isLoggedIn => user != null;
  bool get isEmployee => role != null;
  bool get isSuperAdmin => role == EmployeeRole.superAdmin;
  bool get isAdmin => role == EmployeeRole.admin;
  bool get isKasir => role == EmployeeRole.kasir;
  bool get isChef => role == EmployeeRole.chef;
  bool get isFinance => role == EmployeeRole.finance;

  /// Owner memegang seluruh menu Chef, Kasir, Admin, dan Finance.
  bool get isOwner => role == EmployeeRole.owner;

  bool get hasMultipleRestos => restoIds.length > 1;

  /// Human-readable role label ("Admin", "Super Admin", ...) for display
  /// on each role's home screen header, or null if not an employee.
  String? get roleLabel => role == null ? null : _roleDisplayLabels[role];

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

  /// Signs in and then checks the account against [intent], refusing the
  /// mismatch instead of quietly sending the person wherever their email
  /// happens to belong.
  ///
  /// Nothing is committed to this provider until that check passes: the
  /// lookup runs against the freshly signed-in email rather than
  /// [user], so a rejected sign-in never flips [isLoggedIn] and never
  /// makes the router swap screens out from under the login flow. The
  /// screen that called this stays mounted and can show the reason from
  /// [lastError].
  Future<void> signInWithGoogle({required LoginIntent intent}) async {
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
      final signedIn = response.user;
      final email = signedIn?.email;
      if (signedIn == null || email == null) {
        lastError = 'Gagal login: akun tidak punya alamat email.';
        await _discardSession();
        return;
      }

      final found = await _lookupEmployee(email);

      if (found.blockedReason != null) {
        lastError = found.blockedReason;
        await _discardSession();
        return;
      }

      if (intent == LoginIntent.employee && !found.isEmployee) {
        lastError = 'Akun $email belum terdaftar sebagai karyawan resto.\n'
            'Minta admin untuk menambahkan email ini ke daftar karyawan.';
        await _discardSession();
        return;
      }

      if (intent == LoginIntent.customer && found.isEmployee) {
        final label = _roleDisplayLabels[found.role] ?? 'karyawan';
        lastError = 'Akun $email terdaftar sebagai $label resto.\n'
            'Masuk lewat pilihan "Resto", bukan "Customer".';
        await _discardSession();
        return;
      }

      user = signedIn;
      role = found.role;
      restoIds = found.restoIds;
      restoId = await _restoreSelectedResto(found.restoIds);
      employeeName = found.name;
      notifyListeners();
    } catch (e) {
      lastError = 'Gagal login: $e';
      notifyListeners();
    }
  }

  /// Drops a session that was established but then refused, so a rejected
  /// attempt doesn't leave the app half-authenticated. Deliberately does
  /// not clear [lastError] — that message is the whole point.
  Future<void> _discardSession() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
    user = null;
    role = null;
    restoId = null;
    restoIds = const [];
    employeeName = null;
    notifyListeners();
  }

  /// Applies a lookup to this provider's fields. Used on app launch,
  /// where there's no intent to check against — the account was already
  /// accepted through one of the doors in an earlier session.
  Future<void> _checkEmployeeRole() async {
    final email = user?.email;
    if (email == null) {
      role = null;
      notifyListeners();
      return;
    }

    isCheckingRole = true;
    notifyListeners();

    final found = await _lookupEmployee(email);
    role = found.role;
    restoIds = found.restoIds;
    restoId = await _restoreSelectedResto(found.restoIds);
    employeeName = found.name;
    if (found.blockedReason != null) lastError = found.blockedReason;

    isCheckingRole = false;
    notifyListeners();

    // Signed out last so isCheckingRole is already false by the time
    // listeners react to isLoggedIn flipping — avoids the login screen
    // flashing a stuck spinner mid-transition. signOut() doesn't touch
    // lastError, so the message survives for the login screen.
    if (found.blockedReason != null) await signOut();
  }

  /// Membaca seluruh baris `employees` milik [rawEmail] tanpa menyentuh
  /// state apa pun.
  ///
  /// Bisa mengembalikan beberapa resto: satu orang punya satu baris per
  /// resto yang dia pegang. Perannya diambil dari baris pertama yang sah
  /// — satu orang tidak dimaksudkan berperan beda-beda di tiap cabang,
  /// dan kalau itu terjadi, yang pertama yang berlaku.
  Future<_EmployeeLookup> _lookupEmployee(String rawEmail) async {
    final email = rawEmail.toLowerCase();
    try {
      debugPrint('[Auth] Checking employee rows for: $email');
      final rows = await _supabase.from('employees').select().eq('email', email);
      debugPrint('[Auth] Rows: $rows');
      if (rows.isEmpty) return const _EmployeeLookup();

      EmployeeRole? role;
      String? name;
      final restoIds = <String>[];

      for (final row in rows) {
        final active = row['active'] != false;
        final roleStr = row['role'] as String?;
        final restoIdValue = row['resto_id'] as String?;
        if (!active || roleStr == null) continue;

        // Peran yang tidak dikenal (mis. baris lama dari versi
        // berikutnya) dilewati diam-diam, bukan melempar galat yang akan
        // mengunci seluruh akun dari aplikasi.
        EmployeeRole? parsed;
        for (final entry in _roleDbValues.entries) {
          if (entry.value == roleStr) {
            parsed = entry.key;
            break;
          }
        }
        if (parsed == null) continue;

        // super_admin tidak terikat satu resto, jadi resto_id-nya boleh
        // kosong — untuk peran lain, baris tanpa resto tidak berarti apa
        // pun dan dilewati.
        if (parsed == EmployeeRole.superAdmin) {
          return _EmployeeLookup(role: parsed, name: row['name'] as String?);
        }
        if (restoIdValue == null) continue;

        role ??= parsed;
        name ??= row['name'] as String?;
        if (!restoIds.contains(restoIdValue)) restoIds.add(restoIdValue);
      }

      if (role == null || restoIds.isEmpty) return const _EmployeeLookup();

      // Resto yang dinonaktifkan Super Admin disaring, bukan memblokir
      // seluruh akun: pemilik dua cabang yang satu cabangnya ditutup
      // sementara tetap harus bisa mengurus cabang yang lain.
      final restoRows = await _supabase
          .from('restaurants')
          .select('id, active')
          .inFilter('id', restoIds);
      final activeIds = restoIds
          .where((id) => restoRows
              .where((r) => r['id'] == id)
              .every((r) => r['active'] != false))
          .toList();

      if (activeIds.isEmpty) {
        return const _EmployeeLookup(
          blockedReason: 'Resto ini sedang dinonaktifkan sementara.\n'
              'Silakan hubungi Call Center KaataGo untuk info lebih lanjut.',
        );
      }

      return _EmployeeLookup(role: role, restoIds: activeIds, name: name);
    } catch (e) {
      debugPrint('[Auth] ERROR checking employee role: $e');
      return _EmployeeLookup(blockedReason: 'Gagal cek status karyawan: $e');
    }
  }

  /// Berpindah ke resto lain yang dia pegang.
  ///
  /// Pilihannya diingat sampai logout, supaya membuka aplikasi besok
  /// tidak melemparnya kembali ke cabang yang salah.
  Future<void> switchResto(String id) async {
    if (!restoIds.contains(id) || id == restoId) return;
    restoId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRestoKey, id);
    notifyListeners();
  }

  static const _lastRestoKey = 'auth_last_resto_id';

  /// Menentukan resto mana yang dibuka setelah login: yang terakhir
  /// dipilih kalau masih dipegang, kalau tidak yang pertama.
  Future<String?> _restoreSelectedResto(List<String> available) async {
    if (available.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_lastRestoKey);
      if (last != null && available.contains(last)) return last;
    } catch (_) {
      // Preferensi tidak terbaca — jatuh ke pilihan pertama saja.
    }
    return available.first;
  }

  Future<void> signOut() async {
    // Dilepas sebelum sesinya hilang: menghapus baris token butuh sesi
    // yang masih sah. Kalau gagal pun tidak menghalangi logout — token
    // yang tertinggal paling jauh berarti satu notifikasi nyasar, jauh
    // lebih ringan daripada orang yang tidak bisa keluar dari akunnya.
    await PushService.instance.unregister();
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
    user = null;
    role = null;
    restoId = null;
    restoIds = const [];
    employeeName = null;
    notifyListeners();
  }
}
