import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pelanggan membayar QRIS Statis dari HP-nya sendiri.
///
/// Yang dijaga di sini hal-hal yang kalau salah TIDAK berbunyi: nilai
/// status yang ditebak, perbandingan uuid yang melempar galat di dalam
/// kebijakan storage, dan penanda merah yang menghitung lebih sedikit
/// daripada daftar yang dibukanya.
void main() {
  String baca(String jalur) => File(jalur).readAsStringSync();

  final sql = baca('supabase/bukti_bayar_qris_statis.sql');
  final repo = baca('lib/db/order_repository.dart');

  group('fungsi melampirkan bukti', () {
    test("statusnya 'pending', bukan tebakan", () {
      // Nilainya ditulis aplikasi dari nama enum-nya sendiri
      // (OrderPaymentStatus.pending). Menebaknya 'unpaid' menghasilkan
      // fungsi yang menolak SETIAP pesanan yang sah — dan penolakannya
      // terlihat seperti pesanannya yang bermasalah.
      expect(sql, contains("is distinct from 'pending'"));
      final kode = sql
          .split('\n')
          .where((b) => !b.trimLeft().startsWith('--'))
          .join('\n');
      expect(kode, isNot(contains("'unpaid'")));
    });

    test('uuid dibandingkan sebagai teks, bukan sebaliknya', () {
      // Nama berkas yang bukan uuid MELEMPAR galat kalau dipaksa jadi
      // uuid — dan galat di dalam kebijakan storage mematikan unggahan
      // untuk semua orang, bukan cuma untuk yang salah menamai.
      expect(sql, contains('o.id::text = split_part'));
      expect(sql, contains('id::text = p_order_id'));
    });

    test('hanya pesanan QRIS Statis yang bisa dilampiri', () {
      expect(sql, contains("payment_method is distinct from 'qris_static'"));
    });

    test('bisa dipanggil pelanggan yang belum login', () {
      // Pemesan dari QR meja sering tidak login sama sekali, dan dialah
      // yang memegang buktinya.
      expect(sql, contains('to anon, authenticated'));
    });
  });

  group('ember bukti bayar', () {
    test('tertutup, bukan publik', () {
      // Bukti transfer memuat nama pengirim dan nominalnya.
      expect(sql, contains("values ('bukti-bayar', 'bukti-bayar', false)"));
      expect(sql, contains('do update set public = false'));
    });

    test('menulis dibatasi pesanan yang benar-benar menunggu bayar', () {
      // Ember yang menerima tulisan tanpa syarat adalah tempat
      // penyimpanan gratis bagi siapa pun yang menemukannya.
      final tulis = sql.substring(sql.indexOf('pelanggan menulis'));
      expect(tulis.substring(0, 900), contains('from public.orders o'));
      expect(tulis.substring(0, 900), contains("o.payment_status = 'pending'"));
    });

    test('chef tidak bisa membacanya', () {
      // Antrean dapur tidak berurusan dengan bukti transfer siapa pun.
      final baca = sql.substring(sql.indexOf('kasir membaca'));
      final blok = baca.substring(0, 700);
      expect(blok, contains("'kasir'"));
      expect(blok, isNot(contains("'chef'")));
    });
  });

  group('sisi aplikasi', () {
    test('buktinya diunggah lalu dilampirkan lewat fungsi', () {
      // Pelanggan tidak punya hak mengubah baris pesanan, dan memang
      // tidak boleh punya: baris itu juga memuat status dapur dan total.
      expect(repo, contains("from('bukti-bayar')"));
      expect(repo, contains("rpc('lampirkan_bukti_bayar'"));
      expect(repo, contains(r"'$restoId/$orderId.jpg'"));
    });

    test('penanda merah menghitung sama dengan daftarnya', () {
      // Daftarnya disaring di Dart lewat isPendingCashPayment yang sudah
      // menyertakan QRIS Statis; hitungan ini menyaring di SQL. Keduanya
      // harus menjawab pertanyaan yang sama.
      expect(repo,
          contains("inFilter('payment_method', const ['cash', 'qris_static'])"));
    });

    test('QRIS Statis punya layar bayarnya sendiri di sisi pelanggan', () {
      final cart = baca('lib/screens/customer_cart_screen.dart');
      expect(cart, contains("'qris_static' => CustomerQrisStatisScreen("));
      // Dan tidak lagi dianggap dibayar di kasir.
      expect(cart, contains("bool get _payAtCashier => _paymentMethod == 'cash';"));
    });

    test('mitra tidak ditanya lagi cara bayarnya untuk QRIS Statis', () {
      // Tiap pilihan yang bisa diubah adalah pilihan yang bisa salah
      // diubah — dan pembayaran QRIS yang tercatat sebagai tunai adalah
      // uang yang dicari di laci dan tidak pernah ada di sana.
      final layar = baca('lib/screens/pending_payment_screen.dart');
      final blok = layar.substring(layar.indexOf('Future<void> _settle('));
      final sebelumSheet = blok.substring(0, blok.indexOf('showModalBottomSheet'));
      expect(sebelumSheet, contains("order.paymentMethod == 'qris_static'"));
      expect(sebelumSheet, contains('_DialogBuktiQris'));
      expect(sebelumSheet, contains('return;'));
    });

    test('buktinya ditampilkan, bukan sekadar ditautkan', () {
      final layar = baca('lib/screens/pending_payment_screen.dart');
      expect(layar, contains("ember: 'bukti-bayar'"));
    });
  });
}
