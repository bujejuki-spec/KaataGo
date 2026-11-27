import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Batal tidak boleh berdiri di atas tombol yang justru didatangi
/// orangnya.
///
/// Baris `actions` milik AlertDialog melipat jadi kolom begitu kedua
/// labelnya tidak muat berdampingan — dan saat melipat, urutannya
/// mengikuti daftar. Di layar sempit, atau di popup web yang lebarnya
/// dibatasi, itu menaruh Batal di atas Simpan. [DialogActions] menyusun
/// keduanya sendiri supaya urutannya tetap disengaja di lebar berapa
/// pun.
/// Isi satu blok `actions: [ ... ]`, dihitung sampai kurung penutupnya.
///
/// Dulu penutupnya dicari sebagai teks `'\n      ],'` — enam spasi
/// persis — dan kalau tidak ketemu, yang dibaca 400 karakter pertama
/// sesudahnya. Padahal dialog yang bersarang lebih dalam menutup di
/// indentasi lain: 54 dari 104 blok di `lib/` tidak pernah cocok, jadi
/// separuh lebih diperiksa lewat jendela sembarang yang bisa melewati
/// ujung daftarnya ke kode yang tidak bersangkutan, atau berhenti
/// sebelum tombol batalnya. Penjaga yang membaca blok yang salah bisa
/// meloloskan yang nakal sekaligus menuduh yang tidak.
///
/// Dan jendela itu melempar RangeError pada berkas yang sisanya kurang
/// dari 400 karakter — yang menemukannya dialog pendek yang baru
/// ditambahkan, bukan pengujian ini.
///
/// Menghitung kurung itu tepat. Literal dan komentar dilewati supaya
/// `'[x]'` atau `// [DialogActions]` tidak ikut terhitung.
String? blokActions(String isi, int mulai) {
  var dalam = 1;
  for (var i = mulai; i < isi.length; i++) {
    final c = isi[i];
    if (c == "'" || c == '"') {
      i++;
      while (i < isi.length && isi[i] != c) {
        if (isi[i] == r'\') i++;
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < isi.length && isi[i + 1] == '/') {
      while (i < isi.length && isi[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '[') {
      dalam++;
    } else if (c == ']') {
      dalam--;
      if (dalam == 0) return isi.substring(mulai, i);
    }
  }
  return null;
}

void main() {
  final berkas = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('dialog_actions.dart'));

  test('tidak ada dialog yang menyusun Batal sendiri di baris actions', () {
    final nakal = <String>[];

    for (final f in berkas) {
      final isi = f.readAsStringSync();
      for (final m in RegExp(r'actions: \[').allMatches(isi)) {
        // Isi blok actions-nya saja, sampai kurung penutupnya.
        final blok = blokActions(isi, m.end);
        if (blok == null) {
          // Kurungnya tidak pernah tertutup: itu berkas yang tidak akan
          // terkompilasi, dan bukan urusan pengujian ini — tapi juga
          // tidak boleh lolos tanpa suara.
          nakal.add('${f.path} (blok actions tidak tertutup)');
          continue;
        }

        // Bukan cuma kata "Batal".
        //
        // Penjaga ini dulu hanya mengenal satu kata, dan dialog
        // "Daftarkan wajahmu" lolos dengan tombol bernama "Nanti" —
        // melipat persis seperti yang mau dicegah, dan yang menemukannya
        // tangkapan layar dari HP orang. Yang menentukan bukan katanya,
        // melainkan perannya: tombol yang membatalkan, disebut apa pun.
        const kataBatal = [
          'Batal',
          'Nanti',
          'Lain kali',
          'Tidak',
          'Jangan',
          'Belum',
        ];
        final adaBatal = kataBatal.any((k) => blok.contains("Text('$k')"));
        if (!adaBatal) continue;

        // Batal sendirian itu dialog pemberitahuan, bukan pilihan —
        // tidak ada yang bisa terbalik urutannya.
        final tombol =
            RegExp(r'(TextButton|FilledButton|OutlinedButton)\(')
                .allMatches(blok)
                .toList();
        if (tombol.length < 2) continue;

        // Yang dijaga URUTANNYA, bukan widget yang dipakai.
        //
        // [DialogActions] memenuhinya karena bentuknya, tapi ia cuma
        // menampung satu konfirmasi dan satu batal. Dialog "Selisih
        // Lebih" punya dua pilihan yang berbeda akibatnya ditambah
        // batal, jadi ia menyusun Column-nya sendiri — dengan Batal
        // sudah paling bawah. Menuntutnya memakai DialogActions berarti
        // merusak dialog yang sudah benar demi hurufnya aturan.
        //
        // Jadi yang ditanyakan: tombol batalnya yang terakhir?
        final batalnya = kataBatal
            .map((k) => blok.indexOf("Text('$k')"))
            .where((i) => i >= 0)
            .reduce((a, b) => a > b ? a : b);
        if (batalnya > tombol.last.start) continue;

        final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
        nakal.add('${f.path}:$baris');
      }
    }

    expect(nakal, isEmpty,
        reason: 'pakai DialogActions supaya Batal tetap di bawah: '
            '${nakal.join(', ')}');
  });

  // Warna tombol adalah bahasa yang sudah dipakai seluruh aplikasi
  // untuk membedakan tindakan biasa dari yang merusak. Tombol simpan
  // berwarna lain membuat satu dialog tampak beda jenis dari semua
  // dialog lainnya — dan warna bagian (hijau untuk penarikan, ungu
  // untuk petty cash) sudah punya tempatnya sendiri di ikon dan kotak
  // keterangan.
  test('tombol utama memakai warna tema, kecuali yang merusak', () {
    final nakal = <String>[];
    for (final f in berkas) {
      final isi = f.readAsStringSync();
      for (final m
          in RegExp(r'FilledButton\.styleFrom\(backgroundColor: ([^)]+)\)')
              .allMatches(isi)) {
        final warna = m.group(1)!;
        if (warna.contains('red')) continue;
        final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
        nakal.add('${f.path}:$baris ($warna)');
      }
    }
    expect(nakal, isEmpty, reason: nakal.join(', '));
  });
}
