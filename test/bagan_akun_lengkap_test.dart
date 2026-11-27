import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Akun GL yang dicari kode harus ada di bagan akun bawaan.
///
/// ── Cara gagalnya, dan kenapa ia tidak berbunyi ──────────────────────
///
/// Fungsi yang menulis jurnal mencari akunnya lebih dulu, lalu menulis
/// hanya kalau ketemu:
///
///   if v_gl.gl_code is not null and v_gl.gl_code <> '' then ... end if;
///
/// Akunnya tidak ada berarti barisnya tidak ditulis — dan tindakannya
/// tetap SUKSES. Serah terima cash pickup tercatat diterima, uangnya
/// dinyatakan sampai, lalu tidak muncul di Saldo Perusahaan. Tanpa
/// galat.
///
/// Periksa Pembukuan pun diam, karena pemeriksaannya ber-JOIN ke
/// `gl_accounts` yang sama: tidak ada akun berarti tidak ada temuan.
///
/// ── Kenapa penjaga yang sudah ada tidak menangkapnya ─────────────────
///
/// `default_gl_test.dart` membaca `supabase/default_gl_accounts.sql`,
/// posisi 45 di `scripts/gabung_sql.sh`. Tapi `_default_gl_accounts()`
/// dinyatakan ulang di beberapa berkas, dan yang BERLAKU adalah yang
/// terakhir jalan. `qris_statis.sql` di posisi 91 menjatuhkan empat akun
/// tanpa ada yang bersuara, karena penjaganya memeriksa berkas yang
/// tidak pernah dipakai basis data.
///
/// Jadi yang dibaca di sini definisi yang BERLAKU, ditentukan dari
/// urutan jalannya — bukan dari nama berkas yang kelihatan benar.
void main() {
  /// Urutan jalannya berkas, dari satu-satunya tempat yang menentukan.
  List<String> urutan() {
    final sh = File('scripts/gabung_sql.sh').readAsStringSync();
    final blok = sh.substring(
        sh.indexOf('FILES=(') + 7, sh.indexOf('\n)', sh.indexOf('FILES=(')));
    return [
      for (final b in blok.split('\n'))
        if (b.trim().endsWith('.sql') && !b.trim().startsWith('#')) b.trim(),
    ];
  }

  final berkas = urutan();

  /// Definisi `_default_gl_accounts()` yang benar-benar berlaku.
  ({String berkas, Set<String> akun}) bawaan() {
    final pola = RegExp(
        r'create or replace function _default_gl_accounts.*?\$\$;',
        dotAll: true);
    String? pemilik;
    String? blok;
    for (final n in berkas) {
      final f = File('supabase/$n');
      if (!f.existsSync()) continue;
      final m = pola.firstMatch(f.readAsStringSync());
      if (m != null) {
        pemilik = n;
        blok = m.group(0);
      }
    }
    expect(pemilik, isNotNull, reason: '_default_gl_accounts tidak ditemukan');
    return (
      berkas: pemilik!,
      akun: RegExp(r"\('([a-z_]+)',")
          .allMatches(blok!)
          .map((m) => m.group(1)!)
          .toSet(),
    );
  }

  /// Akun milik pembukuan KaataGo sendiri, bukan milik merchant.
  ///
  /// Keempatnya disemai khusus untuk resto_id 'kaatago' dengan nilai
  /// yang disebut satu per satu, dan memang tidak boleh jadi bawaan tiap
  /// merchant: pendapatan langganan bukan pendapatan warung.
  const milikPlatform = {
    'subscription',
    'subscription_discount',
    'voucher',
    'voucher_redeem',
  };

  test('tiap akun yang dicari kode ada di bagan bawaan yang berlaku', () {
    final b = bawaan();

    final dicari = <String, Set<String>>{};
    for (final n in berkas) {
      final f = File('supabase/$n');
      if (!f.existsSync()) continue;
      final isi = f.readAsStringSync();
      for (final m in [
        ...RegExp(r"_gl_account_for\([^,]+,\s*'([a-z_]+)'").allMatches(isi),
        ...RegExp(r"payment_method\s*=\s*'([a-z_]+)'").allMatches(isi),
      ]) {
        dicari.putIfAbsent(m.group(1)!, () => <String>{}).add(n);
      }
    }

    final hilang = dicari.keys
        .where((a) => !milikPlatform.contains(a) && !b.akun.contains(a))
        .toList()
      ..sort();

    expect(hilang, isEmpty,
        reason: 'akun ini dicari tapi tidak pernah dibuatkan untuk resto '
            'baru, jadi jurnalnya dilewati diam-diam — tambahkan ke '
            '_default_gl_accounts() di ${b.berkas}:\n'
            '${hilang.map((a) => '  $a — dicari di ${dicari[a]!.join(", ")}').join("\n")}');
  });

  test('bagan bawaan memuat kelima akun yang pernah hilang', () {
    // Disebut satu per satu, bukan sekadar dihitung: yang hilang dulu
    // justru lima akun ini, dan hitungan yang cocok tidak membuktikan
    // yang benar ada di dalamnya.
    final b = bawaan();
    for (final a in [
      'company_cash',
      'company_bank',
      'cash_pickup',
      'opening_balance',
      'cash_variance',
    ]) {
      expect(b.akun, contains(a), reason: '$a hilang dari ${b.berkas}');
    }
  });

  test('tiap akun bawaan dipakai nomor yang sama di seluruh berkas', () {
    // Dua nomor untuk satu akun berarti saldonya terpecah dua: jurnal
    // lama di nomor lama, jurnal baru di nomor baru, dan yang
    // dijumlahkan layar cuma salah satunya.
    //
    // Pengecualian 'capital': ia punya satu nomor untuk merchant
    // (1940001) dan satu untuk pembukuan KaataGo (1100003).
    final nomor = <String, Set<String>>{};
    // Harus 3-tuple yang BERAKHIR di namanya: (akun, nomor, 'GL ...').
    //
    // Pola yang cuma menuntut dua unsur pertama ikut menangkap peta
    // penomoran ulang di `platform_gl_renumber.sql`, yang bentuknya
    // (akun, nomor_lama, nomor_baru, nama) — dan melaporkan nomor lama
    // sebagai nomor kembar yang masih berlaku.
    final pola = RegExp(r"\('([a-z_]+)',\s*'(\d{7})',\s*'GL [^']*'\s*\)");
    for (final n in berkas) {
      final f = File('supabase/$n');
      if (!f.existsSync()) continue;
      for (final m in pola.allMatches(f.readAsStringSync())) {
        nomor.putIfAbsent(m.group(1)!, () => <String>{}).add(m.group(2)!);
      }
    }

    final kembar = nomor.entries
        .where((e) => e.value.length > 1 && e.key != 'capital')
        .map((e) => '${e.key}: ${e.value.join(" vs ")}')
        .toList()
      ..sort();

    expect(kembar, isEmpty, reason: 'satu akun, dua nomor:\n  ${kembar.join("\n  ")}');
  });
}
