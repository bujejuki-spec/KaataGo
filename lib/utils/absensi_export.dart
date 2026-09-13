import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/absensi.dart';
import 'id_time.dart';
import 'kode_bank.dart';
import 'simpan_bagikan.dart';
import 'xlsx.dart';

final _rp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _bulanTahun = DateFormat('MMMM yyyy', 'id_ID');
final _tglPendek = DateFormat('dd/MM/yyyy', 'id_ID');
final _jam = DateFormat('HH:mm', 'id_ID');

/// Nama berkas ekspor, berikut periodenya.
///
/// Periodenya ikut di nama, bukan cuma di dalam berkasnya. Berkas
/// laporan menumpuk di folder Unduhan orang, dan tiga berkas bernama
/// sama yang dibedakan angka "(1)" dan "(2)" adalah tiga berkas yang
/// harus dibuka satu per satu untuk tahu mana yang bulan lalu.
String namaBerkasAbsensi(String namaMerchant, DateTime periode) {
  // Hanya karakter yang memang dilarang nama berkas yang dibuang. "&"
  // dipertahankan karena ia bagian dari judul yang diminta, dan sah di
  // Android, Windows, maupun macOS.
  final merchant = namaMerchant
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final bulan = _bulanTahun.format(periode);
  return 'Absensi & Payroll Karyawan '
      '${merchant.isEmpty ? 'Merchant' : merchant} $bulan';
}

/// Satu karyawan berikut absensinya, siap dicetak.
class RekapKaryawan {
  final BarisPayroll payroll;
  final List<BarisAbsensi> absensi;

  const RekapKaryawan({required this.payroll, required this.absensi});
}

// ─────────────────────────────────────────────────────────────────────
// XLSX
// ─────────────────────────────────────────────────────────────────────

