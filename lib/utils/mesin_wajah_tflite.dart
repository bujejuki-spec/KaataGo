import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Hasil satu pemindaian wajah.
class HasilWajah {
  /// Sidik wajahnya — deret angka keluaran model, sudah dinormalkan
  /// panjangnya jadi satu.
  final List<double> sidik;

  /// Wajah yang sudah dipotong, untuk disimpan sebagai bukti yang bisa
  /// dilihat manusia kalau suatu hari ada sengketa.
  final Uint8List potongan;

  const HasilWajah({required this.sidik, required this.potongan});
}

/// Wajahnya tidak bisa dipakai, berikut alasan yang bisa dibaca orang.
///
/// Dibedakan dari galat biasa karena hampir semuanya bisa diperbaiki
/// sendiri oleh yang memegang HP-nya: mendekat, menyalakan lampu,
/// melepas masker. Pesan "terjadi kesalahan" untuk hal-hal itu membuat
/// orang mencoba berulang kali dengan cara yang persis sama.
class WajahGagal implements Exception {
  final String pesan;

  const WajahGagal(this.pesan);

  @override
  String toString() => pesan;
}

/// Pengenal wajah di perangkat: deteksi, potong, lalu ubah jadi sidik.
///
/// ── Kenapa sidiknya, bukan fotonya, yang dikirim ─────────────────────
///
/// Foto wajah seluruh karyawan yang menumpuk di server adalah data
/// biometrik yang harus dijaga selamanya, dan yang menanggung akibatnya
/// kalau bocor bukan aplikasinya melainkan orang-orangnya. Sidik wajah
/// berupa 192 angka tidak bisa dikembalikan jadi foto.
///
/// Fotonya tetap disimpan satu per absen — tapi sebagai bukti yang
/// dilihat manusia saat ada sengketa, bukan sebagai bahan pencocokan.
class MesinWajah {
  static const tersedia = true;

  /// Ikut ditulis ke basis data bersama sidiknya.
  ///
  /// Sidik dari dua model berbeda tidak bisa dibandingkan sama sekali —
  /// angkanya tetap keluar, dan yang keluar adalah penolakan yang tidak
  /// bisa dijelaskan ke orangnya. Menyimpan nama modelnya membuat
  /// pergantian model nanti bisa diketahui, bukan ditebak.
  static const namaModel = 'mobilefacenet-192';

  static const _jalurModel = 'assets/face/mobilefacenet.tflite';

  /// Sisi gambar yang diminta MobileFaceNet.
  static const _sisi = 112;

  static Interpreter? _penafsir;
  static FaceDetector? _pendeteksi;

