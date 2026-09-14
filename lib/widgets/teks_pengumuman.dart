import 'package:flutter/material.dart';

import '../theme.dart';

/// Isi pengumuman, dengan daftar berbutirnya ditampilkan sebagai daftar.
///
/// Catatan rilis ditulis sebagai daftar berbutir dan dibungkus pada
/// lebar berkasnya supaya enak dibaca di editor:
///
/// ```
/// - Setor tunai yang disetujui kini mendarat di Saldo Bank Perusahaan,
///   dan cash pickup di Saldo Cash Perusahaan
/// ```
///
/// Dikirim apa adanya ke layar ponsel, pembungkusan itu berbalik jadi
/// perusak: barisnya dibungkus ulang oleh lebar layar, sementara tanda
/// hubung dan spasi menjorok dari berkasnya tetap tinggal di tengah
/// kalimat. Yang terlihat adalah paragraf yang patah di tempat acak.
///
/// Widget ini merapikannya saat ditampilkan — bukan saat disimpan.
/// Pengumuman yang sudah terlanjur ada di kotak masuk orang tidak bisa
/// ditulis ulang, dan justru itu yang paling banyak dibaca.
class TeksPengumuman extends StatelessWidget {
  final String isi;
  final double fontSize;

  const TeksPengumuman(this.isi, {super.key, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    final bagian = _pecah(isi);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < bagian.length; i++) ...[
          if (i > 0) SizedBox(height: bagian[i].butir ? 6 : 12),
          if (bagian[i].butir)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Sejajar dengan baris pertama teksnya, bukan dengan
                  // tengah kotaknya: titiknya kecil, dan yang menempel
                  // di tengah terlihat melayang di sebelah kalimat
                  // yang panjangnya dua baris.
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: KaataTheme.brandOf(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    _bertebal(bagian[i].teks,
                        TextStyle(fontSize: fontSize, height: 1.45)),
                  ),
                ),
              ],
            )
          else
            Text.rich(
              _bertebal(bagian[i].teks,
                  TextStyle(fontSize: fontSize, height: 1.45)),
            ),
        ],
      ],
    );
  }
}

/// Mengubah `**begini**` jadi benar-benar tebal.
///
/// ── Kenapa perlu ─────────────────────────────────────────────────────
///
/// Catatan rilis ditulis di berkas Markdown, tempat `**` memang berarti
/// tebal. Yang membacanya di kotak masuk bukan Markdown melainkan satu
/// `Text` biasa — jadi bintangnya muncul apa adanya, dan kalimat yang
/// justru ingin ditonjolkan berubah jadi kalimat yang terlihat rusak.
///
/// Diterjemahkan saat DITAMPILKAN, bukan saat disimpan. Pengumuman yang
/// sudah terlanjur ada di kotak masuk orang tidak bisa ditulis ulang,
/// dan justru itu yang paling banyak dibaca — termasuk yang sudah
/// terkirim sebelum berkas ini ada.
///
/// Yang dikenali cuma `**`. Bukan karena yang lain tidak berguna,
/// melainkan karena catatan rilisnya memang hanya memakai itu, dan
/// penerjemah Markdown penuh di sini berarti tiap bintang, garis bawah,
/// dan tanda kurung yang kebetulan ditulis orang berubah jadi gaya yang
/// tidak diniatkan siapa pun.
///
/// Bintang yang tidak berpasangan dibiarkan apa adanya — memakan
/// separuh kalimat karena satu bintang nyasar lebih buruk daripada
/// menampilkan bintangnya.
TextSpan _bertebal(String teks, TextStyle dasar) {
  final pola = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
  final anak = <TextSpan>[];
  var i = 0;

  for (final m in pola.allMatches(teks)) {
    if (m.start > i) anak.add(TextSpan(text: teks.substring(i, m.start)));
    anak.add(TextSpan(
      text: m.group(1),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ));
    i = m.end;
  }
  if (i < teks.length) anak.add(TextSpan(text: teks.substring(i)));

  return TextSpan(style: dasar, children: anak);
}

/// Satu paragraf atau satu butir daftar.
class _Bagian {
  final String teks;
  final bool butir;

  const _Bagian(this.teks, {required this.butir});
}

/// Menyatukan kembali baris yang terbungkus, dan menandai mana yang butir.
///
/// Baris yang diawali '-', '*', atau '•' memulai butir baru. Baris
/// berikutnya yang bukan pembuka butir adalah sambungan baris
/// sebelumnya — itulah pembungkusan dari berkasnya, dan itu yang harus
/// dihapus supaya layarnya membungkus sendiri sesuai lebarnya.
List<_Bagian> _pecah(String isi) {
  final hasil = <_Bagian>[];

  for (final baris in isi.split('\n')) {
    final bersih = baris.trim();

    if (bersih.isEmpty) {
      // Baris kosong memutus sambungan: paragraf berikutnya berdiri
      // sendiri, tidak menempel ke butir terakhir.
      if (hasil.isNotEmpty) hasil.add(const _Bagian('', butir: false));
      continue;
    }

    final pembukaButir = RegExp(r'^[-*•]\s+');
    if (pembukaButir.hasMatch(bersih)) {
      hasil.add(_Bagian(bersih.replaceFirst(pembukaButir, ''), butir: true));
      continue;
    }

    if (hasil.isEmpty || hasil.last.teks.isEmpty) {
      hasil.add(_Bagian(bersih, butir: false));
    } else {
      final sebelum = hasil.removeLast();
      hasil.add(_Bagian('${sebelum.teks} $bersih', butir: sebelum.butir));
    }
  }

  return [for (final b in hasil) if (b.teks.isNotEmpty) b];
}

/// Isi pengumuman untuk pratinjau satu-dua baris di daftar.
///
/// Daftar berbutirnya diratakan jadi satu kalimat panjang: pratinjau
/// yang memuat tanda hubung dan patahan barisnya terbaca seperti teks
/// rusak, dan dua baris pertama jadi terbuang untuk tanda baca.
String ringkasPengumuman(String isi) => _pecah(isi)
    .map((b) => b.teks.replaceAll(RegExp(r'\*\*(.+?)\*\*', dotAll: true),
        r'$1'))
    .join(' · ');
