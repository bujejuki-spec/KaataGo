import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/teks_pengumuman.dart';

/// Isi pengumuman rilis di kotak masuk.
///
/// Catatannya ditulis terbungkus pada lebar berkas supaya enak dibaca di
/// editor. Dikirim apa adanya ke layar ponsel, pembungkusan itu berbalik
/// jadi perusak: barisnya dibungkus ulang oleh lebar layar, sementara
/// tanda hubung dan patahan baris dari berkasnya tetap tinggal di tengah
/// kalimat.
void main() {
  const isi = 'Versi baru KaataGo sudah bisa diunduh. Yang berubah:\n'
      '\n'
      '- Setor tunai yang disetujui kini mendarat di Saldo Bank\n'
      '  Perusahaan, dan cash pickup di Saldo Cash Perusahaan\n'
      '- Selisih kasir yang dilunasi lewat transfer ikut masuk Saldo Bank\n';

  testWidgets('butirnya jadi daftar, bukan paragraf patah', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: TeksPengumuman(isi))),
    ));

    // Sambungan barisnya menyatu kembali: yang tampil satu kalimat utuh,
    // dan layarnya sendiri yang memutuskan di mana ia dibungkus.
    expect(
      find.text('Setor tunai yang disetujui kini mendarat di Saldo Bank '
          'Perusahaan, dan cash pickup di Saldo Cash Perusahaan'),
      findsOneWidget,
    );

    // Tanda hubungnya tidak ikut jadi teks — ia digantikan titik butir.
    expect(find.textContaining('- Setor tunai'), findsNothing);

    // Kalimat pembuka tetap berdiri sendiri sebagai paragraf.
    expect(find.text('Versi baru KaataGo sudah bisa diunduh. Yang berubah:'),
        findsOneWidget);
  });

  test('pratinjaunya diratakan jadi satu kalimat', () {
    final ringkas = ringkasPengumuman(isi);
    expect(ringkas, isNot(contains('\n')));
    expect(ringkas, isNot(contains('- ')));
    expect(ringkas, startsWith('Versi baru KaataGo'));
  });

  test('teks tanpa butir tidak berubah isinya', () {
    const biasa = 'Promo akhir pekan dimulai besok.';
    expect(ringkasPengumuman(biasa), biasa);
  });

  group('sumbernya ikut dirapikan', () {
    // Yang dirapikan di layar menolong pengumuman yang sudah terlanjur
    // ada di kotak masuk orang. Yang dirapikan di sini menolong yang
    // belum terkirim — termasuk saat dibaca di tempat lain, misalnya
    // notifikasi.
    final skrip = File('scripts/catatan_rilis.py').readAsStringSync();

    test('baris sambungan disatukan sebelum dikirim', () {
      expect(skrip, contains('poin[-1] = f"{poin[-1]} {bersih}"'));
      expect(skrip, contains('bersih.startswith(("- ", "* "))'));
    });
  });
}
