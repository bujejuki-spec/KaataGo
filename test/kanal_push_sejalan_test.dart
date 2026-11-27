import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Id kanal notifikasi hidup di DUA bahasa, dan harus tetap sama.
///
/// ── Cara gagalnya, dan ia tidak berbunyi sama sekali ─────────────────
///
/// Kanal notifikasi Android membekukan nada dan tingkat pentingnya pada
/// saat DIBUAT. Tidak ada cara mengubahnya sesudah itu selain memakai id
/// baru — karena itu id-nya berversi, dan aplikasi MENGHAPUS id versi
/// lama saat dinyalakan (`_idUsang`).
///
/// Notifikasi push tidak dibuat aplikasi; ia dibuat Android dari pesan
/// FCM, dan `channel_id`-nya ditentukan Edge Function
/// `supabase/functions/send-push/index.ts`.
///
/// Jadi begitu `_versi` di Dart dinaikkan tanpa berkas TypeScript itu
/// ikut diubah, yang dikirim adalah id yang sudah tidak ada di HP-nya.
/// Android tidak menolaknya dan tidak mencatat galat apa pun —
/// notifikasinya jatuh ke kanal bawaan, dan nada KaataGo tidak pernah
/// berbunyi.
///
/// Itu benar-benar terjadi saat `_versi` dinaikkan ke 'v2'. Yang
/// menemukannya mitra yang pesanannya masuk tanpa suara, bukan satu pun
/// dari 1.700 tes.
void main() {
  String baca(String jalur) => File(jalur).readAsStringSync();

  final dart = baca('lib/services/notification_service.dart');
  final ts = baca('supabase/functions/send-push/index.ts');

  /// Versi yang dipakai Dart.
  String versiDart() {
    final m = RegExp(r"static const _versi = '([^']+)'").firstMatch(dart);
    expect(m, isNotNull, reason: '_versi tidak ditemukan di Dart');
    return m!.group(1)!;
  }

  /// Id kanal yang BENAR-BENAR dibuat aplikasi, sesudah $_versi diisi.
  Set<String> kanalDibuat() {
    final v = versiDart();
    return RegExp(r"id: '(kaata_[a-z_]+)_\$_versi'")
        .allMatches(dart)
        .map((m) => '${m.group(1)}_$v')
        .toSet();
  }

  /// Id kanal yang disebut Edge Function, sesudah template-nya diisi.
  Set<String> kanalDikirim() {
    final m = RegExp(r'const CHANNEL_VERSION = "([^"]+)"').firstMatch(ts);
    expect(m, isNotNull,
        reason: 'CHANNEL_VERSION tidak ditemukan di send-push/index.ts');
    final v = m!.group(1)!;
    return RegExp(r'`(kaata_[a-z_]+)_\$\{CHANNEL_VERSION\}`')
        .allMatches(ts)
        .map((x) => '${x.group(1)}_$v')
        .toSet();
  }

  test('versinya sama di kedua sisi', () {
    final m = RegExp(r'const CHANNEL_VERSION = "([^"]+)"').firstMatch(ts);
    expect(m, isNotNull);
    expect(m!.group(1), versiDart(),
        reason: 'CHANNEL_VERSION di send-push/index.ts tidak sama dengan '
            '_versi di notification_service.dart — notifikasi push akan '
            'memakai kanal yang sudah dihapus, dan tidak berbunyi');
  });

  test('tiap kanal yang dikirim push benar-benar dibuat aplikasi', () {
    final dibuat = kanalDibuat();
    expect(dibuat, isNotEmpty, reason: 'tidak ada kanal terbaca dari Dart');

    final dikirim = kanalDikirim();
    expect(dikirim, isNotEmpty, reason: 'tidak ada kanal terbaca dari TS');

    final hantu = dikirim.difference(dibuat).toList()..sort();
    expect(hantu, isEmpty,
        reason: 'kanal ini dikirim push tapi tidak pernah dibuat aplikasi, '
            'jadi notifikasinya tidak berbunyi:\n  ${hantu.join("\n  ")}');
  });

  test('tidak ada kanal kirim yang justru ada di daftar yang dihapus', () {
    // Dua pemeriksaan yang berbeda: yang di atas menanyakan "ada atau
    // tidak", yang ini menanyakan "jangan-jangan justru yang sengaja
    // dibuang". Sebuah id bisa lolos yang pertama kalau daftar
    // pembuatannya ikut salah — dan kalau begitu, daftar hapusnya yang
    // masih benar.
    final usang = dart.substring(
        dart.indexOf('static const _idUsang'), dart.indexOf('];',
            dart.indexOf('static const _idUsang')));
    final dibuang = RegExp(r"'(kaata_[a-z_0-9]+)'")
        .allMatches(usang)
        .map((m) => m.group(1)!)
        .toSet();

    for (final k in kanalDikirim()) {
      expect(dibuang, isNot(contains(k)),
          reason: '$k dihapus aplikasi saat dinyalakan');
    }
  });

  group('pesanan menunggu dibayar sampai ke yang memegangnya', () {
    test('push-nya tidak lagi hanya untuk tunai', () {
      // QRIS Statis menyisakan pekerjaan yang sama di kasir — ia yang
      // menyatakan lunasnya, karena QR statis tidak membawa nominal dan
      // tidak ada kabar dari penyedia pembayaran.
      final sql = baca('supabase/push_pending_payment_qris.sql');
      final blok = sql.substring(sql.indexOf('create or replace function'));
      expect(blok, isNot(contains("new.payment_method = 'cash' then")));
      expect(blok, contains("new.payment_status = 'pending' then"));
      expect(blok, contains("'qris_static'"));
    });

    test('peran yang dibangunkan sama dengan yang punya menunya', () {
      // Membangunkan peran yang tidak bisa membuka Pending Payment
      // berarti membunyikan HP orang untuk pekerjaan yang tidak bisa
      // dia kerjakan.
      final katalog = baca('lib/utils/katalog_menu.dart');
      final punya = <String>{};
      for (final m
          in RegExp(r"'(\w+)': \[(.*?)\]", dotAll: true).allMatches(katalog)) {
        if (m.group(2)!.contains("'Pending Payment'")) punya.add(m.group(1)!);
      }
      expect(punya, {'kasir', 'admin', 'owner'});

      final sql = baca('supabase/push_pending_payment_qris.sql');
      for (final p in punya) {
        expect(sql, contains("'$p'"), reason: '$p tidak dibangunkan push-nya');
      }
    });

    test('owner punya penotifikasi, bukan cuma kasir dan admin', () {
      // Owner tidak masuk cabang mana pun, jadi apa pun yang diperbaiki
      // di dalam OrderNotifier tidak pernah sampai kepadanya — dan owner
      // yang memegang warungnya sendiri justru yang paling sering
      // memegang Pending Payment.
      final binder = baca('lib/widgets/order_notification_binder.dart');
      final blok = binder.substring(binder.indexOf('OrderNotifier? _buildNotifier'));
      expect(blok, contains('auth.isOwner'));
    });

    test('bunyinya di aplikasi yang sedang terbuka, bukan cuma di latar', () {
      // Notifikasi push hanya muncul sendiri kalau aplikasinya di latar.
      // Yang sedang memandangi layarnya tidak mendengar apa pun kecuali
      // aliran realtime yang membunyikannya.
      final notifier = baca('lib/services/order_notifier.dart');
      final mine = notifier.substring(notifier.indexOf('bool _isMine('));
      expect(mine.substring(0, mine.indexOf('case OrderWatchRole.customer')),
          contains('o.isAwaitingPayment'));

      final baru = notifier.substring(notifier.indexOf('void _announceNew('));
      expect(baru, contains('Pesanan menunggu dibayar'));
      expect(baru, contains("'qris_static' =>"));
    });
  });
}
