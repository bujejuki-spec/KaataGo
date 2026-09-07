import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pembungkus layanan latar yang mengunduh APK pembaruan.
///
/// Alasannya ada di UnduhanService.kt: unduhan yang berjalan di dalam
/// isolate Dart mati begitu Android membekukan aplikasinya — layar
/// dikunci, atau orangnya pindah ke aplikasi lain — dan yang dialami
/// orangnya selalu sama: 86 MB yang batal tanpa satu pun pesan.
///
/// Batasnya juga perlu diingat: force-stop membunuh seluruh milik
/// aplikasi, layanan ini termasuk. Tidak ada yang bisa dilakukan dari
/// sini terhadap itu.
class UnduhanSistem {
  static const _saluran = MethodChannel('kaatago/unduhan');

  static Future<void> mulai(String url,
          {String nama = 'KaataGo-update.apk'}) =>
      _saluran.invokeMethod<void>('mulai', {'url': url, 'nama': nama});

  /// Melanjutkan dari byte terakhir yang sudah tersimpan.
  static Future<void> lanjut(String url,
          {String nama = 'KaataGo-update.apk'}) =>
      _saluran.invokeMethod<void>('lanjut', {'url': url, 'nama': nama});

  static Future<void> jeda() => _saluran.invokeMethod<void>('jeda');

  static Future<void> batal() => _saluran.invokeMethod<void>('batal');

  /// Keadaan unduhan sekarang.
  ///
  /// Ditanyakan berkala, bukan ditunggu lewat siaran: layanannya hidup
  /// lebih lama daripada mesin Flutter yang menanyakannya, dan siaran
  /// yang tidak ada penerimanya hilang begitu saja.
  static Future<KeadaanUnduhan> status() async {
    final map =
        await _saluran.invokeMapMethod<String, Object?>('status');
    if (map == null) return const KeadaanUnduhan.kosong();
    return KeadaanUnduhan(
      keadaan: map['keadaan']?.toString() ?? 'kosong',
      turun: (map['turun'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? -1,
      berkas: map['berkas']?.toString(),
      galat: map['galat']?.toString(),
    );
  }

  // ── Mengingat unduhan yang sedang berjalan ──────────────────────────
  //
  // Layanannya hidup di luar mesin Flutter, tapi tautannya cuma ada di
  // ingatan aplikasi — dan ingatan itu hilang begitu prosesnya mati.
  // Tanpa disimpan, aplikasi yang dibuka lagi tidak punya cara menyambung
  // unduhan yang sebenarnya masih berjalan: tidak ada kemajuan yang
  // ditampilkan, tidak ada pemasang yang dibuka saat selesai. Dari
  // tempat duduk orangnya, itu terlihat persis seperti unduhan yang
  // berhenti sendiri.
  static const _kunciUrl = 'unduhan_apk_url';

  static Future<void> ingat(String url) async =>
      (await SharedPreferences.getInstance()).setString(_kunciUrl, url);

  static Future<void> lupakan() async =>
      (await SharedPreferences.getInstance()).remove(_kunciUrl);

  static Future<String?> yangDiingat() async =>
      (await SharedPreferences.getInstance()).getString(_kunciUrl);
}

class KeadaanUnduhan {
  /// 'kosong' | 'berjalan' | 'dijeda' | 'selesai' | 'gagal' | 'dibatalkan'
  final String keadaan;
  final int turun;

  /// -1 saat panjang berkasnya belum diketahui.
  final int total;
  final String? berkas;
  final String? galat;

  const KeadaanUnduhan({
    required this.keadaan,
    required this.turun,
    required this.total,
    this.berkas,
    this.galat,
  });

  const KeadaanUnduhan.kosong()
      : keadaan = 'kosong',
        turun = 0,
        total = -1,
        berkas = null,
        galat = null;

  bool get berjalan => keadaan == 'berjalan';
  bool get dijeda => keadaan == 'dijeda';
  bool get selesai => keadaan == 'selesai';
  bool get gagal => keadaan == 'gagal';
  bool get dibatalkan => keadaan == 'dibatalkan';

  /// 0..1, atau null kalau panjangnya belum diketahui.
  double? get kemajuan => total > 0 ? turun / total : null;
}
