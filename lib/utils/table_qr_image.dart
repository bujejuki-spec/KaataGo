import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/app_toast.dart';
import 'gallery_saver.dart';

/// Satu meja: yang dibutuhkan untuk menggambar satu kartu QR.
class TableQrCard {
  final String restoName;
  final String table;
  final String payload;

  const TableQrCard({
    required this.restoName,
    required this.table,
    required this.payload,
  });

  /// Nama berkas yang tetap enak dibaca di galeri dan di share sheet.
  String get fileName {
    final safe = table.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    return 'qr-meja-$safe.png';
  }
}

/// Batas jumlah meja yang boleh dibuat sekali jalan.
///
/// Bukan batas teknis: 500 kartu berarti 500 rasterisasi dan 500 gambar
/// di galeri, yang hampir pasti bukan yang dimaksud orangnya waktu salah
/// ketik "1 sampai 1000".
const kMaxTableBatch = 100;

/// Menjabarkan rentang nomor meja jadi daftar labelnya.
///
/// Nomornya diberi nol di depan mengikuti nomor terbesar, jadi meja 7 dan
/// meja 12 sama-sama jadi "07" dan "12". Tanpa itu daftar QR di galeri
/// terurut 1, 10, 11, 2 — dan yang memasangnya di meja harus membaca
/// satu per satu.
///
/// Rentang yang tidak masuk akal mengembalikan daftar kosong, dan itulah
/// yang mematikan tombol-tombolnya di layar.
List<String> tableLabelRange({String prefix = '', required int from, required int to}) {
  if (from < 1 || to < from || to - from + 1 > kMaxTableBatch) return const [];
  final width = to.toString().length;
  return [
    for (var i = from; i <= to; i++) '$prefix${i.toString().padLeft(width, '0')}',
  ];
}

const _brand = PdfColor.fromInt(0xFF4F46E5);
const _brandDark = PdfColor.fromInt(0xFF3730A3);
const _accent = PdfColor.fromInt(0xFFF59E0B);

/// Ukuran kartunya dalam titik PDF. Perbandingannya sengaja mendekati
/// tent card 10x13 cm yang biasa dicetak lalu ditaruh berdiri di meja.
const _cardWidth = 384.0;
const _cardHeight = 512.0;

/// Menyimpan satu kartu QR ke galeri.
Future<bool> saveTableQrToGallery(BuildContext context, TableQrCard card) async {
  final Uint8List bytes;
  try {
    bytes = await renderTableQrPng(card);
  } catch (e) {
    if (!context.mounted) return false;
    showAppToast(context, 'Gagal membuat QR: $e', isError: true);
    return false;
  }

  if (!context.mounted) return false;
  return savePngToGallery(
    context,
    bytes,
    successMessage: 'QR Meja ${card.table} tersimpan di galeri (album KaataGo).',
    failurePrefix: 'Gagal menyimpan QR',
  );
}

/// Menyimpan sekumpulan kartu QR sekaligus.
///
/// Izin galerinya diminta sekali di depan, bukan per kartu — 40 meja
/// berarti 40 permintaan izin kalau tiap kartu mengurus dirinya sendiri.
///
/// [onProgress] dipanggil tiap satu kartu selesai supaya layarnya bisa
/// menunjukkan hitungannya; menyimpan 40 gambar makan waktu belasan
/// detik, dan tanpa angka yang bergerak orang akan mengira aplikasinya
/// menggantung.
///
/// Mengembalikan jumlah yang benar-benar tersimpan. Kartu yang gagal
/// tidak menghentikan sisanya: lebih baik 39 meja terpasang QR daripada
/// batal semua gara-gara satu.
Future<int> saveTableQrBatchToGallery(
  BuildContext context,
  List<TableQrCard> cards, {
  void Function(int done)? onProgress,
}) async {
  final toast = AppToast.of(context);

  if (!await ensureGalleryAccess(context)) return 0;

  var saved = 0;
  final failed = <String>[];
  for (final card in cards) {
    try {
      await putPngInGallery(await renderTableQrPng(card));
      saved++;
    } catch (_) {
      failed.add(card.table);
    }
    onProgress?.call(saved + failed.length);
  }

  if (failed.isEmpty) {
    toast.show('$saved QR Meja tersimpan di galeri (album KaataGo).');
  } else {
    toast.show(
      '$saved tersimpan, ${failed.length} gagal (meja ${failed.take(5).join(', ')}'
      '${failed.length > 5 ? ', ...' : ''}).',
      isError: true,
    );
  }
  return saved;
}

/// Mengirim kartu-kartunya ke dialog cetak — satu meja satu halaman.
Future<void> printTableQrs(BuildContext context, List<TableQrCard> cards) async {
  try {
    final doc = await _buildDoc(cards);
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: cards.length == 1 ? 'qr-meja-${cards.first.table}' : 'qr-meja-semua',
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppToast(context, 'Gagal mencetak QR: $e', isError: true);
  }
}

