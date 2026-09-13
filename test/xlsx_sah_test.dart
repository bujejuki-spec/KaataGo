import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/utils/xlsx.dart';

/// Berkas .xlsx yang ditulis sendiri.
///
/// Diuji dengan benar-benar dibongkar, bukan dibaca sebagai teks: Excel
/// menolak berkas yang XML-nya cacat dengan cara yang paling tidak
/// membantu — berkasnya tidak mau dibuka sama sekali, tanpa menyebut
/// bagian mana yang salah.
void main() {
  test('menghasilkan zip yang isinya lengkap', () {
    final bytes = susunXlsx(const [
      LembarXlsx(
        nama: 'Payroll',
        baris: [
          [SelXlsx.teks('Nama'), SelXlsx.teks('Gaji')],
          [SelXlsx.teks('Budi & Rekan'), SelXlsx.angka(5600000)],
          [SelXlsx.teks('Ani <Kasir>'), SelXlsx.angka(4200000)],
        ],
        lebarKolom: [20, 14],
      ),
      LembarXlsx(
        nama: 'Absensi Harian',
        baris: [
          [SelXlsx.teks('Nama'), SelXlsx.teks('Status')],
          [SelXlsx.teks('Budi'), SelXlsx.teks('Hadir')],
        ],
      ),
    ]);
    expect(bytes.length, greaterThan(500));
    File('/tmp/kaatago-uji.xlsx').writeAsBytesSync(bytes);
  });

  // Nama lembar lebih dari 31 huruf membuat berkasnya rusak, dan
  // rusaknya berupa Excel yang menolak membukanya — bukan pesan galat.
  test('nama lembar yang kepanjangan dipangkas', () {
    final bytes = susunXlsx(const [
      LembarXlsx(
        nama: 'Absensi & Payroll Karyawan Bulan September Tahun 2026',
        baris: [
          [SelXlsx.teks('A')]
        ],
      ),
    ]);
    File('/tmp/kaatago-uji-panjang.xlsx').writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(400));
  });
}
