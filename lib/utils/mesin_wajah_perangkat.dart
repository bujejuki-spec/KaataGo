import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Hasil satu pemindaian wajah.
class HasilWajah {
  /// Sidik wajahnya — 128 angka yang dibandingkan server dengan yang
  /// terdaftar.
  final List<double> sidik;

  /// Wajah yang sudah dipotong, disimpan sebagai bukti yang dilihat
  /// manusia.
  final Uint8List potongan;

  const HasilWajah({required this.sidik, required this.potongan});
}

/// Wajahnya tidak bisa dipakai, berikut alasan yang bisa dibaca orang.
class WajahGagal implements Exception {
  final String pesan;

  const WajahGagal(this.pesan);

  @override
  String toString() => pesan;
}

/// Pengenal wajah di perangkat.
///
/// ── Kenapa bukan bentuk wajahnya ─────────────────────────────────────
///
/// Versi sebelumnya membandingkan BENTUK wajah: titik kontur dari ML
/// Kit, diluruskan di garis mata dan diseragamkan skalanya. Idenya
/// masuk akal dan hasilnya tidak: begitu ada tiga wajah sungguhan untuk
/// diuji, tiga orang yang berbeda berjarak 0,85-0,88 dari skala 0-1 —
/// jauh di atas ambang yang dianggap "yakin orangnya sama".
///
/// Sebabnya mendasar, bukan soal angka yang kurang pas. Penyeragaman
/// skalanya membuang justru apa yang membedakan orang, dan yang tersisa
/// cuma "berbentuk wajah" — dan semua orang berbentuk wajah.
///
/// ── Yang dipakai sekarang ────────────────────────────────────────────
///
/// FaceNet: model terlatih yang mengubah wajah jadi 128 angka, di mana
/// wajah orang yang sama berdekatan dan wajah orang lain berjauhan.
/// Berkasnya ikut di APK dan dijalankan TensorFlow Lite di ponsel.
///
/// Fotonya tidak ke mana-mana. Berkas `.tflite` bukan program: ia
/// bundel angka dalam format data tertutup, tanpa kemampuan membuka
/// jaringan atau membaca berkas. Yang masuk piksel di RAM, yang keluar
/// 128 angka. Itu batas strukturnya, bukan janji niat baik.
///
/// ML Kit tetap dipakai, tapi untuk pekerjaan yang memang bisa
/// dilakukannya: menemukan wajahnya di gambar, memastikan cuma ada
/// satu, dan menolak mata terpejam atau kepala terlalu miring.
///
/// ── Yang TIDAK dijanjikan ────────────────────────────────────────────
///
/// Tidak ada pengenal wajah yang tidak pernah keliru. Saudara kembar
/// bisa lolos, dan cahaya yang sangat buruk bisa menolak orang yang
/// benar. Karena itu fotonya selalu disimpan, skor yang jatuh di pita
/// ragu-ragu ditandai, dan layar Absensi Karyawan menyandingkan foto
/// acuan dengan foto absennya. Yang kasar ditangkap model; yang halus
/// ditangkap mata orang saat memutuskan gaji.
class MesinWajah {
  static const tersedia = true;

  /// Ikut tersimpan di basis data bersama sidiknya.
  ///
  /// Server memilih cara membandingkan berdasarkan nama ini, dan
  /// MENOLAK absen kalau namanya tidak sama dengan yang terdaftar.
  /// Sidik dari dua cara berbeda tidak sebanding sama sekali — angkanya
  /// tetap keluar, dan angka itulah yang paling berbahaya karena ia
  /// terlihat seperti jawaban.
  static const namaModel = 'facenet-128-v1';

  /// Versi teks persetujuan yang sedang berlaku.
  ///
  /// Ikut tercatat saat wajahnya didaftarkan. Kalau teksnya suatu hari
  /// berubah, yang pernah menyetujui teks lama tetap tercatat menyetujui
  /// teks lama — tanpa versinya, catatan persetujuan tidak membuktikan
  /// apa pun karena tidak ada yang tahu dia menyetujui apa.
  static const versiPersetujuan = 'wajah-v1-2026-09';

  static const _berkasModel = 'assets/face/facenet.tflite';

  /// Sisi gambar yang diminta FaceNet, dan panjang sidik yang
  /// dikeluarkannya.
  static const _sisi = 160;
  static const _panjangSidik = 128;

  static FaceDetector? _pendeteksi;
  static Interpreter? _model;

