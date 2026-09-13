import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/apk_updater.dart';
import '../utils/unduhan_sistem.dart';
import 'notification_service.dart';

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

  /// Dijeda, dan berkas separuhnya menunggu dilanjutkan.
  bool paused = false;

  /// Keterangan galat terakhir, atau null kalau tidak ada.
  String? error;

  /// Persen bulat untuk ditampilkan, atau null kalau belum diketahui.
  int? get percent => progress == null ? null : (progress! * 100).round();

  /// Panjang berkasnya dalam byte, begitu servernya memberitahukan.
  int? totalBytes;

  /// "154 MB", atau null selama belum diketahui.
  ///
  /// Dibaca dari unduhannya sendiri, bukan ditulis tangan di layar.
  /// Angka yang ditulis tangan tertinggal pada rilis berikutnya — dan
  /// itu persis yang terjadi: layar ini menyebut 80 MB sampai berkasnya
  /// hampir dua kali lipat.
  String? get ukuranTeks {
    final b = totalBytes;
    if (b == null || b <= 0) return null;
    return '${(b / 1048576).round()} MB';
  }

  /// Persen terakhir yang sudah dikirim ke notifikasi Android.
  ///
  /// Tiap potongan data memanggil onProgress — ribuan kali untuk 83 MB —
  /// dan mengirim semuanya ke Android berarti membanjiri antrean
  /// notifikasi demi angka yang sama.
  int? _lastPercent;

  Future<void> start(String url) async {
    if (downloading) return;

    _url = url;
    error = null;
    _noticeTimer?.cancel();
    notice = null;
    paused = false;
    progress = 0;

    final updater = ApkUpdater(onProgress: (p) {
      progress = p;
      final now = p == null ? null : (p * 100).round();
      if (now != _lastPercent) {
        _lastPercent = now;
        // Saat sistem yang mengunduh, sistem pula yang memasang
        // notifikasinya. Menambah notifikasi sendiri berisi angka yang
        // sama cuma menggandakan barisnya di rana notifikasi, dan yang
        // kedua tidak bisa diketuk untuk memasang.
        if (!ApkUpdater.pakaiSistem) {
          NotificationService.instance.showDownloadProgress(now);
        }
      }
      notifyListeners();
    });
    _updater = updater;

    await _jalankan(url, updater);
  }

  /// Menjalankan unduhannya, entah dari nol atau melanjutkan yang dijeda.
  ///
  /// Dipisah dari [start] supaya melanjutkan memakai ApkUpdater yang
  /// sama — di situlah tersimpan berapa byte yang sudah turun, dan
  /// membuat yang baru berarti mengulang dari nol dengan nama "lanjut".
  Future<void> _jalankan(String url, ApkUpdater updater) async {
    downloading = true;
    error = null;
    notifyListeners();

    _lastPercent = percent;
    if (!ApkUpdater.pakaiSistem) {
      NotificationService.instance.showDownloadProgress(_lastPercent ?? 0);
    }

    final failure = await updater.downloadAndInstall(
      url,
      // Berkasnya sudah turun, layar pemasang belum tentu terbuka.
      //
      // Android melarang aplikasi yang sedang di latar membuka layar
      // sendiri — jadi kalau HP-nya terkunci atau orangnya sedang di
      // aplikasi lain, panggilan membuka pemasang itu diam saja.
      // Notifikasi ini jalan yang tersisa: satu ketukan, dan layar
      // pemasangnya terbuka.
      onDownloaded: (path) =>
          NotificationService.instance.showDownloadReady(path),
      // Hanya terpakai pada pengunduh sendiri. Unduhan lewat sistem
      // sudah membawa notifikasi selesainya sendiri.
    );

    final dijeda = paused;
    downloading = false;
    // Kemajuannya dipertahankan saat dijeda — angka yang kembali ke nol
    // membuat orang mengira unduhannya hangus, dan itu justru kebalikan
    // dari yang dijanjikan tombol Jeda.
    if (!dijeda) {
      _updater = null;
      progress = null;
    }
    error = failure;
    if (failure != null || dijeda) {
      NotificationService.instance.cancelDownloadNotification();
    }
    notifyListeners();
  }

  /// Menyambung lagi unduhan sistem yang masih berjalan dari sesi lalu.
  ///
  /// Dipanggil sekali saat aplikasi dibuka. Unduhannya hidup di proses
  /// sistem, jadi ia bisa saja masih berjalan — atau malah sudah selesai
  /// — sementara aplikasi ini baru saja dinyalakan kembali. Tanpa ini,
  /// aplikasi yang dibuka lagi tidak menampilkan kemajuan apa pun dan
  /// tidak pernah membuka pemasangnya, yang dari tempat duduk orangnya
  /// terlihat persis seperti unduhan yang berhenti sendiri.
  Future<void> pulihkan() async {
    if (!ApkUpdater.pakaiSistem || downloading) return;

    final url = await UnduhanSistem.yangDiingat();
    if (url == null) return;

    // Layanannya mungkin sudah mati bersama prosesnya — force-stop
    // membunuh keduanya. Ditanyakan dulu, jadi yang disambung memang
    // unduhan yang masih ada, bukan bayangannya.
    final keadaan = await UnduhanSistem.status();
    if (keadaan.total > 0) totalBytes = keadaan.total;
    if (keadaan.keadaan == 'kosong' || keadaan.dibatalkan) {
      await UnduhanSistem.lupakan();
      return;
    }

    _url = url;
    final updater = ApkUpdater(
      onProgress: (p) {
        progress = p;
        notifyListeners();
      },
      onTotal: (t) {
        if (t == null || t == totalBytes) return;
        totalBytes = t;
        notifyListeners();
      },
    );
    _updater = updater;

    // Yang dijeda tidak disambung sendiri: menjeda adalah keputusan
    // orangnya, dan aplikasi yang meneruskannya begitu dibuka lagi
    // membatalkan keputusan itu tanpa diminta.
    if (keadaan.dijeda) {
      paused = true;
      progress = keadaan.kemajuan;
      notifyListeners();
      return;
    }

    downloading = true;
    error = null;
    notifyListeners();

    final failure = await updater.ikutiUnduhanBerjalan(url);

    final dijeda = paused;
    downloading = false;
    if (!dijeda) {
      _updater = null;
      progress = null;
    }
    error = failure;
    notifyListeners();
  }

  /// Mengulang unduhan yang gagal, dengan tautan yang sama.
  Future<void> retry() async {
    final url = _url;
    if (url == null) return;
    await start(url);
  }

  /// Bisa dijeda atau tidak — dipakai layar untuk memutuskan menampilkan
  /// tombolnya. Unduhan lewat DownloadManager tidak bisa dijeda.
  bool get bisaDijeda => ApkUpdater.bisaDijeda;

  /// Menjeda unduhan. Berkas separuhnya tetap tersimpan.
  void pause() {
    if (!downloading || !bisaDijeda) return;
    paused = true;
    _updater?.pause();
    notifyListeners();
  }

  /// Melanjutkan dari byte terakhir yang sudah turun.
  ///
  /// Kalau servernya menolak melanjutkan, unduhannya dimulai dari nol —
  /// dan itu ditangani di lapisan bawah, bukan di sini.
  Future<void> resume() async {
    final url = _url;
    if (url == null || downloading) return;
    final updater = _updater;
    paused = false;
    if (updater == null) {
      await start(url);
      return;
    }

    // Di jalur layanan latar, melanjutkan harus memakai perintah
    // "lanjut" — bukan "mulai". Memulai ulang menghapus berkas separuh
    // yang justru jadi seluruh guna Jeda: 70% yang hangus, dengan nama
    // yang menjanjikan sebaliknya.
    if (ApkUpdater.pakaiSistem) {
      downloading = true;
      error = null;
      notifyListeners();

      final gagal = await updater.ikutiUnduhanBerjalan(url);

      final dijeda = paused;
      downloading = false;
      if (!dijeda) {
        _updater = null;
        progress = null;
      }
      error = gagal;
      notifyListeners();
      return;
    }

    await _jalankan(url, updater);
  }

  @visibleForTesting
  void setUjiGagal(String pesan) {
    downloading = false;
    paused = false;
    progress = null;
    error = pesan;
    notice = null;
    notifyListeners();
  }

  @visibleForTesting
  void setUjiBerjalan(double kemajuan) {
    downloading = true;
    paused = false;
    error = null;
    notice = null;
    progress = kemajuan;
    notifyListeners();
  }

  @visibleForTesting
  void setUjiDijeda(double kemajuan) {
    downloading = false;
    paused = true;
    error = null;
    notice = null;
    progress = kemajuan;
    notifyListeners();
  }

  @visibleForTesting
  void resetUji() {
    downloading = false;
    paused = false;
    error = null;
    notice = null;
    progress = null;
    notifyListeners();
  }

  /// Kabar singkat yang hilang sendiri — bukan galat.
  ///
  /// Membatalkan unduhan sendiri bukan kegagalan, jadi tidak boleh
  /// muncul sebagai kotak merah berisi keterangan teknis yang menuntut
  /// dibaca dan ditutup. Cukup satu kalimat yang menegaskan bahwa yang
  /// diminta memang terjadi, lalu pergi.
  String? notice;

  Timer? _noticeTimer;

  void cancel() {
    NotificationService.instance.cancelDownloadNotification();
    paused = false;
    _updater?.cancel();
    _updater = null;
    downloading = false;
    progress = null;
    error = null;
    _showNotice('Unduhan dibatalkan');
  }

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    notice = message;
    notifyListeners();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      notice = null;
      notifyListeners();
    });
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
