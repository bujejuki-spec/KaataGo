import 'package:flutter/foundation.dart';

import '../utils/apk_updater.dart';

/// Unduhan pembaruan aplikasi, hidup di luar layar mana pun.
///
/// Dulu keadaannya dititipkan pada tombol di dalam kotak masuk, dan itu
/// berarti menutup kotak masuknya membatalkan unduhan yang sedang
/// berjalan — 80 MB yang hangus hanya karena orangnya ingin melihat
/// pesanan yang masuk sementara menunggu. Yang paling sering terjadi
/// justru itu: unduhan besar bukan sesuatu yang ditunggui orang sambil
/// menatap layar.
///
/// Sebagai singleton, unduhannya terus berjalan ke mana pun orangnya
/// pergi di dalam aplikasi, dan kemajuannya tetap bisa dilihat lewat
/// penanda mengambang di bawah layar.
class AppUpdater extends ChangeNotifier {
  AppUpdater._();
  static final instance = AppUpdater._();

  ApkUpdater? _updater;
  String? _url;

  /// 0..1, atau null saat panjang berkasnya tidak diberitahukan server.
  double? progress;

  bool downloading = false;

  /// Keterangan galat terakhir, atau null kalau tidak ada.
  String? error;

  /// Persen bulat untuk ditampilkan, atau null kalau belum diketahui.
  int? get percent => progress == null ? null : (progress! * 100).round();

  Future<void> start(String url) async {
    if (downloading) return;

    _url = url;
    error = null;
    progress = 0;
    downloading = true;
    notifyListeners();

    final updater = ApkUpdater(onProgress: (p) {
      progress = p;
      notifyListeners();
    });
    _updater = updater;

    final failure = await updater.downloadAndInstall(url);

    _updater = null;
    downloading = false;
    progress = null;
    error = failure;
    notifyListeners();
  }

  /// Mengulang unduhan yang gagal, dengan tautan yang sama.
  Future<void> retry() async {
    final url = _url;
    if (url == null) return;
    await start(url);
  }

  void cancel() {
    _updater?.cancel();
    _updater = null;
    downloading = false;
    progress = null;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