  static FaceDetector get _detektor => _pendeteksi ??= FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          // Kontur tidak lagi dibutuhkan: yang mengenali wajahnya
          // sekarang FaceNet, dan ML Kit cuma menemukan letaknya.
          // Mematikannya membuat pendeteksiannya jauh lebih ringan.
          enableContours: false,
          enableLandmarks: true,
          enableClassification: true,
          minFaceSize: 0.15,
        ),
      );

  /// Memuat modelnya. Dipanggil sekali, lalu hasilnya dipakai ulang.
  static Future<bool> siap() async {
    if (_model != null) return true;
    try {
      _model = await Interpreter.fromAsset(_berkasModel);
      return true;
    } catch (_) {
      // Tidak dilempar sebagai galat: layar absensi memakai ini untuk
      // memutuskan apa yang ditawarkannya, dan izin tidak masuk tetap
      // harus bisa diajukan meski modelnya gagal dimuat — server tidak
      // menuntut wajah maupun GPS untuk yang satu itu.
      return false;
    }
  }

  /// Memindai satu berkas gambar jadi sidik wajah.
  static Future<HasilWajah> pindai(String jalurGambar) async {
    final wajah =
        await _detektor.processImage(InputImage.fromFilePath(jalurGambar));

    if (wajah.isEmpty) {
      throw const WajahGagal(
          'Tidak ada wajah yang terbaca. Arahkan kamera ke wajahmu, '
          'pastikan cahayanya cukup.');
    }
    // Dua wajah di satu bingkai justru keadaan yang paling ingin
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
      throw const WajahGagal(
          'Matanya terpejam. Coba lagi sambil melihat kamera.');
    }

    // Batasnya lebih longgar daripada cara yang lama. FaceNet dilatih
    // pada wajah yang tidak selalu lurus ke kamera, jadi kemiringan
    // sedang tidak lagi merusak sidiknya — dan menolak orang karena
    // kepalanya agak miring cuma menyuruhnya mengulang tanpa alasan.
    final y = w.headEulerAngleY ?? 0;
    final z = w.headEulerAngleZ ?? 0;
    if (y.abs() > 25 || z.abs() > 25) {
      throw const WajahGagal(
          'Hadapkan wajahmu lurus ke kamera, jangan terlalu miring.');
    }

    final asli = img.decodeImage(await File(jalurGambar).readAsBytes());
    if (asli == null) {
      throw const WajahGagal('Gambarnya tidak terbaca. Coba foto ulang.');
    }

    final potongan = _potong(asli, w.boundingBox);

    return HasilWajah(
      sidik: await _sidik(potongan),
      potongan: Uint8List.fromList(img.encodeJpg(potongan, quality: 82)),
    );
  }

  // ── Sidiknya ───────────────────────────────────────────────────────

  static Future<List<double>> _sidik(img.Image wajah) async {
    if (!await siap()) {
      throw const WajahGagal(
          'Pengenal wajahnya gagal dimuat. Tutup aplikasinya lalu buka '
          'lagi; kalau masih sama, perbarui aplikasinya lewat Kotak Masuk.');
    }

    final kecil = img.copyResize(wajah,
        width: _sisi, height: _sisi, interpolation: img.Interpolation.linear);

    // FaceNet menuntut gambarnya DISERAGAMKAN dulu: tiap nilai dikurangi
    // rata-ratanya lalu dibagi simpangan bakunya, dihitung per gambar.
    //
    // Bukan sekadar dibagi 255. Penyeragaman inilah yang membuat wajah
    // yang sama di ruangan gelap dan di bawah matahari menghasilkan
    // sidik yang berdekatan — tanpanya yang dibandingkan lebih banyak
    // cahayanya daripada orangnya.
    final piksel = Float32List(_sisi * _sisi * 3);
    var i = 0;
    for (var y = 0; y < _sisi; y++) {
      for (var x = 0; x < _sisi; x++) {
        final p = kecil.getPixel(x, y);
        piksel[i++] = p.r.toDouble();
        piksel[i++] = p.g.toDouble();
        piksel[i++] = p.b.toDouble();
      }
    }

    var jumlah = 0.0;
    for (final v in piksel) {
      jumlah += v;
    }
    final rata = jumlah / piksel.length;

    var kuadrat = 0.0;
    for (final v in piksel) {
      kuadrat += (v - rata) * (v - rata);
    }
    // Lantai bawahnya menjaga gambar yang seluruhnya satu warna —
    // tutup lensa, ruangan gelap gulita — dari membagi dengan nol.
    final simpangan =
        math.max(math.sqrt(kuadrat / piksel.length), 1 / math.sqrt(piksel.length));

    for (var j = 0; j < piksel.length; j++) {
      piksel[j] = (piksel[j] - rata) / simpangan;
    }

    final keluaran = List.generate(1, (_) => List.filled(_panjangSidik, 0.0));
    _model!.run(piksel.reshape([1, _sisi, _sisi, 3]), keluaran);

    final sidik = keluaran.first;
    if (sidik.every((v) => v == 0)) {
      throw const WajahGagal(
          'Wajahnya tidak bisa dibaca jadi sidik. Coba foto ulang dengan '
          'cahaya yang lebih terang.');
    }
    return sidik;
  }

  /// Memotong kotak wajahnya berikut sedikit ruang di sekelilingnya,
  /// supaya yang tersimpan bisa dikenali mata manusia — bukan cuma
  /// sepasang mata dan hidung.
  static img.Image _potong(img.Image asli, Rect kotak) {
    final lebihX = (kotak.width * 0.25).round();
    final lebihY = (kotak.height * 0.25).round();

    final x = (kotak.left.round() - lebihX).clamp(0, asli.width - 1);
    final y = (kotak.top.round() - lebihY).clamp(0, asli.height - 1);
    final lebar = (kotak.width.round() + lebihX * 2).clamp(1, asli.width - x);
    final tinggi = (kotak.height.round() + lebihY * 2).clamp(1, asli.height - y);

    return img.copyCrop(asli, x: x, y: y, width: lebar, height: tinggi);
  }

  static Future<void> tutup() async {
    await _pendeteksi?.close();
    _pendeteksi = null;
    _model?.close();
    _model = null;
  }
}
