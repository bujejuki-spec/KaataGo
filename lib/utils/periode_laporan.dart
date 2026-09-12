import 'package:flutter/material.dart';

import '../widgets/app_toast.dart';

/// Panjang periode terjauh yang boleh diminta sekali jalan.
///
/// Jurnal GL dan Laporan Transaksi menarik setiap baris di rentangnya,
/// lalu menyusunnya jadi PDF. Rentang setahun pada merchant yang ramai
/// berarti puluhan ribu baris berjalan lewat jaringan dan menumpuk di
/// memori perangkat — dan yang menekan tombolnya menunggu lama sebelum
/// aplikasinya berhenti sendiri.
///
/// Sebulan, dihitung dari tanggal yang sama di bulan berikutnya: 14
/// Agustus paling jauh sampai 14 September.
const maksPeriodeLaporan = Duration(days: 31);

/// Batas akhir terjauh dari sebuah tanggal mulai.
///
/// Memakai tanggal yang sama di bulan berikutnya, bukan 30 hari mati —
/// orang membaca "sebulan" sebagai tanggal yang sama, dan Februari
/// membuat dua tafsir itu berbeda tiga hari.
DateTime batasAkhirPeriode(DateTime mulai) =>
    DateTime(mulai.year, mulai.month + 1, mulai.day);

/// Memilih periode, dengan batas sebulan yang ditegakkan.
///
/// Rentang yang lebih panjang tidak ditolak diam-diam: ujungnya dipotong
/// ke batasnya dan yang memilih diberi tahu. Penolakan tanpa penjelasan
/// membuat orang mencoba rentang yang sama berulang kali.
Future<DateTimeRange?> pilihPeriodeLaporan(
  BuildContext context, {
  required DateTime mulai,
  required DateTime akhir,
}) async {
  final dipilih = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime.now(),
    initialDateRange: DateTimeRange(start: mulai, end: akhir),
    helpText: 'Pilih periode (maks 1 bulan)',
  );
  if (dipilih == null) return null;

  final batas = batasAkhirPeriode(dipilih.start);
  if (!dipilih.end.isAfter(batas)) return dipilih;

  if (context.mounted) {
    showAppToast(context,
        'Periode paling panjang 1 bulan — diakhiri di ${_tanggal(batas)}.');
  }
  return DateTimeRange(start: dipilih.start, end: batas);
}

String _tanggal(DateTime t) => '${t.day}/${t.month}/${t.year}';
