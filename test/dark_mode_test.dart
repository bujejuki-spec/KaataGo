import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/theme.dart';

/// Berkas yang warnanya memang harus tetap, apa pun temanya.
const _dikecualikan = {
  'lib/theme.dart',
  'lib/widgets/receipt_view.dart', // struk: dicetak & disimpan ke galeri
  'lib/widgets/kaata_qr_card.dart', // kartu QR berbingkai
  'lib/utils/table_qr_image.dart', // PDF
  'lib/screens/finance_report_screen.dart', // PDF
  'lib/screens/receipt_screen.dart',
  'lib/screens/customer_receipt_screen.dart',
};

/// Menjalankan [pemeriksa] dengan context di bawah [tema].
///
/// Temanya dipasang langsung lewat Theme(), bukan lewat themeMode di
/// MaterialApp: di lingkungan tes, kecerahan sistemnya selalu terang,
/// dan menyandarkan pemeriksaan pada penyetelan tidak langsung membuat
/// tesnya menguji harness-nya sendiri alih-alih warnanya.
Future<void> _diTema(
  WidgetTester tester,
  ThemeData tema,
  void Function(BuildContext context) pemeriksa,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Theme(
      data: tema,
      child: Builder(builder: (context) {
        pemeriksa(context);
        return const SizedBox.shrink();
      }),
    ),
  ));
}

void main() {
  test('tidak ada lagi abu-abu yang ditulis langsung di layar', () {
    // Colors.grey.shadeNNN dipilih untuk latar terang. Di tema gelap ia
    // jatuh nyaris tidak terbaca — dan yang paling sering memakainya
    // justru teks penjelas, yang memang sudah kecil.
    final pelanggar = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (_dikecualikan.contains(f.path)) continue;
      if (f.readAsStringSync().contains('Colors.grey.shade')) {
        pelanggar.add(f.path);
      }
    }
    expect(pelanggar, isEmpty,
        reason: 'pakai KaataTheme.mutedOf / softFillOf / borderOf');
  });

  testWidgets('token temanya menjawab berbeda di terang dan gelap',
      (tester) async {
    late Color terang, gelap;
    await _diTema(
        tester, KaataTheme.light(), (c) => terang = KaataTheme.surfaceOf(c));
    await _diTema(tester, KaataTheme.dark(), (c) => gelap = KaataTheme.surfaceOf(c));

    expect(terang, Colors.white);
    expect(gelap, isNot(Colors.white));
  });

  testWidgets('teks utama tidak pernah hitam di tema gelap', (tester) async {
    // Hitam di atas latar gelap bukan sekadar sulit dibaca — ia hilang.
    late Color gelap;
    await _diTema(tester, KaataTheme.dark(), (c) => gelap = KaataTheme.textOf(c));

    expect(gelap.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('teks redup tetap punya jarak dari latarnya', (tester) async {
    // Teks penjelas yang menyatu dengan latarnya sama saja dengan tidak
    // ditulis.
    late Color terang, gelap;
    await _diTema(tester, KaataTheme.light(), (c) => terang = KaataTheme.mutedOf(c));
    await _diTema(tester, KaataTheme.dark(), (c) => gelap = KaataTheme.mutedOf(c));

    expect(terang.computeLuminance(), lessThan(0.5));
    expect(gelap.computeLuminance(), greaterThan(0.2));
  });
}
