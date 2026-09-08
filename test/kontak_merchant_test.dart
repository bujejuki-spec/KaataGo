import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/kontak_merchant.dart';

/// Nomor yang diketik orang bermacam-macam bentuknya, dan wa.me cuma
/// menerima satu. Yang tidak dinormalkan menghasilkan tautan yang
/// terbuka lalu berhenti di layar "nomor tidak valid" — kegagalan yang
/// terlihat seperti WhatsApp-nya yang bermasalah, bukan nomornya.
void main() {
  group('nomor jadi bentuk wa.me', () {
    test('nol di depan diganti kode negara', () {
      expect(nomorWhatsApp('081316090867'), '6281316090867');
    });

    test('tanda plus, spasi, dan hubung dibuang', () {
      expect(nomorWhatsApp('+62 813-1609 0867'), '6281316090867');
    });

    test('yang sudah 62 dibiarkan', () {
      expect(nomorWhatsApp('6281316090867'), '6281316090867');
    });

    test('lokal tanpa nol tetap dapat kode negara', () {
      expect(nomorWhatsApp('81316090867'), '6281316090867');
    });

    // Kode negara saja bukan nomor, dan tombolnya tidak boleh muncul.
    test('yang kosong atau cuma simbol ditolak', () {
      expect(nomorWhatsApp(null), isNull);
      expect(nomorWhatsApp('-'), isNull);
      expect(nomorWhatsApp('0'), isNull);
    });
  });

  group('punya kontak atau tidak', () {
    test('nomor kosong berarti tidak punya', () {
      expect(punyaWhatsApp(null), isFalse);
      expect(punyaWhatsApp('  '), isFalse);
      expect(punyaWhatsApp('081316090867'), isTrue);
    });

    test('surel harus berisi @', () {
      expect(punyaSurel(null), isFalse);
      expect(punyaSurel('bukan-email'), isFalse);
      expect(punyaSurel('resto@contoh.co.id'), isTrue);
    });
  });
}