  /// Modelnya ada dan bisa dimuat.
  ///
  /// Dipanggil layar Absensi sebelum menawarkan tombolnya. Tombol yang
  /// ada lalu gagal saat ditekan lebih buruk daripada tombol yang sejak
  /// awal menjelaskan kenapa ia belum bisa dipakai.
  static Future<bool> siap() async {
    try {
      await _muat();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Interpreter> _muat() async {
    final ada = _penafsir;
    if (ada != null) return ada;
    try {
      final baru = await Interpreter.fromAsset(_jalurModel);
      _penafsir = baru;
      return baru;
    } catch (e) {
      throw WajahGagal(
          'Model pengenal wajah belum terpasang di aplikasi ini ($e).');
    }
  }

  static FaceDetector get _detektor => _pendeteksi ??= FaceDetector(
        options: FaceDetectorOptions(
          // Akurat, bukan cepat. Yang dipindai satu wajah diam di depan
          // kamera depan, sekali sehari — bukan aliran video yang harus
          // mengejar 30 gambar per detik.
          performanceMode: FaceDetectorMode.accurate,
          // Dipakai memastikan matanya terbuka: foto layar HP lain yang
          // diarahkan ke kamera sering lolos deteksi wajah, dan mata
          // terpejam adalah salah satu petunjuk paling murah bahwa yang
          // dilihat bukan orang yang sedang berdiri di situ.
          enableClassification: true,
          enableLandmarks: true,
          minFaceSize: 0.15,
        ),
      );

  /// Memindai satu berkas gambar jadi sidik wajah.
  ///
  /// Melempar [WajahGagal] dengan kalimat yang bisa langsung ditampilkan
  /// kalau wajahnya tidak memenuhi syarat.
  static Future<HasilWajah> pindai(String jalurGambar) async {
    final penafsir = await _muat();

    final wajah = await _detektor.processImage(InputImage.fromFilePath(jalurGambar));

    if (wajah.isEmpty) {
      throw const WajahGagal(
          'Tidak ada wajah yang terbaca. Arahkan kamera ke wajahmu, '
          'pastikan cahayanya cukup.');
    }
    // Dua wajah di satu bingkai adalah keadaan yang justru paling ingin
    // ditolak: satu orang membuka aplikasinya, satu lagi menghadap
    // kamera.
    if (wajah.length > 1) {
      throw const WajahGagal(
          'Ada lebih dari satu wajah di kamera. Pastikan hanya kamu yang '
          'terlihat.');
    }

    final w = wajah.first;

    final kiri = w.leftEyeOpenProbability;
    final kanan = w.rightEyeOpenProbability;
    if (kiri != null && kanan != null && kiri < 0.3 && kanan < 0.3) {
      throw const WajahGagal('Matanya terpejam. Coba lagi sambil melihat kamera.');
    }

    // Kepala yang terlalu miring menghasilkan sidik yang jauh dari yang
    // terdaftar — dan penolakannya nanti terbaca sebagai "aplikasinya
    // tidak mengenali saya", bukan "wajahmu miring".
    final y = w.headEulerAngleY ?? 0;
    final z = w.headEulerAngleZ ?? 0;
    if (y.abs() > 25 || z.abs() > 25) {
      throw const WajahGagal('Hadapkan wajahmu lurus ke kamera.');
    }

    final asli = img.decodeImage(await File(jalurGambar).readAsBytes());
    if (asli == null) {
      throw const WajahGagal('Gambarnya tidak terbaca. Coba foto ulang.');
    }

    final potongan = _potong(asli, w.boundingBox);
    final kecil = img.copyResize(potongan, width: _sisi, height: _sisi);

    final keluaran = _jalankan(penafsir, kecil);

    return HasilWajah(
      sidik: keluaran,
      // Kualitas 80: cukup untuk dikenali mata manusia saat diperiksa,
      // cukup kecil untuk diunggah dari jaringan warung.
      potongan: Uint8List.fromList(img.encodeJpg(potongan, quality: 80)),
    );
  }

  /// Memotong kotak wajahnya berikut sedikit ruang di sekelilingnya.
  ///
  /// Ruang tambahannya bukan hiasan: MobileFaceNet dilatih pada potongan
  /// yang memuat dahi dan dagu, dan potongan yang terlalu rapat ke garis
  /// mata menghasilkan sidik yang tidak sebanding dengan sidik yang
  /// terdaftar dari potongan yang lebih longgar.
  static img.Image _potong(img.Image asli, Rect kotak) {
    final lebihX = (kotak.width * 0.2).round();
    final lebihY = (kotak.height * 0.2).round();

    final x = (kotak.left.round() - lebihX).clamp(0, asli.width - 1);
    final y = (kotak.top.round() - lebihY).clamp(0, asli.height - 1);
    final lebar = (kotak.width.round() + lebihX * 2).clamp(1, asli.width - x);
    final tinggi = (kotak.height.round() + lebihY * 2).clamp(1, asli.height - y);

    return img.copyCrop(asli, x: x, y: y, width: lebar, height: tinggi);
  }

  static List<double> _jalankan(Interpreter penafsir, img.Image gambar) {
    // [1, 112, 112, 3], nilainya digeser ke -1..1 seperti saat modelnya
    // dilatih. Memberinya 0..255 apa adanya tetap menghasilkan angka —
    // angka yang tidak berarti apa-apa, dan dua orang berbeda bisa
    // terlihat mirip.
    final masuk = List.generate(
      1,
      (_) => List.generate(
        _sisi,
        (y) => List.generate(
          _sisi,
          (x) {
            final p = gambar.getPixel(x, y);
            return [
              (p.r - 127.5) / 128.0,
              (p.g - 127.5) / 128.0,
              (p.b - 127.5) / 128.0,
            ];
          },
        ),
      ),
    );

    final panjang = penafsir.getOutputTensor(0).shape.last;
    final keluar = List.generate(1, (_) => List.filled(panjang, 0.0));
    penafsir.run(masuk, keluar);

    return _normalkan(keluar.first);
  }

  /// Panjangnya dijadikan satu.
  ///
  /// Kemiripan kosinus memang tidak peduli panjang vektornya, tapi
  /// sidik yang panjangnya seragam membuat ambang di server berlaku
  /// sama untuk semua — termasuk kalau suatu hari pembandingnya diganti
  /// jarak Euclid.
  static List<double> _normalkan(List<double> v) {
    var jumlah = 0.0;
    for (final x in v) {
      jumlah += x * x;
    }
    final panjang = math.sqrt(jumlah);
    if (panjang == 0) {
      throw const WajahGagal('Wajahnya gagal dibaca model. Coba foto ulang.');
    }
    return [for (final x in v) x / panjang];
  }

  static Future<void> tutup() async {
    await _pendeteksi?.close();
    _pendeteksi = null;
    _penafsir?.close();
    _penafsir = null;
  }
}
