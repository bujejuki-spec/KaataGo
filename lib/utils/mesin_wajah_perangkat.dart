import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Hasil satu pemindaian wajah.
class HasilWajah {
  /// Tanda tangan bentuk wajahnya — deret angka yang dibandingkan
  /// server dengan yang terdaftar.
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

/// Pencocok wajah di perangkat, tanpa model terlatih.
///
/// ── Apa yang benar-benar dibandingkan ────────────────────────────────
///
/// Bentuk wajahnya, bukan penampakannya. ML Kit — yang sudah ikut di
/// APK, Apache-2.0, terbitan Google sendiri — memberi sekitar 133 titik
/// kontur: garis rahang, alis, mata, hidung, pipi. Titik-titik itu
/// diluruskan, diseragamkan skalanya, lalu dijadikan satu deret angka.
///
/// Dua foto orang yang sama menghasilkan deret yang berdekatan. Dua
/// orang yang bentuk wajahnya berbeda menghasilkan deret yang berjauhan.
///
/// ── Yang TIDAK dijanjikan ────────────────────────────────────────────
///
/// Ini bukan pengenal wajah sekelas model terlatih, dan tidak boleh
/// diperlakukan begitu. Dua orang yang kebetulan berbentuk wajah mirip —
/// saudara kandung, misalnya — bisa lolos. Yang dijamin cuma satu: absen
/// tidak bisa dititipkan ke orang yang bentuk wajahnya jelas berbeda.
///
/// Karena itu fotonya selalu disimpan, dan layar Admin menyandingkan
/// foto acuan dengan foto absen hari itu. Pemeriksaan otomatis menangkap
/// yang kasar; yang halus ditangkap mata orang saat memutuskan gaji —
/// dan itu memang saat yang paling tepat untuk memeriksanya.
///
/// Menyebutnya "pengenal wajah" tanpa keterangan ini akan membuat orang
/// mengandalkan jaminan yang tidak pernah diberikan.
class MesinWajah {
  static const tersedia = true;

  /// Ikut tersimpan di basis data bersama sidiknya.
  ///
  /// Server memilih cara membandingkan berdasarkan nama ini. Sidik dari
  /// dua cara berbeda tidak sebanding sama sekali — angkanya tetap
  /// keluar, dan yang keluar adalah penolakan yang tidak bisa
  /// dijelaskan ke orangnya.
  static const namaModel = 'geometri-mlkit-v1';

  static FaceDetector? _pendeteksi;

  /// Selalu siap: tidak ada berkas model yang perlu dimuat.
  static Future<bool> siap() async => true;

