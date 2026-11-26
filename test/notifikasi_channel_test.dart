import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Channel notifikasi Android.
///
/// ── Kenapa dijaga tes yang membaca kode ──────────────────────────────
///
/// Channel hanya ada di perangkat Android sungguhan: `flutter test`
/// berjalan di mesin, tanpa satu pun API Android. Tidak ada cara memasang
/// NotificationService lalu memeriksa suaranya di sini.
///
/// Yang bisa dijaga justru hal-hal yang pernah salah diam-diam, dan
/// ketiganya memang pernah: id yang tidak berversi, channel yang diambil
/// lewat indeks sampai tertukar, dan suara yang diberikan ke channel
/// yang seharusnya senyap.
void main() {
  final kode =
      File('lib/services/notification_service.dart').readAsStringSync();

  /// Kode tanpa komentarnya.
  ///
  /// Komentar di berkas itu justru menceritakan kekeliruan yang pernah
  /// terjadi — termasuk menyebut `_channels[0]` yang dulu dipakai. Tanpa
  /// penyaringan ini, catatan sejarahnya sendiri yang memerahkan tes,
  /// dan jalan termudah membuatnya hijau adalah menghapus penjelasannya.
  final kodeSaja = kode
      .split('\n')
      .where((b) => !b.trimLeft().startsWith('//'))
      .join('\n');

  group('id channel berversi', () {
    // Android mengunci suara dan tingkat kepentingan sebuah channel pada
    // saat ia pertama kali dibuat. Tanpa versi di id-nya, perbaikan
    // apa pun di berkas ini tidak akan pernah sampai ke HP yang sudah
    // telanjur memasang versi lama — dan notifikasinya tetap senyap.
    test('setiap channel membawa versinya', () {
      final ids = RegExp(r"id: '(kaata_[a-z_]+)\$_versi'")
          .allMatches(kode)
          .map((m) => m.group(1)!)
          .toList();
      expect(ids.length, 5, reason: 'Ada channel yang id-nya tanpa versi.');
      expect(ids.toSet().length, 5, reason: 'Ada id channel yang kembar.');

      // Versinya harus benar-benar BERISI.
      //
      // Memeriksa adanya teks `\$_versi` saja tidak cukup: mengosongkan
      // nilainya jadi '' membuat id-nya kembali persis sama dengan yang
      // lama, channel lamanya yang bisu dipakai lagi, dan tes ini tetap
      // hijau. Saya menemukannya dengan merusaknya sendiri.
      final versi = RegExp(r"static const _versi = '([^']*)'").firstMatch(kode);
      expect(versi, isNotNull, reason: '_versi hilang.');
      expect(versi!.group(1), matches(RegExp(r'^v\d+$')),
          reason: 'Versinya kosong atau bukan vN — id-nya jadi sama '
              'dengan channel lama yang bisu.');
    });

    test('id versi lama dibuang, bukan ditinggalkan', () {
      // Yang tertinggal muncul sebagai channel kembar di Setelan HP:
      // satu yang lama dan bisu, satu yang baru, tanpa cara menebak mana
      // yang sedang dipakai.
      expect(kode, contains('_idUsang'));
      expect(kode, contains('deleteNotificationChannel'));
      for (final lama in const [
        'kaata_order_status',
        'kaata_new_order',
        'kaata_fund_review',
        'kaata_download',
        'kaata_announcement',
      ]) {
        expect(kode, contains("    '$lama',"), reason: lama);
      }
    });

    test('yang lama dibuang SESUDAH yang baru dibuat', () {
      // Urutan terbalik berarti kegagalan membuat channel baru
      // meninggalkan nol channel — dan nol channel berarti nol
      // notifikasi, bukan notifikasi yang bisu.
      expect(kode.indexOf('for (final id in _idUsang)'),
          greaterThan(kode.indexOf('for (final c in _channels)')));
    });
  });

  group('channel dipanggil dengan nama, bukan indeks', () {
    // Pengumuman dulu memakai `_channels[3]`, dan indeks 3 itu channel
    // unduhan. Kabar dari merchant keluar lewat kanal "Unduhan
    // Pembaruan" — dan yang membisukan progres unduhan ikut membisukan
    // pengumuman tanpa pernah tahu.
    test('tidak ada lagi akses lewat indeks', () {
      expect(kodeSaja, isNot(contains('_channels[')),
          reason: 'Akses lewat indeks adalah cara channel tertukar.');
    });

    test('tiap jenis notifikasi memakai channelnya sendiri', () {
      const pasangan = {
        'showOrderStatus': '_statusPesanan',
        'showNewOrder': '_pesananBaru',
        'showFundReview': '_hasilPengajuan',
        'showAnnouncement': '_pengumuman',
      };
      final dipakai = <String>[];
      pasangan.forEach((metode, channel) {
        final mulai = kode.indexOf('Future<void> $metode(');
        expect(mulai, greaterThan(-1), reason: '$metode hilang');
        final blok = kode.substring(mulai, mulai + 900);
        expect(blok, contains('channel: $channel'), reason: metode);
        dipakai.add(channel);
      });
      expect(dipakai.toSet().length, pasangan.length,
          reason: 'Ada dua jenis notifikasi berbagi satu channel.');
    });
  });

  group('hanya unduhan yang senyap', () {
    test('suara mengikuti channelnya, bukan disamaratakan', () {
      // Di Android 8+ setelan channel yang menang, bukan setelan per
      // notifikasi. Memberi suara ke semua channel membuat
      // `playSound: false` di notifikasi progres tidak pernah berlaku —
      // dan unduhan berbunyi tiap satu persen.
      expect(kode, contains('playSound: c.berbunyi'));
      expect(kode, contains('sound: c.berbunyi ? _sound : null'));
      expect(kode, isNot(contains('playSound: true,')),
          reason: 'Masih ada channel yang dipaksa berbunyi.');
    });

    test('unduhan ditandai senyap, selebihnya berbunyi', () {
      expect(kode, contains('berbunyi: false'));
      expect('berbunyi: false'.allMatches(kode).length, 1,
          reason: 'Hanya channel unduhan yang boleh senyap.');
      expect('berbunyi: true'.allMatches(kode).length, 4);
    });
  });
}