/// Dua lembar: rekap gaji, dan absensi harian.
///
/// Rekapnya lebih dulu karena itu yang dibuka bagian keuangan untuk
/// membayar. Absensi hariannya ada di lembar kedua sebagai bukti angka
/// di lembar pertama — dan tanpa itu, "potongan 4 hari" adalah angka
/// yang harus dipercaya begitu saja.
Uint8List xlsxAbsensiPayroll({
  required String namaMerchant,
  required DateTime mulai,
  required DateTime akhir,
  required List<RekapKaryawan> data,
  required AturanGaji aturan,
}) {
  final judulPeriode =
      '${_tglPendek.format(mulai)} - ${_tglPendek.format(akhir)}';

  final rekap = <List<SelXlsx>>[
    const [
      SelXlsx.teks('Nama'),
      SelXlsx.teks('Peran'),
      SelXlsx.teks('Bank'),
      SelXlsx.teks('Kode Bank'),
      SelXlsx.teks('No. Rekening'),
      SelXlsx.teks('Atas Nama'),
      SelXlsx.teks('Hari Kerja'),
      SelXlsx.teks('Hadir'),
      SelXlsx.teks('Izin'),
      SelXlsx.teks('Sakit'),
      SelXlsx.teks('Cuti'),
      SelXlsx.teks('Alpa'),
      SelXlsx.teks('Hari Potong'),
      SelXlsx.teks('Gaji Pokok'),
      SelXlsx.teks('Tunjangan'),
      SelXlsx.teks('Potongan Absen'),
      SelXlsx.teks('BPJS Kesehatan'),
      SelXlsx.teks('BPJS Ketenagakerjaan'),
      SelXlsx.teks('Gaji Bersih'),
    ],
    for (final r in data)
      [
        SelXlsx.teks(r.payroll.nama),
        SelXlsx.teks(r.payroll.peran),
        SelXlsx.teks(r.payroll.bankName ?? '-'),
        // Kolomnya sendiri, bukan digabung ke nama banknya: berkas ini
        // dipakai menyusun daftar transfer, dan yang menyalinnya butuh
        // kodenya berdiri sendiri supaya bisa ditempel apa adanya.
        SelXlsx.teks(kodeBank(r.payroll.bankName) ?? '-'),
        // Nomor rekening sebagai teks, bukan angka. Sebagai angka, nol
        // di depannya hilang dan rekening 0081234567 terkirim ke
        // 81234567 — rekening yang mungkin milik orang lain.
        SelXlsx.teks(r.payroll.accountNumber ?? '-'),
        SelXlsx.teks(r.payroll.accountHolder ?? '-'),
        SelXlsx.angka(r.payroll.hariKerja),
        SelXlsx.angka(r.payroll.hadir),
        SelXlsx.angka(r.payroll.izin),
        SelXlsx.angka(r.payroll.sakit),
        SelXlsx.angka(r.payroll.cuti),
        SelXlsx.angka(r.payroll.alpa),
        SelXlsx.angka(r.payroll.hariPotong),
        SelXlsx.angka(r.payroll.gajiPokok),
        SelXlsx.angka(r.payroll.tunjangan),
        SelXlsx.angka(r.payroll.potonganAbsen),
        SelXlsx.angka(r.payroll.potonganBpjsKesehatan),
        SelXlsx.angka(r.payroll.potonganBpjsTk),
        SelXlsx.angka(r.payroll.gajiBersih),
      ],
    const [SelXlsx.kosong()],
    [
      const SelXlsx.teks('TOTAL'),
      for (var i = 0; i < 17; i++) const SelXlsx.kosong(),
      SelXlsx.angka(data.fold<int>(0, (a, b) => a + b.payroll.gajiBersih)),
    ],
    const [SelXlsx.kosong()],
    [
      const SelXlsx.teks('Periode'),
      SelXlsx.teks(judulPeriode),
    ],
    [
      const SelXlsx.teks('Tanggal gajian'),
      SelXlsx.teks('Tiap tanggal ${aturan.tanggalGajian}'),
    ],
    [
      const SelXlsx.teks('Hari kerja per periode'),
      SelXlsx.angka(aturan.hariKerjaPeriode),
    ],
  ];

  final harian = <List<SelXlsx>>[
    const [
      SelXlsx.teks('Nama'),
      SelXlsx.teks('Tanggal'),
      SelXlsx.teks('Status'),
      SelXlsx.teks('Masuk'),
      SelXlsx.teks('Pulang'),
      SelXlsx.teks('Jarak (m)'),
      SelXlsx.teks('Latitude'),
      SelXlsx.teks('Longitude'),
      SelXlsx.teks('Potong Gaji'),
      SelXlsx.teks('Alasan'),
    ],
    for (final r in data)
      for (final a in r.absensi)
        [
          SelXlsx.teks(r.payroll.nama),
          SelXlsx.teks(_tglPendek.format(a.tanggal)),
          SelXlsx.teks(a.status.label),
          SelXlsx.teks(a.masukAt == null ? '-' : _jam.format(a.masukAt!.toWib())),
          SelXlsx.teks(
              a.pulangAt == null ? '-' : _jam.format(a.pulangAt!.toWib())),
          if (a.masukJarakM != null)
            SelXlsx.angka(a.masukJarakM!)
          else
            const SelXlsx.teks('-'),
          if (a.masukLat != null)
            SelXlsx.angka(a.masukLat!)
          else
            const SelXlsx.teks('-'),
          if (a.masukLng != null)
            SelXlsx.angka(a.masukLng!)
          else
            const SelXlsx.teks('-'),
          SelXlsx.teks(a.potongGaji ? 'Ya' : 'Tidak'),
          SelXlsx.teks(a.alasan ?? ''),
        ],
  ];

  return susunXlsx([
    LembarXlsx(
      nama: 'Payroll',
      baris: rekap,
      lebarKolom: const [22, 10, 14, 10, 18, 20, 11, 8, 7, 8, 7, 7, 12, 14, 13,
        15, 15, 20, 15],
    ),
    LembarXlsx(
      nama: 'Absensi Harian',
      baris: harian,
      lebarKolom: const [22, 12, 10, 9, 9, 10, 12, 12, 11, 30],
    ),
  ]);
}

// ─────────────────────────────────────────────────────────────────────
// PDF
// ─────────────────────────────────────────────────────────────────────

