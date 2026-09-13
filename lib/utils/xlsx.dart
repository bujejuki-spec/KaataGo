import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Penulis berkas .xlsx seadanya — tapi .xlsx sungguhan.
///
/// ── Kenapa ditulis sendiri ───────────────────────────────────────────
///
/// Paket `excel` menuntut `archive` versi 3, sedangkan aplikasi ini
/// sudah memakai versi 4 untuk hal lain. Menurunkan `archive` demi satu
/// laporan berarti menyentuh kode yang sudah jalan di tempat lain, dan
/// bertahan pada dua versi paket yang sama tidak mungkin.
///
/// Yang dibutuhkan di sini juga kecil: beberapa lembar berisi teks,
/// angka, dan satu baris judul tebal. Itu bisa ditulis langsung — sebuah
/// .xlsx tidak lain adalah ZIP berisi beberapa berkas XML.
///
/// Yang sengaja tidak didukung: rumus, gambar, penggabungan sel, dan
/// beberapa lembar dengan gaya berbeda-beda. Begitu salah satunya
/// dibutuhkan, yang benar adalah menambahkannya di sini — bukan
/// menempelkannya di tempat pemakaian.

/// Satu sel. Angka ditulis sebagai angka supaya bisa dijumlahkan di
/// Excel; teks yang berisi angka akan muncul dengan segitiga hijau dan
/// tidak ikut terjumlah.
class SelXlsx {
  final String? teks;
  final num? angka;

  const SelXlsx.teks(String this.teks) : angka = null;
  const SelXlsx.angka(num this.angka) : teks = null;
  const SelXlsx.kosong()
      : teks = null,
        angka = null;
}

/// Satu lembar.
class LembarXlsx {
  final String nama;

  /// Baris pertama dianggap judul kolom dan ditebalkan.
  final List<List<SelXlsx>> baris;

  /// Lebar tiap kolom dalam satuan karakter. Boleh lebih pendek dari
  /// jumlah kolomnya.
  final List<double> lebarKolom;

  const LembarXlsx({
    required this.nama,
    required this.baris,
    this.lebarKolom = const [],
  });
}

/// Merangkai lembar-lembar jadi satu berkas .xlsx.
Uint8List susunXlsx(List<LembarXlsx> lembar) {
  if (lembar.isEmpty) {
    throw ArgumentError('Tidak ada lembar untuk ditulis.');
  }

  final arsip = Archive();

  void tulis(String nama, String isi) {
    final b = utf8.encode(isi);
    arsip.addFile(ArchiveFile(nama, b.length, b));
  }

  tulis('[Content_Types].xml', _contentTypes(lembar.length));
  tulis('_rels/.rels', _relsUtama);
  tulis('xl/workbook.xml', _workbook(lembar));
  tulis('xl/_rels/workbook.xml.rels', _relsWorkbook(lembar.length));
  tulis('xl/styles.xml', _styles);

  for (var i = 0; i < lembar.length; i++) {
    tulis('xl/worksheets/sheet${i + 1}.xml', _sheet(lembar[i]));
  }

  // Tanpa kompresi tambahan di luar deflate bawaan ZIP: laporan absensi
  // sebulan berisi ratusan baris, bukan ratusan ribu.
  final zip = ZipEncoder().encode(arsip);
  return Uint8List.fromList(zip);
}

String _contentTypes(int jumlah) {
  final sheets = [
    for (var i = 1; i <= jumlah; i++)
      '<Override PartName="/xl/worksheets/sheet$i.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.worksheet+xml"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.'
      'openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.'
      'openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '$sheets</Types>';
}

const _relsUtama =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<LembarXlsx> lembar) {
  final sheets = [
    for (var i = 0; i < lembar.length; i++)
      '<sheet name="${_aman(_namaLembar(lembar[i].nama))}" '
          'sheetId="${i + 1}" r:id="rId${i + 1}"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets>$sheets</sheets></workbook>';
}

/// Excel menolak nama lembar yang panjangnya lebih dari 31 huruf atau
/// memuat : \ / ? * [ ] — dan penolakannya berupa berkas rusak yang
/// tidak mau dibuka sama sekali, bukan pesan galat.
String _namaLembar(String nama) {
  final bersih = nama.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
  return bersih.length <= 31 ? bersih : bersih.substring(0, 31);
}

String _relsWorkbook(int jumlah) {
  final rel = [
    for (var i = 1; i <= jumlah; i++)
      '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/'
          'officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet$i.xml"/>',
    '<Relationship Id="rId${jumlah + 1}" Type="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships/styles" Target="styles.xml"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '$rel</Relationships>';
}

/// Dua gaya: biasa (0) dan tebal (1).
const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border/></borders>'
    '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
    '<cellXfs count="2">'
    '<xf xfId="0"/>'
    '<xf xfId="0" fontId="1" applyFont="1"/>'
    '</cellXfs></styleSheet>';

String _sheet(LembarXlsx lembar) {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main">');

  if (lembar.lebarKolom.isNotEmpty) {
    buf.write('<cols>');
    for (var i = 0; i < lembar.lebarKolom.length; i++) {
      buf.write('<col min="${i + 1}" max="${i + 1}" '
          'width="${lembar.lebarKolom[i]}" customWidth="1"/>');
    }
    buf.write('</cols>');
  }

  buf.write('<sheetData>');
  for (var r = 0; r < lembar.baris.length; r++) {
    buf.write('<row r="${r + 1}">');
    final baris = lembar.baris[r];
    for (var c = 0; c < baris.length; c++) {
      final sel = baris[c];
      final ref = '${_kolom(c)}${r + 1}';
      final gaya = r == 0 ? ' s="1"' : '';
      if (sel.angka != null) {
        buf.write('<c r="$ref"$gaya><v>${sel.angka}</v></c>');
      } else if (sel.teks != null && sel.teks!.isNotEmpty) {
        // inlineStr, bukan sharedStrings: tabel bersama hanya menghemat
        // ruang kalau teksnya banyak berulang, dan yang berulang di
        // laporan ini cuma nama status.
        buf.write('<c r="$ref"$gaya t="inlineStr"><is><t xml:space="preserve">'
            '${_aman(sel.teks!)}</t></is></c>');
      } else {
        buf.write('<c r="$ref"$gaya/>');
      }
    }
    buf.write('</row>');
  }
  buf.write('</sheetData></worksheet>');
  return buf.toString();
}

/// 0 -> A, 25 -> Z, 26 -> AA.
String _kolom(int i) {
  var n = i;
  var hasil = '';
  while (true) {
    hasil = String.fromCharCode(65 + n % 26) + hasil;
    n = n ~/ 26 - 1;
    if (n < 0) break;
  }
  return hasil;
}

/// Nama orang memuat `&` lebih sering daripada yang diduga, dan satu
/// ampersand mentah membuat seluruh berkasnya ditolak Excel sebagai
/// rusak — bukan satu selnya saja.
String _aman(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Karakter kendali tidak sah di XML 1.0. Bisa ikut masuk dari
    // tempelan orang yang menyalin alasan izin dari aplikasi lain.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
