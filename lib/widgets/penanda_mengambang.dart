import 'package:flutter/material.dart';

/// Pembungkus yang menaruh pilnya di bawah dan membiarkannya digeser.
///
/// Bawah, bukan atas: yang di atas menutupi judul layar dan tombol
/// kembali — dua hal yang dipakai terus-menerus. Yang di bawah memang
/// bisa bertabrakan dengan tombol mengambang tiap layar, dan justru
/// itulah sebabnya pilnya bisa dipindahkan: yang tahu mana yang sedang
/// terhalang cuma orang yang sedang memakainya.
///
/// Letaknya disimpan selama aplikasi berjalan saja, tidak disimpan ke
/// penyimpanan. Letak yang diingat lintas pemakaian berarti pil yang
/// suatu hari muncul di tempat yang tidak dipahami lagi asalnya.
class PenandaMengambang extends StatefulWidget {
  final Widget child;

  const PenandaMengambang({super.key, required this.child});

  @override
  State<PenandaMengambang> createState() => _PenandaMengambangState();
}

class _PenandaMengambangState extends State<PenandaMengambang> {
  static const _tepi = 12.0;

  final _kunciPil = GlobalKey();

  /// Kiri-atas pilnya di dalam Stack, atau null selama belum digeser —
  /// selama itu ia mengikuti tempat bawaannya di bawah tengah.
  Offset? _letak;
  Size? _ukuran;

  void _mulai() {
    final pil = _kunciPil.currentContext?.findRenderObject() as RenderBox?;
    final wadah = context.findRenderObject() as RenderBox?;
    if (pil == null || wadah == null) return;
    _ukuran = pil.size;
    // Digeser dari tempatnya yang sekarang, bukan melompat ke jari.
    _letak ??= wadah.globalToLocal(pil.localToGlobal(Offset.zero));
  }

  void _geser(DragUpdateDetails d, Size layar) {
    final ukuran = _ukuran;
    if (_letak == null || ukuran == null) return;
    final calon = _letak! + d.delta;
    setState(() {
      _letak = Offset(
        calon.dx.clamp(_tepi,
            (layar.width - ukuran.width - _tepi).clamp(_tepi, double.infinity)),
        calon.dy.clamp(_tepi,
            (layar.height - ukuran.height - _tepi)
                .clamp(_tepi, double.infinity)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ukurannya dari MediaQuery, BUKAN dari LayoutBuilder.
    //
    // Positioned harus menjadi anak LANGSUNG sebuah Stack: ia menempelkan
    // data posisinya ke render object induknya, dan LayoutBuilder punya
    // render object sendiri di antaranya. Yang terjadi bukan tata letak
    // yang meleset melainkan galat — dan di build release galat itu
    // digambar sebagai kotak abu-abu yang menutupi seluruh layar, di
    // setiap layar, karena widget ini dipasang di atas Navigator.
    //
    // Stack-nya memenuhi jendela, jadi ukuran jendela memang ukuran yang
    // dibutuhkan untuk menahan pilnya tetap di dalam layar.
    final layar = MediaQuery.sizeOf(context);

    // Lebarnya tetap dibatasi meski sudah digeser: Positioned yang cuma
    // menyebut kiri dan atas memberi ruang tak terbatas, dan teks yang
    // seharusnya dipendekkan malah melimpah keluar layar.
    final pil = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: layar.width - _tepi * 2),
      child: GestureDetector(
        onPanStart: (_) => _mulai(),
        onPanUpdate: (d) => _geser(d, layar),
        child: KeyedSubtree(key: _kunciPil, child: widget.child),
      ),
    );

    if (_letak == null) {
      return Positioned(
        left: _tepi,
        right: _tepi,
        bottom: _tepi,
        child: SafeArea(
          top: false,
          child: Align(alignment: Alignment.bottomCenter, child: pil),
        ),
      );
    }
    return Positioned(left: _letak!.dx, top: _letak!.dy, child: pil);
  }
}
