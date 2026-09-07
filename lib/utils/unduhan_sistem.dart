import 'package:flutter/services.dart';

/// Pembungkus DownloadManager milik Android.
///
/// Alasan memakainya ada di MainActivity.kt: unduhan yang berjalan di
/// dalam proses aplikasi ini mati bersama prosesnya, dan itu berarti
/// menutup aplikasi atau mengunci layar membatalkan 86 MB tanpa satu pun
/// pesan yang menjelaskannya.
class UnduhanSistem {
  static const _saluran = MethodChannel('kaatago/unduhan');

  /// Menitipkan unduhannya ke sistem. Mengembalikan id untuk ditanyakan
  /// kemajuannya nanti.
  static Future<int> mulai(String url, {String nama = 'KaataGo-update.apk'}) async {
    final id = await _saluran.invokeMethod<Object>('mulai', {
      'url': url,
      'nama': nama,
    });
    return (id as num).toInt();
  }

  /// Keadaan unduhan sekarang.
  ///
  /// Ditanyakan berkala, bukan ditunggu: DownloadManager hanya
  /// menyiarkan penyelesaian, tidak menyiarkan kemajuan.
  static Future<KeadaanUnduhan> status(int id) async {
    final map = await _saluran.invokeMapMethod<String, Object?>(
        'status', {'id': id});
    if (map == null) return const KeadaanUnduhan.hilang();
    return KeadaanUnduhan(
      keadaan: map['keadaan']?.toString() ?? 'hilang',
      turun: (map['turun'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? -1,
      alasan: (map['alasan'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> batal(int id) =>
      _saluran.invokeMethod<void>('batal', {'id': id});

  /// Membuka layar pemasang. False berarti sistem menolak — biasanya
  /// karena aplikasinya sedang di latar, dan notifikasi jadi jalan yang
  /// tersisa.
  static Future<bool> pasang(int id) async =>
      await _saluran.invokeMethod<bool>('pasang', {'id': id}) ?? false;
}

class KeadaanUnduhan {
  /// 'berjalan' | 'tertunda' | 'selesai' | 'gagal' | 'hilang'
  final String keadaan;
  final int turun;

  /// -1 saat servernya tidak memberitahu panjang berkasnya.
  final int total;
  final int alasan;

  const KeadaanUnduhan({
    required this.keadaan,
    required this.turun,
    required this.total,
    required this.alasan,
  });

  const KeadaanUnduhan.hilang()
      : keadaan = 'hilang',
        turun = 0,
        total = -1,
        alasan = 0;

  bool get selesai => keadaan == 'selesai';
  bool get gagal => keadaan == 'gagal';
  bool get hilang => keadaan == 'hilang';

  /// 0..1, atau null kalau panjangnya belum diketahui.
  double? get kemajuan => total > 0 ? turun / total : null;
}