/// Membagikan kartunya lewat share sheet (WhatsApp, Drive, dan lainnya).
Future<void> shareTableQrs(BuildContext context, List<TableQrCard> cards) async {
  try {
    final files = <XFile>[];
    for (final card in cards) {
      files.add(XFile.fromData(
        await renderTableQrPng(card),
        mimeType: 'image/png',
        name: card.fileName,
      ));
    }
    await Share.shareXFiles(
      files,
      text: cards.length == 1
          ? 'QR Meja ${cards.first.table} — ${cards.first.restoName}'
          : 'QR Meja ${cards.first.restoName} (${cards.length} meja)',
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppToast(context, 'Gagal membagikan QR: $e', isError: true);
  }
}

/// Menggambar satu kartu jadi PNG.
///
/// Lewat PDF yang dirasterkan, bukan tangkapan layar widget-nya: kartu
/// yang tersimpan harus utuh dan sama besar untuk semua meja, sementara
/// tangkapan layar ikut ukuran dan kerapatan piksel HP yang kebetulan
/// dipakai — dan kartu di halaman gulir bisa terpotong.
Future<Uint8List> renderTableQrPng(TableQrCard card) async {
  final doc = await _buildDoc([card]);
  // 200 dpi: cukup rapat supaya QR-nya tetap terbaca pemindai walau
  // gambarnya dicetak ulang dari galeri.
  final raster = await Printing.raster(await doc.save(), pages: [0], dpi: 200).first;
  return raster.toPng();
}

Future<pw.Document> _buildDoc(List<TableQrCard> cards) async {
  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/icon/kaata_icon.png')).buffer.asUint8List(),
  );

  final doc = pw.Document();
  for (final card in cards) {
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(_cardWidth, _cardHeight, marginAll: 0),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (context) => _card(card, logo),
      ),
    );
  }
  return doc;
}

pw.Widget _card(TableQrCard card, pw.MemoryImage logo) {
  return pw.Container(
    width: _cardWidth,
    height: _cardHeight,
    decoration: const pw.BoxDecoration(
      gradient: pw.LinearGradient(
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
        colors: [_brand, _brandDark],
      ),
    ),
    child: pw.Stack(
      children: [
        // Siku amber di keempat pojok. Sekadar garis lurus di dalam
        // bidang ungu akan terbaca sebagai bingkai kedua yang menyempit;
        // siku terputus di tengah sisi justru membingkai isinya tanpa
        // mengecilkan ruang QR-nya.
        ..._corners(),
        pw.Padding(
          padding: const pw.EdgeInsets.all(26),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(logo, width: 22, height: 22),
                  pw.SizedBox(width: 7),
                  pw.Text(
                    'KaataGo',
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'PESAN SENDIRI DARI MEJA',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: _accent,
                  letterSpacing: 1.8,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Expanded(child: _innerCard(card)),
              pw.SizedBox(height: 12),
              pw.Text(
                'Arahkan kamera HP ke kode di atas',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _innerCard(TableQrCard card) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 18),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: pw.BorderRadius.circular(20),
    ),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          card.restoName,
          textAlign: pw.TextAlign.center,
          maxLines: 2,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Scan untuk pesan dari meja ini',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 14),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: card.payload,
          width: 196,
          height: 196,
          // Warna mereknya, bukan hitam. Kontrasnya terhadap putih masih
          // jauh di atas ambang yang dibutuhkan pemindai.
          color: _brandDark,
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 7),
          decoration: pw.BoxDecoration(
            color: _accent,
            borderRadius: pw.BorderRadius.circular(22),
          ),
          child: pw.Text(
            'MEJA ${card.table}',
            style: pw.TextStyle(
              fontSize: 19,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Empat siku amber, satu di tiap pojok kartu.
List<pw.Widget> _corners() {
  const inset = 12.0;
  const arm = 34.0;
  const thick = 3.0;

  pw.Widget bar(double w, double h) => pw.Container(
        width: w,
        height: h,
        decoration: pw.BoxDecoration(
          color: _accent,
          borderRadius: pw.BorderRadius.circular(thick / 2),
        ),
      );

  return [
    // Kiri atas
    pw.Positioned(left: inset, top: inset, child: bar(arm, thick)),
    pw.Positioned(left: inset, top: inset, child: bar(thick, arm)),
    // Kanan atas
    pw.Positioned(right: inset, top: inset, child: bar(arm, thick)),
    pw.Positioned(right: inset, top: inset, child: bar(thick, arm)),
    // Kiri bawah
    pw.Positioned(left: inset, bottom: inset, child: bar(arm, thick)),
    pw.Positioned(left: inset, bottom: inset, child: bar(thick, arm)),
    // Kanan bawah
    pw.Positioned(right: inset, bottom: inset, child: bar(arm, thick)),
    pw.Positioned(right: inset, bottom: inset, child: bar(thick, arm)),
  ];
}