  static FaceDetector get _detektor => _pendeteksi ??= FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          // Konturnya yang jadi bahan tanda tangannya. Tanpa ini yang
          // tersedia cuma sepuluh titik, dan sepuluh titik tidak cukup
          // membedakan siapa pun.
          enableContours: true,
          enableLandmarks: true,
          enableClassification: true,
          minFaceSize: 0.15,
        ),
      );

  /// Memindai satu berkas gambar jadi tanda tangan wajah.
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

    // Wajah miring mengubah bentuk yang terlihat kamera, bukan cuma
    // memutarnya — dan tanda tangan yang dihitung darinya akan berbeda
    // dari yang terdaftar meski orangnya sama. Batasnya lebih ketat
    // daripada pengenal wajah terlatih justru karena metode ini lebih
    // peka terhadap pose.
    final y = w.headEulerAngleY ?? 0;
    final z = w.headEulerAngleZ ?? 0;
    if (y.abs() > 15 || z.abs() > 15) {
      throw const WajahGagal(
          'Hadapkan wajahmu lurus ke kamera, jangan miring.');
    }

    final sidik = _tandaTangan(w);

    final asli = img.decodeImage(await File(jalurGambar).readAsBytes());
    if (asli == null) {
      throw const WajahGagal('Gambarnya tidak terbaca. Coba foto ulang.');
    }

    return HasilWajah(
      sidik: sidik,
      potongan: Uint8List.fromList(
          img.encodeJpg(_potong(asli, w.boundingBox), quality: 82)),
    );
  }

  // ── Tanda tangannya ────────────────────────────────────────────────

  /// Kontur yang dipakai, berikut berapa titik yang diambil dari
  /// masing-masing.
  ///
  /// Bibir sengaja TIDAK ikut. Bentuknya berubah total antara tersenyum
  /// dan tidak, dan orang yang absen sambil tersenyum akan ditolak oleh
  /// wajahnya sendiri.
  ///
  /// Mata juga tidak: ia menyipit dan membuka, dan kelopak yang setengah
  /// tertutup menggeser seluruh konturnya.
  static const _dipakai = <FaceContourType, int>{
    FaceContourType.face: 24,
    FaceContourType.leftEyebrowTop: 5,
    FaceContourType.rightEyebrowTop: 5,
    FaceContourType.noseBridge: 2,
    FaceContourType.noseBottom: 3,
  };

  static List<double> _tandaTangan(Face w) {
    final mataKiri = w.landmarks[FaceLandmarkType.leftEye]?.position;
    final mataKanan = w.landmarks[FaceLandmarkType.rightEye]?.position;
    if (mataKiri == null || mataKanan == null) {
      throw const WajahGagal(
          'Mata tidak terbaca jelas. Coba lagi dengan cahaya yang lebih '
          'terang.');
    }

    final kiri = Offset(mataKiri.x.toDouble(), mataKiri.y.toDouble());
    final kanan = Offset(mataKanan.x.toDouble(), mataKanan.y.toDouble());

    // Diluruskan pada garis mata: titik tengah kedua mata jadi pusat,
    // garisnya diputar jadi mendatar, dan jarak antarmata jadi satuan
    // ukurnya.
    //
    // Tanpa ini, wajah yang sama pada jarak berbeda dari kamera
    // menghasilkan angka yang sama sekali berbeda — dan yang dibandingkan
    // bukan lagi wajahnya melainkan seberapa dekat orangnya berdiri.
    final pusat = Offset((kiri.dx + kanan.dx) / 2, (kiri.dy + kanan.dy) / 2);
    final beda = kanan - kiri;
    final jarakMata = beda.distance;
    if (jarakMata < 1) {
      throw const WajahGagal('Wajahnya terlalu kecil di bingkai. Mendekat '
          'sedikit lalu coba lagi.');
    }
    final sudut = math.atan2(beda.dy, beda.dx);
    final cos = math.cos(-sudut);
    final sin = math.sin(-sudut);

    final angka = <double>[];
    for (final entri in _dipakai.entries) {
      final titik = w.contours[entri.key]?.points;
      if (titik == null || titik.isEmpty) {
        throw const WajahGagal(
            'Bentuk wajahnya tidak terbaca lengkap. Hadapkan wajahmu lurus '
            'ke kamera dengan cahaya yang cukup.');
      }
      for (final p in _ambilRata(titik, entri.value)) {
        final dx = (p.dx - pusat.dx) / jarakMata;
        final dy = (p.dy - pusat.dy) / jarakMata;
        angka.add(dx * cos - dy * sin);
        angka.add(dx * sin + dy * cos);
      }
    }

    return angka;
  }

  /// Mengambil [berapa] titik yang jaraknya merata di sepanjang kontur.
  ///
  /// Jumlah titik yang dikembalikan ML Kit tidak selalu sama antara satu
  /// foto dan foto berikutnya. Deret yang panjangnya berbeda tidak bisa
  /// dibandingkan sama sekali, jadi panjangnya dipaksa tetap di sini.
  static List<Offset> _ambilRata(List<math.Point<int>> titik, int berapa) {
    final p = [
      for (final t in titik) Offset(t.x.toDouble(), t.y.toDouble()),
    ];
    if (p.length == 1) return List.filled(berapa, p.first);

    final hasil = <Offset>[];
    for (var i = 0; i < berapa; i++) {
      final pos = i * (p.length - 1) / (berapa - 1);
      final bawah = pos.floor();
      final atas = math.min(bawah + 1, p.length - 1);
      final sisa = pos - bawah;
      hasil.add(Offset(
        p[bawah].dx + (p[atas].dx - p[bawah].dx) * sisa,
        p[bawah].dy + (p[atas].dy - p[bawah].dy) * sisa,
      ));
    }
    return hasil;
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
  }
}
