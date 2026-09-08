import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/periksa_qris.dart';

/// Menyusun payload EMVCo dari pasangan tag dan isinya.
String _payload(List<(String, String)> tag) => tag
    .map((t) => '${t.$1}${t.$2.length.toString().padLeft(2, '0')}${t.$2}')
    .join();

void main() {
  String qrisSah({String nama = 'KAATA RESTO', String mataUang = '360'}) =>
      _payload([
        ('00', '01'),
        ('01', '11'),
        ('26', '0014ID.CO.QRIS.WWW'),
        ('52', '5812'),
        ('53', mataUang),
        ('58', 'ID'),
        ('59', nama),
        ('60', 'JAKARTA'),
      ]);

  group('yang diterima', () {
    test('QRIS yang benar lolos', () {
      final hasil = periksaPayloadQris(qrisSah());
      expect(hasil.sah, isTrue);
      expect(hasil.namaMerchant, 'KAATA RESTO');
    });

    test('spasi di ujung tidak menggagalkan', () {
      expect(periksaPayloadQris('  ${qrisSah()}  ').sah, isTrue);
    });
  });

  group('yang ditolak, berikut alasannya', () {
    test('gambar tanpa QR', () {
      final h = periksaPayloadQris(null);
      expect(h.sah, isFalse);
      expect(h.alasan, contains('tidak berisi QR'));
    });

    // Inilah kekeliruan yang paling mungkin: QR apa pun difoto dan
    // dikira QRIS.
    test('QR biasa berisi tautan', () {
      final h = periksaPayloadQris('https://kaatago.com');
      expect(h.sah, isFalse);
      expect(h.alasan, contains('bukan QRIS'));
    });

    test('QR pembayaran mata uang lain', () {
      final h = periksaPayloadQris(qrisSah(mataUang: '702'));
      expect(h.sah, isFalse);
      expect(h.alasan, contains('Rupiah'));
    });

    test('tanpa penyelenggara QRIS', () {
      final h = periksaPayloadQris(_payload([
        ('00', '01'),
        ('53', '360'),
        ('59', 'ENTAH'),
      ]));
      expect(h.sah, isFalse);
      expect(h.alasan, contains('penyelenggara'));
    });

    // Panjang yang menunjuk ke luar teks: payload terpotong.
    test('susunan yang rusak', () {
      final h = periksaPayloadQris('000201' '2699AB');
      expect(h.sah, isFalse);
      expect(h.alasan, contains('rusak'));
    });
  });
}
