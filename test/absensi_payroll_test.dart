import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:pos_app/models/absensi.dart';
import 'package:pos_app/utils/absensi_export.dart';
import 'package:pos_app/utils/kode_bank.dart';

/// Absensi wajah berlokasi, dan payroll yang menghitung darinya.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('periode gaji', () {
    // Yang dibayar tanggal 25 adalah kerja sampai tanggal 25. Memakai
    // bulan kalender berarti membayar lima hari yang belum dikerjakan.
    test('berakhir di tanggal gajian, bukan akhir bulan', () {
      const aturan = AturanGaji(tanggalGajian: 25);
      final p = aturan.periodeUntuk(DateTime(2026, 6, 1));
      expect(p.mulai, DateTime(2026, 5, 26));
      expect(p.akhir, DateTime(2026, 6, 25));
    });

    test('gajian tanggal 1 tetap menghasilkan periode sebulan penuh', () {
      const aturan = AturanGaji(tanggalGajian: 1);
      final p = aturan.periodeUntuk(DateTime(2026, 6, 1));
      expect(p.mulai, DateTime(2026, 5, 2));
      expect(p.akhir, DateTime(2026, 6, 1));
    });

    // Januari mengambil periodenya dari Desember tahun sebelumnya.
    test('melewati pergantian tahun', () {
      const aturan = AturanGaji(tanggalGajian: 25);
      final p = aturan.periodeUntuk(DateTime(2026, 1, 1));
      expect(p.mulai, DateTime(2025, 12, 26));
      expect(p.akhir, DateTime(2026, 1, 25));
    });
  });

  group('kode bank', () {
    // Kode bank yang salah tidak pernah muncul sebagai galat: uangnya
    // terkirim, dan yang ketahuan belakangan cuma bahwa gajinya tidak
    // sampai.
    test('bank besar punya sandi BI-nya', () {
      expect(kodeBank('BCA'), '014');
      expect(kodeBank('Mandiri'), '008');
      expect(kodeBank('BRI'), '002');
      expect(kodeBank('BNI'), '009');
      expect(kodeBank('BSI'), '451');
    });

    // Rekening lama diketik tangan sebelum daftar banknya ada.
    test('dicocokkan tanpa memperhatikan besar-kecil huruf dan spasi', () {
      expect(kodeBank('bca '), '014');
      expect(kodeBank('  MANDIRI'), '008');
    });

    // Dompet digital tidak punya sandi bank BI. Yang tidak punya kode
    // dibiarkan null, bukan diisi tebakan.
    test('dompet digital memang tidak punya kode', () {
      for (final e in ['GoPay', 'OVO', 'DANA', 'ShopeePay', 'LinkAja']) {
        expect(kodeBank(e), isNull, reason: e);
        expect(bankBerkode(e), e);
      }
    });

    test('bank yang tidak dikenal tidak mengarang kode', () {
      expect(kodeBank('Bank Antah Berantah'), isNull);
    });

    test('kosong tidak jadi baris tanpa nama', () {
      expect(bankBerkode(null), '-');
      expect(bankBerkode('  '), '-');
    });

    test('digabung untuk dibaca manusia', () {
      expect(bankBerkode('BCA'), '014 — BCA');
    });
  });

  group('nama berkas ekspor', () {
    // Tiga berkas bernama sama yang dibedakan "(1)" dan "(2)" adalah
    // tiga berkas yang harus dibuka satu per satu untuk tahu mana yang
    // bulan lalu.
    test('memuat nama merchant dan periodenya', () {
      expect(
        namaBerkasAbsensi('Warung Bu Ani', DateTime(2026, 6, 1)),
        'Absensi & Payroll Karyawan Warung Bu Ani Juni 2026',
      );
    });

    // "&" bagian dari judul yang diminta, dan sah di Android, Windows,
    // maupun macOS.
    test('ampersand dipertahankan', () {
      expect(namaBerkasAbsensi('X', DateTime(2026, 1, 1)), startsWith('Absensi & '));
    });

    // Karakter yang memang dilarang nama berkas tetap dibuang — kalau
    // tidak, penyimpanannya gagal tanpa alasan yang bisa dibaca.
    test('garis miring di nama merchant dibuang', () {
      final nama = namaBerkasAbsensi('Kopi/Teh: Enak', DateTime(2026, 6, 1));
      expect(nama, isNot(contains('/')));
      expect(nama, isNot(contains(':')));
      expect(nama, 'Absensi & Payroll Karyawan Kopi Teh Enak Juni 2026');
    });

    test('merchant tanpa nama tidak menghasilkan spasi ganda', () {
      expect(namaBerkasAbsensi('   ', DateTime(2026, 6, 1)),
          'Absensi & Payroll Karyawan Merchant Juni 2026');
    });
  });

  group('baris payroll', () {
    test('gaji nol dibedakan dari gaji yang belum disetel', () {
      const belum = BarisPayroll(
        email: 'a@b.c', nama: 'A', peran: 'kasir',
        gajiPokok: 0, tunjangan: 0, hariKerja: 20,
        hadir: 0, izin: 0, sakit: 0, cuti: 0, alpa: 0, hariPotong: 0,
        potonganAbsen: 0, potonganBpjsKesehatan: 0, potonganBpjsTk: 0,
        gajiBersih: 0,
      );
      expect(belum.belumDisetel, isTrue);

      const sudah = BarisPayroll(
        email: 'a@b.c', nama: 'A', peran: 'kasir',
        gajiPokok: 5600000, tunjangan: 0, hariKerja: 20,
        hadir: 15, izin: 0, sakit: 0, cuti: 0, alpa: 5, hariPotong: 5,
        potonganAbsen: 1400000, potonganBpjsKesehatan: 0, potonganBpjsTk: 0,
        gajiBersih: 4200000,
      );
      expect(sudah.belumDisetel, isFalse);
      expect(sudah.totalPotongan, 1400000);
    });
  });

  // ── Yang dijaga server ────────────────────────────────────────────
  group('aturan yang ditegakkan server', () {
    final sql = File('supabase/absensi_payroll.sql').readAsStringSync();

    // Yang bisa mengirim "cocok" bisa mengirimnya tanpa membuka kamera
    // sama sekali.
    test('wajahnya dicocokkan di server, bukan dipercaya dari aplikasi', () {
      expect(sql, contains('_mirip_wajah(v_wajah.embedding, p_embedding)'));
      expect(sql, contains('if v_skor < _ambang_wajah() then'));
    });

    // Sidik wajah yang bisa dibaca aplikasi adalah sidik yang bisa
    // dikirim balik sebagai "hasil pemindaian".
    test('sidik terdaftar tidak bisa dibaca aplikasi', () {
      expect(sql, contains('alter table employee_faces enable row level security'));
      // Tidak ada satu pun kebijakan SELECT untuk tabel itu.
      expect(sql, isNot(contains('create policy "employee_faces')));
    });

    // Titik GPS yang cuma diperiksa di HP adalah titik yang ditentukan
    // HP.
    test('jaraknya dihitung server dan menolak yang terlalu jauh', () {
      expect(sql, contains('v_jarak := _jarak_meter('));
      expect(sql, contains('if v_jarak > coalesce(v_setelan.radius_absen_m, 150)'));
    });

    // Titip absen cuma butuh mendaftar ulang dengan wajah temannya pagi
    // itu lalu mengembalikannya sore hari.
    test('wajah tidak bisa didaftar ulang sendiri', () {
      expect(sql, contains('Wajahmu sudah terdaftar.'));
      expect(sql, contains('Hanya Owner dan Admin yang bisa mereset wajah.'));
    });

    // Tombol yang ditekan dua kali karena jaringannya lambat menjadi dua
    // kali hadir — dan orang itu dibayar untuk hari yang sama dua kali.
    test('satu baris per orang per hari', () {
      expect(sql, contains('unique (resto_id, employee_email, tanggal)'));
    });

    // Absen jam tujuh pagi WIB adalah hari itu; disimpan UTC ia jatuh ke
    // tanggal kemarin.
    test('tanggalnya WIB', () {
      expect(sql, contains("(now() at time zone 'Asia/Jakarta')::date"));
    });

    // Angka merah yang dibaca sebagai utang karyawan ke merchant bukan
    // yang dimaksud siapa pun.
    test('gaji bersih tidak pernah minus', () {
      expect(sql, contains('greatest('));
      expect(sql, contains('0)::bigint'));
    });

    // Besaran gaji bukan angka yang perlu bisa diubah oleh setiap orang
    // yang bisa menambah menu.
    test('hanya Owner dan Finance yang menyetel gaji', () {
      expect(sql, contains('Hanya Owner dan Finance yang bisa membuka payroll.'));
      expect(
        sql,
        contains("is_resto_employee(resto_id, array['owner', 'finance'])"),
      );
    });

    // Rekapnya menolak siapa pun selain Owner dan Finance; melonggarkan
    // syaratnya supaya karyawan bisa masuk berarti melonggarkannya untuk
    // seluruh baris sekaligus.
    test('slip gaji karyawan lewat fungsinya sendiri', () {
      expect(sql, contains('create or replace function slip_gaji_saya('));
      final blok = sql.substring(sql.indexOf('function slip_gaji_saya('));
      expect(blok, contains("lower(employee_email) = v_email"));
    });

    // Yang sedang sakit di rumah memang tidak bisa berdiri di depan
    // merchant.
    test('tidak masuk tidak menuntut wajah maupun GPS', () {
      final blok = sql.substring(
        sql.indexOf('function ajukan_tidak_masuk('),
        sql.indexOf('revoke all on function absen_masuk'),
      );
      expect(blok, isNot(contains('_jarak_meter')));
      expect(blok, isNot(contains('_mirip_wajah')));
    });
  });

  // Absensi memang hanya di aplikasi HP — yang diperlukan kamera depan
  // dan GPS yang dibawa orangnya, bukan peramban di komputer kasir.
  test('mesin wajah diimpor bersyarat supaya web tetap bisa dibangun', () {
    final s = File('lib/utils/mesin_wajah.dart').readAsStringSync();
    expect(s, contains("export 'mesin_wajah_kosong.dart'"));
    expect(s, contains("if (dart.library.io) 'mesin_wajah_tflite.dart'"));

    // Layar absensinya sendiri tidak boleh mengimpor tflite langsung.
    final layar = File('lib/screens/absensi_screen.dart').readAsStringSync();
    expect(layar, isNot(contains('tflite_flutter')));
    expect(layar, isNot(contains('google_mlkit')));
  });

  // Gambar yang boleh dipilih dari galeri adalah gambar yang bisa
  // dipilih dari foto teman.
  test('wajahnya difoto kamera depan, bukan diambil dari galeri', () {
    final layar = File('lib/screens/absensi_screen.dart').readAsStringSync();
    final blok = layar.substring(layar.indexOf('Future<HasilWajah?> _pindaiWajah'));
    final pindai = blok.substring(0, blok.indexOf('\n  }'));
    expect(pindai, contains('source: ImageSource.camera'));
    expect(pindai, contains('preferredCameraDevice: CameraDevice.front'));
    expect(pindai, isNot(contains('ImageSource.gallery')));
  });

  testWidgets('semua peran punya menu Absensi di katalog UAM', (tester) async {
    final katalog = File('lib/utils/katalog_menu.dart').readAsStringSync();
    // Lima peran, masing-masing satu entri 'Absensi'.
    expect("'Absensi',".allMatches(katalog).length, 5);
    expect("'Absensi Karyawan',".allMatches(katalog).length, 3);
    expect("'Payroll',".allMatches(katalog).length, 2);
    debugPrint('katalog terverifikasi');
  });
}
