import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/models/paket_langganan.dart';
import 'package:pos_app/utils/katalog_menu.dart';

/// Paket Basic dan Premium, masa percobaan, dan pengajuan berlangganan.
void main() {
  final sql = File('supabase/paket_langganan.sql').readAsStringSync();

  /// Isi sebuah array SQL yang ditulis sebagai `select array[...]`.
  List<String> arraySql(String namaFungsi) {
    final i = sql.indexOf('function $namaFungsi()');
    expect(i, greaterThan(-1), reason: '$namaFungsi tidak ada di SQL');
    final mulai = sql.indexOf('array[', i);
    final akhir = sql.indexOf(']', mulai);
    return RegExp(r"'([^']*)'")
        .allMatches(sql.substring(mulai, akhir))
        .map((m) => m.group(1)!)
        .toList();
  }

  group('daftar menu di SQL sejalan dengan katalog aplikasi', () {
    // Basis data tidak bisa melihat katalog menu di dalam APK. Yang
    // menjaga keduanya tetap sama adalah pengujian ini — tanpanya, menu
    // baru yang lupa disebut di SQL akan diam-diam terbuka untuk Basic.
    test('_menu_semua memuat setiap menu di katalog', () {
      final diKatalog = {for (final v in katalogMenu.values) ...v};
      final diSql = arraySql('_menu_semua').toSet();

      final ketinggalan = diKatalog.difference(diSql);
      expect(ketinggalan, isEmpty,
          reason: 'menu ini ada di aplikasi tapi belum disebut '
              '_menu_semua() di paket_langganan.sql — Basic tidak akan '
              'menutupnya: ${ketinggalan.join(', ')}');
    });

    test('_menu_semua tidak menyebut menu yang tidak ada', () {
      final diKatalog = {for (final v in katalogMenu.values) ...v};
      final berlebih = arraySql('_menu_semua').toSet().difference(diKatalog);
      expect(berlebih, isEmpty,
          reason: 'menu ini disebut SQL tapi tidak ada di aplikasi: '
              '${berlebih.join(', ')}');
    });

    // Daftar putih, bukan daftar hitam: fitur baru harus ditambahkan
    // dengan sengaja supaya terbuka untuk Basic.
    test('semua menu Basic memang menu yang dikenal', () {
      final semua = arraySql('_menu_semua').toSet();
      final basic = arraySql('_menu_paket_basic').toSet();
      expect(basic.difference(semua), isEmpty);
    });

    test('Basic membuka penjualan, shift, keuangan harian, dan info', () {
      final basic = arraySql('_menu_paket_basic').toSet();
      for (final harus in [
        'Kasir / Input Pesanan',
        'Layar Pelanggan',
        'Pending Payment',
        'Riwayat Kasir',
        'Shift Kasir',
        'Saldo & Pengeluaran',
        'Setor Saldo Cash',
        'Info Merchant',
        'Pengaturan Pembayaran',
      ]) {
        expect(basic, contains(harus), reason: harus);
      }
    });

    // Yang membedakan Premium dari Basic. Kalau salah satu bocor ke
    // daftar putih, merchant Basic memakai fitur Premium tanpa
    // membayarnya — dan tidak ada galat yang memberitahukannya.
    test('Basic menutup pembukuan, laporan, absensi karyawan, dan payroll', () {
      final basic = arraySql('_menu_paket_basic').toSet();
      for (final jangan in [
        'Laporan Penjualan',
        'Jurnal GL',
        'Mapping GL Account',
        'Laporan Transaksi',
        'Periksa Pembukuan',
        'Saldo Perusahaan',
        'Rekonsiliasi Bank',
        'Absensi Karyawan',
        'Payroll',
        'Kelola Karyawan',
        'Kelola Produk',
      ]) {
        expect(basic, isNot(contains(jangan)), reason: jangan);
      }
    });

    // Menyatakan diri sudah datang bekerja bukan fitur pembukuan, dan
    // menguncinya menyakiti orang yang salah.
    test('absensi diri sendiri tetap terbuka di Basic', () {
      expect(arraySql('_menu_paket_basic'), contains('Absensi'));
    });
  });

  group('yang dijaga server', () {
    // Memasang berkas ini tidak boleh mengunci seluruh merchant yang
    // sudah berjalan hari ini.
    test('merchant tanpa masa percobaan tidak pernah terkunci paket', () {
      expect(sql, contains('s.trial_until is not null'));
      final blok = sql.substring(sql.indexOf('terkunci_paket boolean'));
      expect(blok, contains('s.paket is null and s.trial_until is not null'));
    });

    // Yang bisa menyisipkan barisnya sendiri bisa menyisipkan yang
    // statusnya sudah 'selesai'.
    test('pengajuan hanya bisa ditulis lewat fungsi', () {
      expect(sql, contains('alter table subscription_requests enable row level security'));
      expect(sql, isNot(contains('create policy "subscription_requests: tulis"')));
    });

    // Tombol yang ditekan dua kali karena jaringannya lambat menjadi dua
    // antrean untuk uang yang sama.
    test('satu pengajuan menunggu per merchant', () {
      expect(sql, contains("on subscription_requests (resto_id) where status = 'verifikasi'"));
    });

    // Berlangganan mengikat merchant pada pembayaran bulanan.
    test('hanya Owner yang bisa berlangganan', () {
      expect(sql, contains("Hanya Owner yang bisa berlangganan."));
    });

    test('hanya KaataGo Admin yang memutuskan dan menyetel paket', () {
      for (final pesan in [
        'Hanya KaataGo Admin yang bisa memutuskan pengajuan.',
        'Hanya KaataGo Admin yang bisa menyetel paket.',
        'Hanya KaataGo Admin yang bisa memberi masa percobaan.',
      ]) {
        expect(sql, contains(pesan), reason: pesan);
      }
    });

    // Pengajuan tanpa bukti adalah pengajuan yang tidak bisa diperiksa
    // siapa pun.
    test('bukti transfernya wajib', () {
      expect(sql, contains('bukti_url text not null'));
      expect(sql, contains('Bukti transfernya wajib diunggah.'));
    });

    // Penolakan tanpa alasan membuat merchant mengirim ulang bukti yang
    // sama.
    test('penolakan wajib menyebut alasannya', () {
      expect(sql, contains('Sebutkan alasannya'));
    });

    // Merchant yang baru saja transfer tidak boleh langsung melihat
    // tagihan yang menuntutnya membayar lagi.
    test('bulan pertama dicatat lunas, bukan jadi utang baru', () {
      final blok = sql.substring(sql.indexOf('function putuskan_langganan'));
      expect(blok, contains("'paid'"));
      expect(blok, contains('insert into billing_invoices'));
    });

    // Layar yang terkunci hanyalah layar.
    test('penguncian paket ikut ditegakkan RLS', () {
      expect(sql, contains('create or replace function is_resto_billing_locked'));
      expect(sql, contains('terkunci_paket from keadaan_langganan'));
    });

    // Percobaan yang separuh terkunci tidak memperlihatkan apa yang
    // sedang ditawarkan.
    test('masa percobaan membuka semuanya', () {
      final blok = sql.substring(sql.indexOf('function set_trial_resto'));
      expect(blok.substring(0, blok.indexOf('\$fn\$;')),
          contains("terapkan_paket(p_resto_id, 'premium')"));
    });

    // Harga yang tertanam di kode berarti menaikkannya menuntut merilis
    // APK baru.
    test('harganya di basis data, bukan di aplikasi', () {
      expect(sql, contains('create table if not exists paket_langganan'));
      final dart = File('lib/models/paket_langganan.dart').readAsStringSync();
      expect(dart, isNot(contains('99000')));
      expect(dart, isNot(contains('249000')));
    });

    // "Bisa diubah tanpa merilis APK" cuma berlaku bagi orang yang
    // memegang akses basis data selama satu-satunya cara mengubahnya
    // adalah SQL.
    test('harganya bisa diubah dari layar KaataGo Admin', () {
      expect(sql, contains('create policy "paket: super admin ubah"'));
      final repo =
          File('lib/db/paket_langganan_repository.dart').readAsStringSync();
      expect(repo, contains('Future<void> simpanHarga('));
      expect(repo, contains("_client.from('paket_langganan').update("));

      final layar =
          File('lib/screens/harga_paket_screen.dart').readAsStringSync();
      expect(layar, contains('class HargaPaketScreen'));
      // Harga baru tidak boleh menaikkan tagihan yang sudah berjalan —
      // dan itu harus tertulis di layarnya, bukan cuma benar diam-diam.
      expect(layar, contains('Harga baru hanya berlaku untuk yang berlangganan'));

      final pengajuan = File('lib/screens/pengajuan_langganan_screen.dart')
          .readAsStringSync();
      expect(pengajuan, contains('HargaPaketScreen()'));
    });

    // Postgres memberi EXECUTE ke PUBLIC secara bawaan, dan
    // terapkan_paket adalah SECURITY DEFINER tanpa pemeriksaan izin di
    // dalamnya. Tanpa pencabutan ini, siapa pun yang sudah masuk bisa
    // memanggilnya sendiri dan menghapus seluruh pembatasan paket
    // sebuah merchant — Basic membuka setiap menu Premium tanpa
    // membayar, dan tanpa satu pun galat.
    test('fungsi bantu tidak bisa dipanggil aplikasi', () {
      final patch =
          File('supabase/perbaikan_hak_fungsi.sql').readAsStringSync();
      for (final berkas in [sql, patch]) {
        expect(berkas, contains('revoke all on function terapkan_paket'));
      }
      expect(sql, contains('revoke all on function ingatkan_percobaan_habis'));

      final absensi = File('supabase/absensi_payroll.sql').readAsStringSync();
      expect(absensi, contains('revoke all on function _absen('));
    });

    // Id resto yang ditebak orang tidak boleh menjawab paket, harga,
    // dan masa percobaan merchant lain.
    test('keadaan langganan hanya untuk merchant sendiri', () {
      final blok = sql.substring(sql.indexOf('function keadaan_langganan'));
      expect(blok, contains('with boleh as ('));
      expect(blok, contains('is_resto_employee(p_resto_id,'));
      expect(blok, contains('where b.ya;'));
    });

    test('pengingat H-2 dijadwalkan sekali sehari', () {
      expect(sql, contains('b.trial_until - v_ini = 2'));
      expect(sql, contains("cron.schedule('kaatago-ingat-percobaan'"));
    });
  });

  group('masa percobaan punya paketnya sendiri', () {
    final rapi = File('supabase/paket_trial_rapi.sql').readAsStringSync();

    // Yang dicoba-cobakan Basic tidak boleh mencicipi Premium dua minggu
    // lalu kehilangan separuh menunya persis di hari dia mulai membayar.
    test('akses menunya mengikuti paket yang dicoba', () {
      expect(rapi, contains('perform terapkan_paket(p_resto_id, v_paket)'));
      expect(rapi, isNot(contains("terapkan_paket(p_resto_id, 'premium')")));
    });

    // Daftar parameternya berubah — `create or replace` dengan daftar
    // berbeda membuat fungsi KEDUA, bukan menimpa.
    test('fungsi lamanya dibuang lebih dulu', () {
      expect(rapi.indexOf('drop function if exists set_trial_resto(text, integer)'),
          lessThan(rapi.indexOf('create or replace function set_trial_resto')));
      expect(rapi.indexOf('drop function if exists keadaan_langganan(text)'),
          lessThan(rapi.indexOf('create or replace function keadaan_langganan')));
    });

    // Percobaan bukan langganan: penagihannya tidak boleh ikut jalan.
    test('percobaan tidak menyetel paket berbayar', () {
      final blok = rapi.substring(rapi.indexOf('function set_trial_resto'));
      expect(blok.substring(0, blok.indexOf('\$fn\$;')),
          contains('paket = null'));
    });

    // set_trial_resto menyetel paket jadi null dan harganya jadi nol.
    // Dipanggil untuk merchant yang sudah membayar, ia membatalkan
    // langganannya dan menghentikan penagihannya — tanpa galat, dan yang
    // menemukannya adalah tagihan yang berhenti datang.
    test('yang sudah berlangganan tidak bisa diberi percobaan', () {
      final blok = rapi.substring(rapi.indexOf('function set_trial_resto'));
      final badan = blok.substring(0, blok.indexOf(r'$fn$;'));
      expect(badan, contains('paket is not null'));
      expect(badan, contains('sudah berlangganan'));
    });

    // Layar yang menyembunyikan tombol tidak menahan apa pun kalau
    // fungsinya tetap bisa dipanggil — tapi menyembunyikannya tetap
    // benar, supaya tidak ada yang menekan tombol yang pasti ditolak.
    test('layarnya menyembunyikan percobaan untuk yang berlangganan', () {
      final layar = File('lib/screens/super_admin_billing_screen.dart')
          .readAsStringSync();
      expect(layar, contains('if (k?.paket != null) ...['));
      expect(layar, contains('sudah berlangganan, jadi masa '));
    });

    // Kolom yang melupakan angka yang barusan diisi orang membuat setiap
    // pembukaan berikutnya terlihat seperti perubahan yang gagal
    // tersimpan.
    test('dialog membaca kembali lama percobaan yang sudah disetel', () {
      final layar = File('lib/screens/super_admin_billing_screen.dart')
          .readAsStringSync();
      expect(layar, contains("_hari.text = '\${k.trialHari ?? 14}'"));
      expect(layar, contains('_paketPercobaan = k.trialPaket ?? Paket.premium'));
    });

    // Tanpa penanda, layar KaataGo Admin tidak punya satu pun tempat
    // yang menyebut siapa yang sedang percobaan.
    test('daftar merchant menyebut yang sedang percobaan', () {
      final layar = File('lib/screens/super_admin_billing_screen.dart')
          .readAsStringSync();
      expect(layar, contains('class _PenandaBaris'));
      expect(layar, contains("'Trial \${k.sisaHari}h'"));
    });

    // Lencana yang cuma menyebut "Percobaan" tidak memberi tahu menu
    // mana yang sedang dipegang.
    test('lencana merchant menyebut paket percobaannya', () {
      final lencana =
          File('lib/widgets/lencana_paket_aktif.dart').readAsStringSync();
      expect(lencana, contains("'Percobaan \${coba.label}"));
    });

    // Menampilkan paket yang sedang dipakai sebagai pilihan berarti
    // menawarkan tombol yang tidak mengubah apa pun, lalu menagih
    // bayaran untuknya.
    test('yang sudah berlangganan cuma ditawari paket yang lain', () {
      const basic = KeadaanLangganan(paket: Paket.basic);
      expect(basic.paketTujuanUbah, Paket.premium);
      const premium = KeadaanLangganan(paket: Paket.premium);
      expect(premium.paketTujuanUbah, Paket.basic);
      const belum = KeadaanLangganan();
      expect(belum.paketTujuanUbah, isNull);

      final layar =
          File('lib/screens/pilih_paket_screen.dart').readAsStringSync();
      expect(layar, contains('List<InfoPaket> get _pilihanPaket'));
      expect(layar, contains('p.paket == tujuan'));
    });

    // Percobaan Basic tetap boleh langsung berlangganan Premium.
    test('yang sedang percobaan tetap bisa memilih dua-duanya', () {
      const coba = KeadaanLangganan(
          dalamPercobaan: true, trialPaket: Paket.basic);
      expect(coba.paketTujuanUbah, isNull);
      expect(coba.paketBerlaku, Paket.basic);
      expect(coba.sudahBerlangganan, isFalse);
    });
  });

  group('keadaan langganan', () {
    test('merchant lama dikenali di luar jalur paket', () {
      const k = KeadaanLangganan();
      expect(k.diluarJalurPaket, isTrue);
      expect(k.terkunciPaket, isFalse);
    });

    test('yang sudah berlangganan tidak di luar jalur', () {
      const k = KeadaanLangganan(paket: Paket.premium);
      expect(k.diluarJalurPaket, isFalse);
    });

    test('diingatkan mulai dua hari sebelum habis', () {
      KeadaanLangganan sisa(int hari) => KeadaanLangganan(
            trialSampai: DateTime(2026, 9, 20),
            dalamPercobaan: true,
            sisaHari: hari,
          );
      expect(sisa(3).mendekatiHabis, isFalse);
      expect(sisa(2).mendekatiHabis, isTrue);
      expect(sisa(0).mendekatiHabis, isTrue);
    });

    test('status pengajuan terbaca', () {
      const diperiksa = KeadaanLangganan(statusPengajuan: 'verifikasi');
      expect(diperiksa.sedangDiperiksa, isTrue);
      const ditolak = KeadaanLangganan(statusPengajuan: 'ditolak');
      expect(ditolak.pengajuanDitolak, isTrue);
    });

    test('dibaca dari kembalian server apa adanya', () {
      final k = KeadaanLangganan.fromMap(const {
        'paket': 'basic',
        'nama_paket': 'Basic',
        'harga': 99000,
        'trial_until': '2026-09-20',
        'trial_days': 14,
        'sisa_hari': -3,
        'dalam_percobaan': false,
        'percobaan_habis': true,
        'status_pengajuan': 'selesai',
        'terkunci_paket': false,
      });
      expect(k.paket, Paket.basic);
      expect(k.harga, 99000);
      expect(k.trialHari, 14);
      expect(k.percobaanHabis, isTrue);
    });
  });
}
