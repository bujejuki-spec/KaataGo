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
    expect(s, contains("if (dart.library.io) 'mesin_wajah_perangkat.dart'"));

    // Layar absensinya sendiri tidak boleh mengimpor tflite langsung.
    final layar = File('lib/screens/absensi_screen.dart').readAsStringSync();
    expect(layar, isNot(contains('google_mlkit')));
  });

  // Kotak kosong di PDF tidak pernah muncul sebagai galat. Yang
  // menemukannya orang yang membuka berkasnya — dan untuk daftar
  // transfer gaji, kotak kosong di tengah nomor rekening adalah
  // kekeliruan yang mahal.
  group('PDF tidak menghasilkan kotak kosong', () {
    // Font bawaan PDF (Helvetica) cuma menjamin Latin-1.
    final diluarLatin1 = RegExp(r'[^\x00-\xFF]');

    /// Teks di dalam tanda kutip pada sebuah berkas Dart.
    Iterable<String> teksDart(String jalur) {
      final isi = File(jalur).readAsStringSync();
      // Komentar dibuang: yang dicetak ke PDF cuma literalnya.
      final tanpaKomentar =
          isi.split('\n').where((b) => !b.trimLeft().startsWith('//')).join('\n');
      return RegExp(r"'((?:[^'\\\n]|\\.)*)'")
          .allMatches(tanpaKomentar)
          .map((m) => m.group(1)!);
    }

    for (final berkas in [
      'lib/utils/absensi_export.dart',
      'lib/utils/slip_gaji_pdf.dart',
    ]) {
      test('$berkas memakai huruf yang dijamin ada', () {
        final nakal = teksDart(berkas)
            .where((t) => diluarLatin1.hasMatch(t))
            .toList();
        expect(nakal, isEmpty,
            reason: 'huruf ini keluar sebagai kotak kosong di PDF: '
                '${nakal.join(' | ')}');
      });
    }

    // Nama merchant dan nama karyawan diketik orang dari papan ketik
    // ponsel, yang gemar menyisipkan tanda kutip melengkung tanpa
    // diminta. Itu tidak bisa disaring di sini — jadi fontnya dipasang.
    test('fontnya dipasang, dan gagal memuatnya tidak membatalkan cetakan',
        () {
      final ekspor =
          File('lib/utils/absensi_export.dart').readAsStringSync();
      expect(ekspor, contains('PdfGoogleFonts.notoSansRegular()'));
      expect(ekspor, contains('Future<pw.ThemeData?> temaPdf()'));
      final blok = ekspor.substring(ekspor.indexOf('Future<pw.ThemeData?> temaPdf'));
      expect(blok.substring(0, blok.indexOf('\n}')), contains('catch (_)'));

      final slip = File('lib/utils/slip_gaji_pdf.dart').readAsStringSync();
      expect(slip, contains('theme: tema'));
    });

    // Kode bank yang dipisah em dash keluar sebagai kotak di tengah
    // nomor rekening.
    test('kode bank di PDF memakai pemisah biasa', () {
      expect(bankBerkode('BCA', pemisah: ' - '), '014 - BCA');
      for (final berkas in [
        'lib/utils/absensi_export.dart',
        'lib/utils/slip_gaji_pdf.dart',
      ]) {
        final isi = File(berkas).readAsStringSync();
        if (!isi.contains('bankBerkode(')) continue;
        expect(isi, contains("pemisah: ' - '"), reason: berkas);
      }
    });
  });

  group('jam kerja dari absen masuk sampai pulang', () {
    BarisAbsensi baris({DateTime? masuk, DateTime? pulang}) => BarisAbsensi(
          id: '1',
          email: 'a@b.c',
          tanggal: DateTime(2026, 9, 14),
          status: StatusAbsen.hadir,
          masukAt: masuk,
          pulangAt: pulang,
        );

    test('dihitung dari selisih keduanya', () {
      final b = baris(
        masuk: DateTime.utc(2026, 9, 14, 1),
        pulang: DateTime.utc(2026, 9, 14, 8, 45),
      );
      expect(b.lamaTeks, '7j 45m');
      expect(b.lamaJam, closeTo(7.75, 0.001));
    });

    // Yang belum pulang belum punya jam kerja — bukan nol, karena nol
    // terbaca sebagai "datang lalu langsung pulang".
    test('belum pulang berarti belum ada angkanya', () {
      expect(baris(masuk: DateTime.utc(2026, 9, 14, 1)).lamaTeks, isNull);
      expect(baris().lamaTeks, isNull);
    });

    // Jam pulang yang lebih awal daripada jam masuk cuma bisa datang
    // dari data yang kacau; yang keluar jangan angka minus.
    test('selisih minus tidak ditampilkan', () {
      final b = baris(
        masuk: DateTime.utc(2026, 9, 14, 9),
        pulang: DateTime.utc(2026, 9, 14, 8),
      );
      expect(b.lamaTeks, isNull);
    });

    test('tampil di layar karyawan, layar atasan, dan kedua ekspor', () {
      for (final jalur in [
        'lib/screens/absensi_screen.dart',
        'lib/screens/absensi_report_screen.dart',
        'lib/utils/absensi_export.dart',
      ]) {
        final isi = File(jalur).readAsStringSync();
        expect(isi, anyOf(contains('lamaTeks'), contains('lamaJam')),
            reason: jalur);
      }
    });

    // Lembar XLSX dipakai menjumlah. Teks "7j 45m" berhenti bisa
    // dijumlahkan di Excel.
    test('XLSX menulisnya sebagai angka, PDF sebagai teks', () {
      final e = File('lib/utils/absensi_export.dart').readAsStringSync();
      expect(e, contains('SelXlsx.angka(double.parse(a.lamaJam'));
      expect(e, contains('a.lamaTeks ?? '));
    });
  });

  // Radiusnya ada supaya kasir dan dapur benar-benar berada di merchant.
  // Admin dan Finance sering tidak — satu kantor pusat bisa mengurus
  // beberapa merchant sekaligus.
  group('radius absen', () {
    final sql = File('supabase/wajah_geometri.sql').readAsStringSync();

    test('Admin dan Finance tidak diikat radius', () {
      expect(sql, contains("not in ('admin', 'finance')"));
      expect(sql, contains('v_wajib_dekat and v_jarak >'));
    });

    // Yang dilepas cuma penolakannya, bukan pencatatannya — kalau suatu
    // hari ada yang perlu ditelusuri, yang dibutuhkan justru titik itu.
    test('titik GPS-nya tetap dicatat', () {
      final blok = sql.substring(sql.indexOf('v_wajib_dekat :='));
      expect(blok, contains('masuk_jarak_m'));
      expect(blok, contains('masuk_lat'));
    });

    test('peran lain tetap diikat', () {
      // Kasir, chef, dan owner tidak disebut di pengecualiannya.
      final blok = sql.substring(sql.indexOf('v_wajib_dekat :='),
          sql.indexOf('v_wajib_dekat and'));
      for (final peran in ['kasir', 'chef', 'owner']) {
        expect(blok, isNot(contains("'$peran'")), reason: peran);
      }
    });
  });

  // Absen wajah memakai FaceNet, model terlatih yang dijalankan di
  // ponsel.
  //
  // Kelompok tes yang dulu berdiri di sini menjaga cara sebelumnya —
  // mencocokkan BENTUK wajah dari kontur ML Kit. Semuanya hijau, dan
  // semuanya salah: yang mereka periksa adalah apakah kodenya ditulis
  // seperti yang saya niatkan, bukan apakah ia membedakan orang.
  //
  // Tiga wajah sungguhan membantahnya dalam satu query — tiga orang yang
  // berbeda berjarak 0,85-0,88 dari skala 0-1. Tesnya tidak berkedip.
  //
  // Penggantinya ada di test/wajah_facenet_test.dart, dan yang dijaganya
  // dipilih justru dari hal-hal yang pernah gagal DIAM-DIAM.
  group('pencocokan wajah dengan model terlatih', () {
    final mesin =
        File('lib/utils/mesin_wajah_perangkat.dart').readAsStringSync();
    final sql = File('supabase/wajah_facenet.sql').readAsStringSync();

    test('modelnya dimuat dari bundel aplikasi, bukan diunduh', () {
      // Diunduh berarti absen menunggu jaringan warung di pagi hari, dan
      // gagal unduh berarti orangnya tidak bisa masuk kerja.
      expect(mesin, contains('Interpreter.fromAsset'));
      expect(mesin, contains("assets/face/facenet.tflite"));
    });

    // Bukan sekadar dibagi 255. Penyeragaman per gambar inilah yang
    // membuat wajah yang sama di ruangan gelap dan di bawah matahari
    // menghasilkan sidik yang berdekatan — tanpanya yang dibandingkan
    // lebih banyak cahayanya daripada orangnya.
    test('gambarnya diseragamkan sebelum masuk model', () {
      expect(mesin, contains('(piksel[j] - rata) / simpangan'));
      // Lantai bawahnya menjaga gambar satu warna — tutup lensa, ruangan
      // gelap gulita — dari membagi dengan nol.
      expect(mesin, contains('math.max(math.sqrt('));
    });

    test('ukuran masukan dan panjang sidiknya sesuai modelnya', () {
      expect(mesin, contains('_sisi = 160'));
      expect(mesin, contains('_panjangSidik = 128'));
      expect(mesin, contains('reshape([1, _sisi, _sisi, 3])'));
    });

    // Sidik FaceNet tidak dinormalkan panjangnya, jadi yang dipakai
    // kosinus — bukan jarak bentuk seperti cara yang lama.
    test('dibandingkan dengan kosinus', () {
      expect(sql, contains("like 'facenet-%' then _mirip_wajah"));
    });

    // Ada pita di antara "jelas orangnya" dan "jelas bukan". Menolak
    // semua yang jatuh di situ mengunci orang dari pekerjaannya karena
    // cahaya pagi yang berbeda.
    test('yang ragu ditandai, bukan ditolak', () {
      expect(sql, contains('_ambang_yakin(v_wajah.model)'));
      final blok = sql.substring(sql.indexOf('v_ragu := '));
      expect(blok.substring(0, 120), contains('_ambang_yakin'));
    });

    // Ambangnya masih akan disetel begitu terlihat sebaran nyatanya. Ia
    // harus bisa disetel tanpa merilis APK — terutama karena angka yang
    // ditebak dari laboratorium sudah sekali terbukti keliru.
    test('ambangnya berdiri sebagai fungsi yang bisa disetel', () {
      for (final f in ['_ambang_facenet', '_ambang_facenet_yakin']) {
        expect(sql, contains('create or replace function $f()'), reason: f);
      }
    });
  });

  // Kasir dan Chef sengaja tidak punya hak BACA di ember `absensi` —
  // isinya foto wajah dan surat sakit rekan-rekannya. Tapi layanan
  // Storage membaca baris objeknya lebih dulu saat upsert, jadi
  // `upsert: true` membuat mereka kena 403 sebelum sempat menulis apa
  // pun. Galatnya tidak menyebut izin sama sekali.
  test('unggahan ke ember tertutup tidak memakai upsert', () {
    for (final jalur in [
      'lib/db/absensi_repository.dart',
      'lib/db/paket_langganan_repository.dart',
    ]) {
      final isi = File(jalur).readAsStringSync();
      // Komentar boleh menyebutnya; yang dilarang kodenya.
      final kode = isi
          .split('\n')
          .where((b) => !b.trimLeft().startsWith('//'))
          .join('\n');
      expect(kode, isNot(contains('upsert: true')),
          reason: '$jalur memakai upsert — Kasir dan Chef akan kena 403');
    }
  });

  // Yang menulis boleh semua peran; yang membaca hanya yang memeriksa
  // absensi.
  test('kebijakan embernya menulis untuk semua peran, baca untuk atasan', () {
    final sql = File('supabase/absensi_payroll.sql').readAsStringSync();
    final tulis = sql.substring(sql.indexOf('create policy "absensi: tulis'));
    expect(tulis.substring(0, 600), contains("'kasir', 'chef'"));

    final baca = sql.substring(sql.indexOf('create policy "absensi: baca'));
    final blokBaca = baca.substring(0, 900);
    expect(blokBaca, contains("'owner', 'admin', 'finance'"));
    expect(blokBaca, isNot(contains("'kasir'")));

    // KaataGo Admin bukan karyawan resto mana pun, tapi dialah yang
    // wajib memeriksa bukti transfer langganan sebelum menyetujui
    // pembayaran. Tanpa ini yang dia lihat "Gagal dimuat", dan
    // satu-satunya jalan yang tersisa menyetujui tanpa melihat bukti.
    expect(blokBaca, contains('is_super_admin()'));

    // Menulis dan menimpa tidak ikut: KaataGo Admin tidak perlu menaruh
    // berkas di ember milik merchant.
    final tulisBlok = sql.substring(sql.indexOf('create policy "absensi: tulis'));
    expect(tulisBlok.substring(0, 600), isNot(contains('is_super_admin()')));
  });

  // Ember `absensi` sengaja tidak publik: isinya foto wajah karyawan dan
  // surat keterangan sakit.
  //
  // getPublicUrl() tetap mengembalikan alamat untuk ember tertutup —
  // alamat yang selalu ditolak. Tidak ada galat saat menyimpannya, dan
  // yang terlihat cuma kotak "Gagal dimuat" di layar orang yang sedang
  // memutuskan gaji.
  group('gambar dari ember tertutup', () {
    test('yang disimpan jalur berkasnya, bukan alamat publik', () {
      for (final jalur in [
        'lib/db/absensi_repository.dart',
        'lib/db/paket_langganan_repository.dart',
      ]) {
        expect(File(jalur).readAsStringSync(), isNot(contains('getPublicUrl')),
            reason: jalur);
      }
    });

    test('ditampilkan lewat URL bertanda tangan', () {
      final w = File('lib/widgets/gambar_bertanda.dart').readAsStringSync();
      expect(w, contains('createSignedUrl('));
      // Tanda yang tersimpan di basis data akan kedaluwarsa, dan
      // barisnya berubah jadi kotak kosong tanpa ada yang mengubah
      // apa pun. Jadi tandanya dibuat saat gambarnya mau ditampilkan.
      expect(w, contains('class GambarBertanda'));
    });

    // Baris lama terlanjur menyimpan URL publik yang tidak pernah bisa
    // dibuka. Jalurnya masih ada di dalam alamat itu.
    test('alamat lama dipungut kembali jalurnya', () {
      final w = File('lib/widgets/gambar_bertanda.dart').readAsStringSync();
      expect(w, contains("'/object/public/\$ember/'"));
      expect(w, contains("indexOf('?')"));
    });

    test('layar yang menampilkannya memakai widget itu', () {
      for (final jalur in [
        'lib/screens/absensi_report_screen.dart',
        'lib/screens/pengajuan_langganan_screen.dart',
      ]) {
        final isi = File(jalur).readAsStringSync();
        expect(isi, contains('GambarBertanda('), reason: jalur);
        expect(isi, isNot(contains('Image.network(')), reason: jalur);
      }
    });
  });

  // Pencocokan otomatisnya cuma membandingkan bentuk wajah, dan bentuk
  // wajah dua orang bisa mirip. Yang tidak mirip wajahnya sendiri — dan
  // itu cuma bisa dilihat kalau kedua fotonya bersebelahan.
  group('foto acuan disandingkan dengan foto absen', () {
    final layar =
        File('lib/screens/absensi_report_screen.dart').readAsStringSync();

    test('layar Absensi Karyawan bisa membandingkan keduanya', () {
      expect(layar, contains('class _DialogBandingFoto'));
      expect(layar, contains("judul: 'Acuan'"));
      expect(layar, contains("judul: 'Absen hari itu'"));
    });

    test('hari yang ragu ditandai di kartu orangnya', () {
      expect(layar, contains('hari perlu dilihat'));
    });

    // employee_faces sengaja tanpa satu pun kebijakan SELECT — yang
    // dibuka cuma URL fotonya, dan cuma untuk yang memeriksa absensi.
    test('foto acuan dibuka lewat fungsi, bukan tabelnya', () {
      final sql = File('supabase/wajah_geometri.sql').readAsStringSync();
      expect(sql, contains('create or replace function foto_acuan_wajah'));
      expect(sql, contains("array['owner', 'admin', 'finance']"));
      expect(File('lib/db/absensi_repository.dart').readAsStringSync(),
          contains("rpc('foto_acuan_wajah'"));
    });
  });

  // Kegagalan yang paling berbahaya bukan model yang menolak semua
  // orang — itu langsung ketahuan. Yang berbahaya model yang menerima
  // semua orang, karena tidak ada yang mengeluh.
  group('wajah kembar ditolak saat pendaftaran', () {
    final sql = File('supabase/wajah_tidak_kembar.sql').readAsStringSync();

    test('dibandingkan dengan rekan satu merchant', () {
      expect(sql, contains('_mirip_wajah(embedding, p_embedding)'));
      expect(sql, contains('v_kembar.skor >= _ambang_kembar()'));
    });

    // Sidik dari dua model berbeda memang tidak sebanding.
    test('hanya sidik dari model yang sama yang dibandingkan', () {
      expect(sql, contains("model = coalesce(p_model, 'mobilefacenet-192')"));
    });

    // Menyebutkan emailnya membocorkan siapa saja yang sudah terdaftar
    // kepada siapa pun yang mau memancingnya.
    test('tidak menyebut wajah siapa yang mirip', () {
      final blok = sql.substring(sql.indexOf('terlalu mirip'));
      expect(blok.substring(0, 200),
          isNot(contains('v_kembar.employee_email')));
    });

    // Menolak pendaftaran orang yang wajahnya kebetulan mirip
    // saudaranya mengunci dia sampai ada yang turun tangan.
    test('ambangnya lebih longgar daripada ambang absen', () {
      expect(sql, contains('select 0.90::double precision'));
      final absen = File('supabase/absensi_payroll.sql').readAsStringSync();
      expect(absen, contains('select 0.75::double precision'));
    });
  });

  // Menyuruh orang memperbarui aplikasi berarti menyuruhnya mengerjakan
  // sesuatu yang tidak akan menolong, lalu menyimpulkan sendiri bahwa
  // aplikasinya rusak saat pesannya tetap sama.
  test('tanpa model, pesannya tidak menyuruh memperbarui aplikasi', () {
    final layar = File('lib/screens/absensi_screen.dart').readAsStringSync();
    expect(layar, isNot(contains('Perbarui aplikasinya lewat Kotak Masuk')));
    expect(layar, contains('belum diaktifkan KaataGo'));
  });

  // Yang sedang sakit di rumah tidak bisa berdiri di depan merchant, dan
  // servernya memang tidak menuntut wajah maupun GPS untuk itu.
  // Menyembunyikannya di balik pemeriksaan model berarti orang yang
  // sakit hari ini tidak punya cara menyatakannya sama sekali.
  test('tanpa model, izin dan sakit tetap bisa diajukan', () {
    final layar = File('lib/screens/absensi_screen.dart').readAsStringSync();
    expect(layar, contains('class _KartuTidakMasukSaja'));

    final blok = layar.substring(
      layar.indexOf('else if (!_modelSiap)'),
      layar.indexOf('else if (!_wajahTerdaftar)'),
    );
    expect(blok, contains('_KartuTidakMasukSaja('));
    expect(blok, contains('onTidakMasuk: _ajukanTidakMasuk'));
  });

  // Gambar yang boleh dipilih dari galeri adalah gambar yang bisa
  // dipilih dari foto teman.
  test('wajahnya difoto kamera dalam aplikasi, bukan dipilih dari galeri', () {
    // Dulu tes ini menuntut `preferredCameraDevice: CameraDevice.front`,
    // dan itu memang tertulis di kodenya — tapi ia cuma SARAN di dalam
    // ACTION_IMAGE_CAPTURE, dan aplikasi kamera pabrikan mengabaikannya.
    // Tesnya hijau; kameranya tetap membuka lensa belakang.
    //
    // Sekarang kameranya dibuka sendiri, jadi tidak ada yang bisa
    // mengabaikan pilihannya.
    final layar = File('lib/screens/absensi_screen.dart').readAsStringSync();
    final blok = layar.substring(layar.indexOf('Future<HasilWajah?> _pindaiWajah'));
    final pindai = blok.substring(0, blok.indexOf('\n  }'));
    expect(pindai, contains('ambilFotoWajah(context'));
    expect(pindai, isNot(contains('ImagePicker()')));

    final kamera = File('lib/screens/kamera_wajah_screen.dart').readAsStringSync();
    expect(kamera, contains('CameraLensDirection.front'));
    // Tablet kasir kadang tidak punya kamera depan. Menolak membuka
    // kamera sama sekali di situ berarti absennya mati total.
    expect(kamera, contains('orElse: () => daftar.first'));
    // Bingkai kepala, supaya orangnya tahu harus berdiri di mana.
    expect(kamera, contains('_PanduanKepala'));
  });

  testWidgets('semua peran punya menu Absensi di katalog UAM', (tester) async {
    final katalog = File('lib/utils/katalog_menu.dart').readAsStringSync();
    // Enam peran, masing-masing satu entri 'Absensi' — HR ikut sejak
    // peran itu ada.
    expect("'Absensi',".allMatches(katalog).length, 6);
    expect("'Absensi Karyawan',".allMatches(katalog).length, 4);
    // Payroll TETAP dua: Owner dan Finance.
    //
    // HR mengurus kehadiran, bukan bayarannya. Yang mencatat kehadiran
    // tidak boleh jadi orang yang sama dengan yang menentukan gaji —
    // kalau angka ini naik jadi tiga, bacalah dulu catatan di
    // lib/screens/hr_home_screen.dart.
    expect("'Payroll',".allMatches(katalog).length, 2);
    debugPrint('katalog terverifikasi');
  });
}
