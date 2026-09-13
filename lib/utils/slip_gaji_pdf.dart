import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/absensi.dart';
import 'kode_bank.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tgl = DateFormat('d MMMM yyyy', 'id_ID');

/// Slip gaji satu orang, satu periode.
///
/// Potongannya dirinci baris per baris, bukan disebut satu angka "total
/// potongan". Yang menerima slip dengan satu angka potongan tidak punya
/// cara memeriksanya selain bertanya — dan yang ditanya adalah orang
/// yang menentukan gajinya.
Future<Uint8List> pdfSlipGaji({
  required String namaMerchant,
  required BarisPayroll slip,
  required DateTime mulai,
  required DateTime akhir,
  required AturanGaji aturan,
}) async {
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Slip Gaji',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(namaMerchant,
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Periode',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600)),
                  pw.Text('${_tgl.format(mulai)} – ${_tgl.format(akhir)}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 10),
          _baris('Nama', slip.nama),
          _baris('Peran', slip.peran),
          if (slip.accountNumber?.isNotEmpty == true) ...[
            _baris('Bank', bankBerkode(slip.bankName)),
            _baris('No. rekening', slip.accountNumber!),
            if (slip.accountHolder?.isNotEmpty == true)
              _baris('Atas nama', slip.accountHolder!),
          ],
          pw.SizedBox(height: 16),
          pw.Text('Kehadiran',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: const [
              'Hari kerja',
              'Hadir',
              'Izin',
              'Sakit',
              'Cuti',
              'Alpa',
              'Dipotong'
            ],
            data: [
              [
                '${slip.hariKerja}',
                '${slip.hadir}',
                '${slip.izin}',
                '${slip.sakit}',
                '${slip.cuti}',
                '${slip.alpa}',
                '${slip.hariPotong} hari',
              ]
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _blok('Penerimaan', [
                  ('Gaji pokok', slip.gajiPokok),
                  if (slip.tunjangan > 0) ('Tunjangan', slip.tunjangan),
                ]),
              ),
              pw.SizedBox(width: 18),
              pw.Expanded(
                child: _blok('Potongan', [
                  ('Tidak masuk (${slip.hariPotong} hari)', slip.potonganAbsen),
                  if (slip.potonganBpjsKesehatan > 0)
                    ('BPJS Kesehatan', slip.potonganBpjsKesehatan),
                  if (slip.potonganBpjsTk > 0)
                    ('BPJS Ketenagakerjaan', slip.potonganBpjsTk),
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Gaji bersih',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(_rp.format(slip.gajiBersih),
                    style: pw.TextStyle(
                        fontSize: 15, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Text(
            'Dihitung otomatis dari absensi yang tercatat: gaji pokok dibagi '
            '${aturan.hariKerjaPeriode} hari kerja, dikali jumlah hari yang '
            'ditandai memotong gaji. Dokumen ini dibuat sistem dan sah tanpa '
            'tanda tangan.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _baris(String label, String nilai) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(label,
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700)),
          ),
          pw.Expanded(
              child: pw.Text(nilai, style: const pw.TextStyle(fontSize: 10))),
        ],
      ),
    );

pw.Widget _blok(String judul, List<(String, int)> isi) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(judul,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (final (label, nilai) in isi)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(label,
                      style: const pw.TextStyle(fontSize: 9.5)),
                ),
                pw.Text(_rp.format(nilai),
                    style: const pw.TextStyle(fontSize: 9.5)),
              ],
            ),
          ),
        if (isi.isEmpty)
          pw.Text('—', style: const pw.TextStyle(fontSize: 9.5)),
      ],
    );