Future<Uint8List> pdfAbsensiPayroll({
  required String namaMerchant,
  required DateTime mulai,
  required DateTime akhir,
  required List<RekapKaryawan> data,
  required AturanGaji aturan,
}) async {
  final doc = pw.Document();
  final total = data.fold<int>(0, (a, b) => a + b.payroll.gajiBersih);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text('Absensi & Payroll — $namaMerchant',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Halaman ${context.pageNumber} dari ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600)),
      ),
      build: (context) => [
        pw.Text('Absensi & Payroll Karyawan',
            style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(namaMerchant, style: const pw.TextStyle(fontSize: 12)),
        pw.Text(
          'Periode ${_tglPendek.format(mulai)} - ${_tglPendek.format(akhir)}'
          '  •  ${aturan.hariKerjaPeriode} hari kerja'
          '  •  gajian tiap tanggal ${aturan.tanggalGajian}',
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
        _tabelPayroll(data),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Total gaji bersih: ${_rp.format(total)}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Absensi Harian',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _tabelHarian(data),
        pw.SizedBox(height: 14),
        pw.Text(
          'Dicetak dari KaataGo. Titik GPS dan jarak tercatat pada tiap '
          'absen; wajah dicocokkan di server dengan yang terdaftar.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _tabelPayroll(List<RekapKaryawan> data) {
  return pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellAlignment: pw.Alignment.centerLeft,
    cellAlignments: {
      for (var i = 6; i <= 12; i++) i: pw.Alignment.centerRight,
    },
    headers: const [
      'Nama',
      'Peran',
      'Bank',
      'No. Rekening',
      'Atas Nama',
      'Hadir',
      'Potong',
      'Gaji Pokok',
      'Tunjangan',
      'Pot. Absen',
      'BPJS Kes',
      'BPJS TK',
      'Gaji Bersih',
    ],
    data: [
      for (final r in data)
        [
          r.payroll.nama,
          r.payroll.peran,
          // Kode dan nama bank digabung di PDF — yang membacanya manusia,
          // bukan yang menyalin ke kolom formulir.
          bankBerkode(r.payroll.bankName),
          r.payroll.accountNumber ?? '-',
          r.payroll.accountHolder ?? '-',
          '${r.payroll.hadir}',
          '${r.payroll.hariPotong}',
          _rp.format(r.payroll.gajiPokok),
          _rp.format(r.payroll.tunjangan),
          _rp.format(r.payroll.potonganAbsen),
          _rp.format(r.payroll.potonganBpjsKesehatan),
          _rp.format(r.payroll.potonganBpjsTk),
          _rp.format(r.payroll.gajiBersih),
        ],
    ],
  );
}

pw.Widget _tabelHarian(List<RekapKaryawan> data) {
  return pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    headers: const [
      'Nama',
      'Tanggal',
      'Status',
      'Masuk',
      'Pulang',
      'Jarak',
      'Titik GPS',
      'Potong',
      'Alasan',
    ],
    data: [
      for (final r in data)
        for (final a in r.absensi)
          [
            r.payroll.nama,
            _tglPendek.format(a.tanggal),
            a.status.label,
            a.masukAt == null ? '-' : _jam.format(a.masukAt!.toWib()),
            a.pulangAt == null ? '-' : _jam.format(a.pulangAt!.toWib()),
            a.masukJarakM == null ? '-' : '${a.masukJarakM} m',
            a.masukLat == null
                ? '-'
                : '${a.masukLat!.toStringAsFixed(5)}, '
                    '${a.masukLng?.toStringAsFixed(5) ?? '-'}',
            a.potongGaji ? 'Ya' : '-',
            a.alasan ?? '',
          ],
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────
// Menyerahkan berkasnya
// ─────────────────────────────────────────────────────────────────────

/// Menyerahkan berkasnya — dibagikan di HP, diunduh di peramban.
///
/// Bedanya diurus impor bersyarat, bukan percabangan `kIsWeb` di sini:
/// `dart:io` tidak punya wujud apa pun di peramban, dan satu impor
/// tanpa syarat sudah cukup membuat seluruh konsol web gagal dibangun.
Future<void> serahkanBerkas({
  required Uint8List bytes,
  required String nama,
  required String tipe,
}) =>
    simpanLaluBagikan(bytes, nama, tipe);

const mimeXlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const mimePdf = 'application/pdf';
