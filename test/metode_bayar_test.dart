import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/metode_bayar.dart';

void main() {
  group('kode yang tersimpan tidak berubah', () {
    // Nilai 'qris' tersebar di ribuan baris pesanan, jurnal, dan
    // pencairan. Yang berubah hanya namanya di layar — mengganti
    // nilainya berarti menulis ulang sejarah dan berharap tidak ada satu
    // pun tempat yang terlewat.
    test('QRIS lama tetap berkode qris, namanya saja yang jadi Dinamis', () {
      expect(MetodeBayar.qrisDinamis.kode, 'qris');
      expect(MetodeBayar.qrisDinamis.label, 'QRIS Dinamis');
    });

    test('QRIS Statis punya kodenya sendiri', () {
      expect(MetodeBayar.qrisStatis.kode, 'qris_static');
    });

    test('kode lama tetap terbaca labelnya', () {
      expect(MetodeBayar.labelDari('cash'), 'Tunai');
      expect(MetodeBayar.labelDari('transfer'), 'Transfer');
    });
  });

  group('metode yang ditawarkan merchant', () {
    test('baris lama tanpa kolomnya dianggap menyala', () {
      // Merchant yang sudah berjualan tidak boleh kehilangan metode
      // bayarnya hanya karena aplikasinya diperbarui.
      final m = MetodeBayarMerchant.fromMap({});
      expect(m.tunai, isTrue);
      expect(m.qrisDinamis, isTrue);
      expect(m.transfer, isTrue);
      expect(m.qrisStatis, isFalse);
    });

    // Saklarnya menyala tapi gambarnya tidak ada = metode yang layarnya
    // kosong. Pelanggan yang memilihnya berdiri memandangi tempat yang
    // seharusnya berisi QR.
    test('QRIS Statis tanpa QR tidak dianggap aktif', () {
      const m = MetodeBayarMerchant(qrisStatis: true);
      expect(m.aktif(MetodeBayar.qrisStatis), isFalse);
      expect(m.yangAktif, isNot(contains(MetodeBayar.qrisStatis)));
    });

    test('QRIS Statis dengan QR ikut ditawarkan', () {
      const m = MetodeBayarMerchant(
          qrisStatis: true, qrisStatisUrl: 'https://x/qr.png');
      expect(m.yangAktif, contains(MetodeBayar.qrisStatis));
    });

    test('membuang QR-nya ikut mematikan metodenya', () {
      const m = MetodeBayarMerchant(
          qrisStatis: true, qrisStatisUrl: 'https://x/qr.png');
      final sesudah = m.copyWith(hapusQrisStatis: true);
      expect(sesudah.qrisStatis, isFalse);
      expect(sesudah.qrisStatisUrl, isNull);
    });
  });

  group('QRIS Statis dibayar lewat kasir, bukan lewat aplikasi', () {
    // QR statis tidak membawa nominal, jadi pelanggan bisa mengirim
    // jumlah yang berbeda. Yang memastikan angkanya benar adalah kasir.
    test('pesanannya masuk antrean menunggu bayar di kasir', () {
      final model =
          File('lib/models/customer_order.dart').readAsStringSync();
      final blok = model.substring(model.indexOf('bool get isPendingCashPayment'));
      expect(blok.substring(0, blok.indexOf(';')),
          contains("paymentMethod == 'qris_static'"));
    });

    test('yang ditinggalkan ikut hangus setelah 30 menit', () {
      final sql = File('supabase/qris_hangus.sql').readAsStringSync();
      expect(sql, contains("in ('cash', 'qris', 'qris_static')"));
    });
  });

  group('jurnalnya terpisah dari QRIS Dinamis', () {
    final sql = File('supabase/qris_statis.sql').readAsStringSync();

    // Yang dinamis lewat penyedia pembayaran dan dicairkan menyusul;
    // yang statis mendarat langsung. Satu akun untuk keduanya membuat
    // angka yang menunggu dicairkan menghitung uang yang sudah sampai.
    test('punya akun GL sendiri', () {
      expect(sql, contains("('qris_static',      '1950004'"));
      expect(sql, contains('GL Penerimaan QRIS Statis'));
    });

    test('GL QRIS lama diganti namanya, bukan kodenya', () {
      expect(sql, contains("('qris',             '1950002', "
          "'GL Penerimaan QRIS Dinamis')"));
      expect(sql, contains("set gl_name = 'GL Penerimaan QRIS Dinamis'"));
    });

    // Merchant yang sudah menamai akunnya sendiri tidak boleh ditimpa —
    // pemetaan GL adalah keputusan pembukuan mereka.
    test('penggantian nama hanya menyentuh nama bawaannya', () {
      expect(sql, contains("and gl_name = 'GL Penerimaan QRIS'"));
    });
  });
}
