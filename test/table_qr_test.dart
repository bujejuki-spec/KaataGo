import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/table_qr_image.dart';

void main() {
  group('tableLabelRange', () {
    test('menjabarkan rentangnya', () {
      expect(tableLabelRange(from: 1, to: 4), ['1', '2', '3', '4']);
    });

    test('nol di depan mengikuti nomor terbesar', () {
      final labels = tableLabelRange(from: 8, to: 12);
      expect(labels, ['08', '09', '10', '11', '12']);
    });

    test('nol di depan bikin urutannya benar saat diurutkan sebagai teks', () {
      final labels = tableLabelRange(from: 1, to: 12)..sort();
      // Inilah alasan nol di depannya ada: galeri mengurutkan nama berkas
      // sebagai teks, dan tanpa itu meja 10 nyempil di antara 1 dan 2.
      expect(labels.first, '01');
      expect(labels[1], '02');
      expect(labels.last, '12');
    });

    test('awalan menempel di depan nomornya', () {
      expect(tableLabelRange(prefix: 'VIP-', from: 1, to: 3),
          ['VIP-1', 'VIP-2', 'VIP-3']);
    });

    test('rentang terbalik tidak menghasilkan apa-apa', () {
      expect(tableLabelRange(from: 9, to: 3), isEmpty);
    });

    test('nomor awal di bawah 1 ditolak', () {
      expect(tableLabelRange(from: 0, to: 5), isEmpty);
    });

    test('satu meja tetap sah', () {
      expect(tableLabelRange(from: 5, to: 5), ['5']);
    });

    test('tepat sebatas maksimum masih boleh, lewat satu ditolak', () {
      expect(tableLabelRange(from: 1, to: kMaxTableBatch), hasLength(kMaxTableBatch));
      expect(tableLabelRange(from: 1, to: kMaxTableBatch + 1), isEmpty);
    });
  });

  group('TableQrCard', () {
    test('nama berkasnya menyebut nomor mejanya', () {
      const card = TableQrCard(restoName: 'Resto', table: '07', payload: 'x');
      expect(card.fileName, 'qr-meja-07.png');
    });

    test('karakter yang tidak aman untuk nama berkas diganti', () {
      // Nomor meja bebas diketik, jadi "VIP/2" bisa saja masuk — dan garis
      // miring di situ akan dibaca sebagai pemisah folder.
      const card = TableQrCard(restoName: 'Resto', table: 'VIP/2', payload: 'x');
      expect(card.fileName, 'qr-meja-VIP-2.png');
    });
  });
}
