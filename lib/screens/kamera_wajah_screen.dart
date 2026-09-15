
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Memotret wajah di dalam aplikasi, dengan kamera depan yang benar-benar
/// depan.
///
/// ── Kenapa tidak memakai image_picker seperti sebelumnya ─────────────
///
/// image_picker menyerahkan pekerjaannya ke aplikasi kamera bawaan HP
/// lewat ACTION_IMAGE_CAPTURE, dan `preferredCameraDevice: front` cuma
/// ikut sebagai SARAN di dalam intent-nya. Aplikasi kamera boleh
/// mengabaikannya, dan hampir semua aplikasi kamera pabrikan memang
/// mengabaikannya.
///
/// Akibatnya kecil tapi berulang: tiap pagi, tiap orang, membalik
/// kameranya sendiri sebelum bisa absen — dan sebagian memotret wajahnya
/// dengan kamera belakang tanpa sadar, lalu bertanya-tanya kenapa
/// absennya ditolak.
///
/// Di sini kameranya dipilih sendiri, jadi tidak ada yang bisa
/// mengabaikan pilihannya.
///
/// ── Kembaliannya ─────────────────────────────────────────────────────
///
/// Jalur berkas foto, atau null kalau dibatalkan — bentuk yang sama
/// dengan yang dulu dikembalikan image_picker, supaya yang memanggilnya
/// tidak perlu tahu bedanya.
class KameraWajahScreen extends StatefulWidget {
  /// Ditampilkan di atas pratinjau. Menyebut untuk apa fotonya diambil,
  /// karena kamera yang terbuka tanpa keterangan terbaca seperti
  /// aplikasi yang salah membuka sesuatu.
  final String petunjuk;

  const KameraWajahScreen({super.key, required this.petunjuk});

  @override
  State<KameraWajahScreen> createState() => _KameraWajahScreenState();
}

class _KameraWajahScreenState extends State<KameraWajahScreen> {
  CameraController? _kamera;
  String? _galat;
  bool _memotret = false;

  @override
  void initState() {
    super.initState();
    _siapkan();
  }

  @override
  void dispose() {
    _kamera?.dispose();
    super.dispose();
  }

