import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Grafik untuk Laporan Penjualan.
///
/// Dipisahkan dari layarnya karena isinya hampir seluruhnya urusan
/// menggambar — sumbu, label, warna — dan layarnya sudah penuh oleh
/// urusan lain: rentang tanggal, satuan waktu, dan empat pemanggilan
/// server yang harus disegarkan pada saat yang berbeda-beda.

/// Warna potongan, dipakai grafik lingkaran dan keterangannya.
///
/// Ditetapkan sebagai daftar, bukan diacak dari kuncinya. Warna yang
/// berpindah tiap kali layarnya dibuka membuat orang yang membandingkan
/// dua tangkapan layar menyimpulkan yang salah — dan laporan memang
/// dibaca dengan cara itu.
const _palet = [
  Color(0xFF6366F1),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFF0EA5E9),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFEF4444),
];

Color warnaPotong(int i) => _palet[i % _palet.length];

/// Garis tren sepanjang rentangnya.
///
/// Satu garis, bukan dua sumbu bertumpuk. Omzet dan jumlah pesanan
/// berbeda seribu kali besarnya; menggambar keduanya bersama membuat
/// yang kecil jadi garis datar di dasar grafik, dan yang terbaca cuma
/// satu di antaranya — sambil tetap memakan ruang untuk dua.
class GrafikTren extends StatelessWidget {
  /// Nilai per titik, urut dari yang paling awal.
  final List<double> nilai;

  /// Label sumbu bawah, sejajar dengan [nilai].
  final List<String> label;

  /// Ditulis di kotak sentuh — "Rp 1.240.000" atau "24 pesanan".
  final String Function(double) format;

  final Color warna;

  const GrafikTren({
    super.key,
    required this.nilai,
    required this.label,
    required this.format,
    this.warna = const Color(0xFF6366F1),
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final tertinggi =
        nilai.isEmpty ? 0.0 : nilai.reduce((a, b) => a > b ? a : b);

    // Atapnya sedikit di atas titik tertinggi, supaya puncaknya tidak
    // menempel ke tepi dan terpotong setengah.
    final atap = tertinggi <= 0 ? 1.0 : tertinggi * 1.15;

    // Label sumbu bawah dijarangkan sampai muat.
    //
    // Tiga puluh tanggal berjejal jadi satu pita hitam yang tidak
    // terbaca sebagai apa pun. Yang dibutuhkan dari sumbu ini cuma
    // penanda di mana awal dan akhirnya, bukan tiap titiknya.
    final langkah = (nilai.length / 6).ceil().clamp(1, 999);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: atap,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: atap / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: KaataTheme.borderOf(context),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= label.length) return const SizedBox.shrink();
                if (i % langkah != 0 && i != label.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label[i],
                      style: TextStyle(fontSize: 9.5, color: muted)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1F2937),
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${label[s.x.round().clamp(0, label.length - 1)]}\n'
                  '${format(s.y)}',
                  const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < nilai.length; i++)
                FlSpot(i.toDouble(), nilai[i]),
            ],
            isCurved: true,
            // Lengkungnya ditahan supaya tidak menukik di bawah nol.
            // Kurva yang "cantik" bisa menggambar penjualan minus pada
            // hari yang sebenarnya nol.
            preventCurveOverShooting: true,
            curveSmoothness: 0.22,
            color: warna,
            barWidth: 2.4,
            // Titiknya disembunyikan pada deret panjang: tiga puluh
            // bulatan di sepanjang garis menutupi garisnya sendiri.
            dotData: FlDotData(show: nilai.length <= 14),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [warna.withOpacity(0.28), warna.withOpacity(0.02)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Batang per jam, 24 jam penuh.
///
/// Jam yang kosong tetap digambar sebagai batang nol. Melompatinya
/// membuat sumbu waktunya tidak lagi seragam, dan jeda sepi tengah hari
/// — justru yang paling berarti untuk mengatur shift — hilang tanpa
/// bekas.
class GrafikJam extends StatelessWidget {
  /// 24 nilai, indeksnya jam WIB.
  final List<double> perJam;
  final String Function(int jam, double nilai) tooltip;

  const GrafikJam({super.key, required this.perJam, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final tertinggi = perJam.isEmpty ? 0.0 : perJam.reduce((a, b) => a > b ? a : b);
    final atap = tertinggi <= 0 ? 1.0 : tertinggi * 1.15;
    final warna = KaataTheme.brandOf(context);

    return BarChart(
      BarChartData(
        maxY: atap,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: atap / 3,
          getDrawingHorizontalLine: (_) => FlLine(
            color: KaataTheme.borderOf(context),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final jam = v.round();
                // Tiap tiga jam. Dua puluh empat angka berdempetan
                // berhenti terbaca sebagai angka.
                if (jam % 3 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('$jam',
                      style: TextStyle(fontSize: 9.5, color: muted)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1F2937),
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              tooltip(group.x, rod.toY),
              const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (var jam = 0; jam < perJam.length; jam++)
            BarChartGroupData(
              x: jam,
              barRods: [
                BarChartRodData(
                  toY: perJam[jam],
                  width: 7,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3)),
                  color: perJam[jam] >= tertinggi && tertinggi > 0
                      ? warna
                      : warna.withOpacity(0.45),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Lingkaran berlubang untuk pembagian omzet.
///
/// Berlubang, bukan penuh: bagian tengahnya dipakai menyebut totalnya,
/// dan tanpa total itu tiap potongan cuma bisa dibandingkan satu sama
/// lain — bukan dinilai besar atau kecil.
class GrafikPotong extends StatelessWidget {
  /// Nilai tiap potongan, urut dari yang terbesar.
  final List<double> nilai;
  final String tengahAtas;
  final String tengahBawah;

  const GrafikPotong({
    super.key,
    required this.nilai,
    required this.tengahAtas,
    required this.tengahBawah,
  });

  @override
  Widget build(BuildContext context) {
    final total = nilai.fold<double>(0, (a, b) => a + b);

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 52,
            startDegreeOffset: -90,
            sections: [
              for (var i = 0; i < nilai.length; i++)
                PieChartSectionData(
                  value: nilai[i],
                  color: warnaPotong(i),
                  radius: 22,
                  // Judulnya dimatikan: persennya sudah tertulis di
                  // keterangan di bawahnya, dan angka yang diulang di
                  // atas potongan setipis ini jatuh menimpa tetangganya.
                  showTitle: false,
                ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tengahAtas,
                style: TextStyle(
                    fontSize: 11, color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 2),
            Text(tengahBawah,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if (total <= 0)
              Text('belum ada',
                  style: TextStyle(
                      fontSize: 10.5, color: KaataTheme.mutedOf(context))),
          ],
        ),
      ],
    );
  }
}
