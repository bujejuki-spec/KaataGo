import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/bank_account.dart';
import 'package:pos_app/utils/daftar_bank.dart';

/// Rekening berdiri sendiri, tidak menempel di satu resto.
///
/// Alasan sebenarnya bukan kerapian: sebuah mutasi bank masuk ke
/// REKENING, bukan ke resto. Selama rekeningnya cuma tiga kolom yang
/// menempel di baris settings tiap cabang, tidak ada satu pun tempat
/// untuk menautkan mutasi itu — dan rekonsiliasi mustahil dikerjakan.
void main() {
  const rek = BankAccount(
    id: 'a1',
    bankName: 'BCA',
    accountNumber: '1234567890',
    accountHolder: 'PT Kaata Nusantara',
    label: 'BCA Operasional',
  );

  group('cara membacanya', () {
    // Nomor rekening tidak pernah dihafal siapa pun, dan daftar berisi
    // empat nomor tanpa nama menuntut yang memilihnya membaca digit satu
    // per satu.
    test('sebutan dipakai kalau ada', () {
      expect(rek.tampilan, 'BCA Operasional');
    });

    test('tanpa sebutan, nama banknya yang dipakai', () {
      expect(rek.copyWith(label: '').tampilan, 'BCA');
    });

    test('ringkasnya menyebut ketiganya', () {
      expect(rek.ringkas, contains('BCA'));
      expect(rek.ringkas, contains('1234567890'));
      expect(rek.ringkas, contains('PT Kaata Nusantara'));
    });
  });

  group('bentuk datanya', () {
    // is_primary sifatnya per resto, bukan milik rekeningnya sendiri:
    // rekening yang utama di cabang satu bisa jadi cadangan di cabang
    // lain. Karena itu ia tidak ikut ditulis saat menyimpan rekeningnya.
    test('utama tidak ikut disimpan di baris rekeningnya', () {
      expect(rek.copyWith(isPrimary: true).toMap().containsKey('is_primary'),
          isFalse);
    });

    test('sebutan kosong disimpan sebagai null, bukan string kosong', () {
      expect(rek.copyWith(label: '   ').toMap()['label'], isNull);
    });

    test('dibaca dari join berikut penanda utamanya', () {
      final dari = BankAccount.fromMap({
        'id': 'a1',
        'bank_name': 'BCA',
        'account_number': '1234567890',
        'account_holder': 'PT Kaata',
        'is_primary': true,
      });
      expect(dari.isPrimary, isTrue);
    });
  });

  group('aturannya ditegakkan basis data', () {
    final sql =
        File('supabase/rekening_perusahaan.sql').readAsStringSync();

    // Nomor yang sama di bank yang sama adalah rekening yang SAMA. Dua
    // barisnya berarti dua tempat menautkan mutasi yang sebenarnya satu.
    test('satu rekening tercatat sekali', () {
      expect(sql, contains('create unique index if not exists bank_accounts_unik'));
      expect(sql, contains('(lower(bank_name), account_number)'));
    });

    // Tanpa batas ini, "rekening utama" jadi pertanyaan yang jawabannya
    // bergantung urutan baris.
    test('tepat satu rekening utama per resto', () {
      expect(sql, contains('resto_bank_accounts_satu_utama'));
      expect(sql, contains('where is_primary'));
    });

    // Mengganti nomor rekening berarti mengganti ke mana uang laci
    // pergi, dan itu bukan keputusan yang dibuat sambil melayani antrean.
    test('kasir membaca, tidak menulis', () {
      // Dimulai dari create policy-nya, bukan dari drop di atasnya —
      // baris drop berakhir di titik koma pertama dan memotong blok
      // yang justru mau diperiksa.
      final mulai =
          sql.indexOf('create policy "bank_accounts: finance write"');
      final blok = sql.substring(mulai, sql.indexOf(';', mulai));
      expect(blok, contains("array['owner', 'finance']"));
      expect(blok, isNot(contains('kasir')));
    });

    // Kolom lama tidak dihapus: aplikasi versi lama membacanya dan tidak
    // tahu apa-apa tentang tabel ini.
    test('kolom lama di settings dipertahankan dulu', () {
      expect(sql, isNot(contains('alter table settings drop column')));
    });
  });

  // Nama bank diketik tangan berarti "BCA", "Bank BCA", dan "bca "
  // adalah tiga bank berbeda bagi basis data — dan keunikan rekening
  // ditentukan pasangan nama bank dan nomornya. Rekening yang sama
  // berakhir sebagai tiga baris, masing-masing dengan mutasi tertaut
  // sebagian, dan tidak ada satu pun galat yang muncul.
  group('bank dipilih dari daftar', () {
    test('daftarnya tidak kosong dan memuat bank besar', () {
      expect(kDaftarBank, contains('BCA'));
      expect(kDaftarBank, contains('Mandiri'));
      expect(kDaftarBank, contains('BRI'));
    });

    test('tidak ada nama kembar', () {
      final huruf = kDaftarBank.map((b) => b.toLowerCase()).toList();
      expect(huruf.toSet().length, kDaftarBank.length);
    });

    // Data lama diketik sebelum daftar ini ada. Yang tidak ada di daftar
    // disisipkan apa adanya — kalau tidak, menyunting rekening lama
    // diam-diam mengganti banknya jadi yang pertama di daftar.
    test('nilai lama di luar daftar tetap bisa dipilih', () {
      final pilihan = daftarBankUntuk('Bank Antah Berantah');
      expect(pilihan.first, 'Bank Antah Berantah');
      expect(pilihan.length, kDaftarBank.length + 1);
    });

    test('nilai yang sudah ada tidak digandakan', () {
      expect(daftarBankUntuk('BCA').length, kDaftarBank.length);
    });

    // "bca" dari data lama harus terpilih sebagai "BCA", bukan tampil
    // sebagai pilihan kedua yang mirip.
    test('besar-kecil huruf diabaikan saat mencocokkan', () {
      expect(bankTerpilih('bca', kDaftarBank), 'BCA');
      expect(bankTerpilih('  Mandiri  ', kDaftarBank), 'Mandiri');
      expect(bankTerpilih('', kDaftarBank), isNull);
    });
  });
}