  Future<void> _siapkan() async {
    try {
      final daftar = await availableCameras();
      if (daftar.isEmpty) {
        throw CameraException('kosong', 'Tidak ada kamera di perangkat ini.');
      }

      // Depan kalau ada; kalau tidak ada, yang pertama.
      //
      // Tablet kasir kadang memang tidak punya kamera depan. Menolak
      // membuka kamera sama sekali di situ berarti absennya mati total,
      // padahal memotret dengan kamera yang ada masih menghasilkan
      // wajah yang bisa dicocokkan.
      final pilihan = daftar.firstWhere(
        (k) => k.lensDirection == CameraLensDirection.front,
        orElse: () => daftar.first,
      );

      final kamera = CameraController(
        pilihan,
        // Sedang, bukan tertinggi. Yang dibutuhkan model cuma 160×160
        // piksel; resolusi tertinggi hanya memperlambat pengambilannya
        // dan memperbesar berkas yang harus diunggah lewat jaringan
        // warung.
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await kamera.initialize();
      if (!mounted) {
        await kamera.dispose();
        return;
      }
      setState(() => _kamera = kamera);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _galat = e.description ?? 'Kamera tidak bisa dibuka.');
      }
    } catch (_) {
      if (mounted) setState(() => _galat = 'Kamera tidak bisa dibuka.');
    }
  }

  Future<void> _potret() async {
    final kamera = _kamera;
    if (kamera == null || _memotret) return;

    setState(() => _memotret = true);
    try {
      final foto = await kamera.takePicture();
      if (mounted) Navigator.pop(context, foto.path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _memotret = false;
          _galat = 'Gagal mengambil foto. Coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kamera = _kamera;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Ambil Foto Wajah'),
      ),
      body: _galat != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined,
                        size: 40, color: Colors.white54),
                    const SizedBox(height: 14),
                    Text(_galat!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () {
                        setState(() => _galat = null);
                        _siapkan();
                      },
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            )
          : kamera == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1 / kamera.value.aspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(kamera),
                              // Bingkai kepala, supaya orangnya tahu
                              // harus berdiri di mana.
                              //
                              // Tanpa ini tiap orang menebak sendiri:
                              // ada yang terlalu jauh sampai wajahnya
                              // cuma sekian puluh piksel, ada yang
                              // terlalu dekat sampai dahinya terpotong.
                              // Keduanya menghasilkan sidik yang
                              // berbeda dari foto acuannya — dan yang
                              // muncul ke orangnya bukan "posisimu
                              // kurang pas" melainkan "wajahnya tidak
                              // cocok", yang terbaca seperti tuduhan.
                              const IgnorePointer(
                                child: _PanduanKepala(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                      color: Colors.black,
                      child: Column(
                        children: [
                          Text(
                            'Letakkan kepalamu di dalam bingkai. '
                            '${widget.petunjuk}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4),
                          ),
                          const SizedBox(height: 18),
                          // Tombolnya besar dan di tengah, seperti
                          // kamera mana pun. Yang memakainya sedang
                          // berdiri di depan pintu merchant jam tujuh
                          // pagi, bukan duduk mempelajari layarnya.
                          GestureDetector(
                            onTap: _memotret ? null : _potret,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _memotret
                                    ? Colors.white24
                                    : Colors.white,
                                border: Border.all(
                                    color: KaataTheme.brand, width: 4),
                              ),
                              child: _memotret
                                  ? const Padding(
                                      padding: EdgeInsets.all(22),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.camera_alt,
                                      color: Colors.black87, size: 30),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Membuka kameranya dan mengembalikan jalur fotonya.
///
/// Berdiri sebagai fungsi supaya yang memanggilnya tidak perlu tahu ada
/// layar di baliknya — bentuknya sama dengan `ImagePicker().pickImage`
/// yang dulu dipakai di tempat yang sama.
Future<String?> ambilFotoWajah(BuildContext context,
        {required String petunjuk}) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => KameraWajahScreen(petunjuk: petunjuk),
      ),
    );


/// Bingkai lonjong tempat kepala diletakkan.
///
/// Di luar bingkainya digelapkan, di dalamnya tetap terang. Itu yang
/// membuat panduannya terbaca tanpa satu kata pun: mata mengikuti bagian
/// yang terang, dan bagian yang terang persis seukuran kepala.
///
/// Ukurannya bukan hiasan. Lebarnya 62% lebar bingkai dan tingginya 1,32
/// kali lebarnya — kira-kira proporsi kepala manusia dilihat dari depan,
/// pada jarak yang membuat wajahnya cukup besar untuk dipindai tapi
/// belum terpotong dahi dan dagunya.
class _PanduanKepala extends StatelessWidget {
  const _PanduanKepala();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PelukisPanduan(), size: Size.infinite);
}

class _PelukisPanduan extends CustomPainter {
  @override
  void paint(Canvas kanvas, Size ukuran) {
    final lebar = ukuran.width * 0.62;
    final lonjong = Rect.fromCenter(
      center: Offset(ukuran.width / 2, ukuran.height * 0.44),
      width: lebar,
      height: lebar * 1.32,
    );

    // Gelapkan seluruhnya, lalu lubangi lonjongnya.
    //
    // evenOdd, bukan dua lapisan cat: menumpuk cat gelap di luar dan cat
    // bening di dalam meninggalkan garis tipis di batasnya pada layar
    // dengan kerapatan piksel tertentu.
    final gelap = Path()
      ..addRect(Offset.zero & ukuran)
      ..addOval(lonjong)
      ..fillType = PathFillType.evenOdd;
    kanvas.drawPath(gelap, Paint()..color = const Color(0x8C000000));

    kanvas.drawOval(
      lonjong,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withOpacity(0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _PelukisPanduan lama) => false;
}
