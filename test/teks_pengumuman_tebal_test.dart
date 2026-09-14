import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/teks_pengumuman.dart';

void main() {
  testWidgets('bintang tidak muncul di layar, tebalnya yang muncul',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TeksPengumuman(
            '- **Pengenalan wajah** diganti dengan model terlatih'),
      ),
    ));

    final teks = tester.widget<Text>(find.byType(Text));
    final span = teks.textSpan! as TextSpan;

    final datar = span.toPlainText();
    expect(datar, isNot(contains('*')),
        reason: 'Bintangnya masih ikut tergambar di layar.');
    expect(datar, contains('Pengenalan wajah'));

    final tebal = (span.children!)
        .whereType<TextSpan>()
        .where((c) => c.style?.fontWeight == FontWeight.bold)
        .map((c) => c.text)
        .toList();
    expect(tebal, ['Pengenalan wajah']);
  });

  testWidgets('bintang nyasar dibiarkan, tidak memakan separuh kalimat',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TeksPengumuman('Diskon **50% untuk bulan ini')),
    ));
    final span =
        tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
    expect(span.toPlainText(), 'Diskon **50% untuk bulan ini');
  });
}
