import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Mengunduh APK versi baru di dalam aplikasi, lalu menyerahkannya ke
/// pemasang bawaan Android.
///
/// Sebelumnya tombol Unduh cuma membuka tautan di browser. Itu berarti
/// orangnya berpindah aplikasi, menunggu di sana, mencari berkasnya di
/// folder unduhan, lalu membukanya sendiri — empat langkah yang
/// masing-masing bisa membuat orang berhenti di tengah jalan. Dan di
/// sebagian HP, browser bawaannya justru menampilkan peringatan
/// menakutkan tentang berkas yang "mungkin berbahaya".
///
/// Di sini seluruhnya terjadi di satu layar: unduh berikut angka
/// kemajuannya, lalu layar pemasang langsung terbuka.
class ApkUpdater {
  /// Perkembangan unduhan, 0..1. Null berarti panjang berkasnya tidak
  /// diberitahukan server — jarang, tapi mungkin.
  final void Function(double? progress)? onProgress;

  ApkUpdater({this.onProgress});

  http.Client? _client;

  /// Membatalkan unduhan yang sedang berjalan.
  void cancel() {
    _client?.close();
    _client = null;
  }

  /// Mengunduh lalu membuka pemasangnya.
  ///
  /// Mengembalikan null kalau berhasil, atau keterangan galat yang layak
  /// dibaca orang biasa.
  Future<String?> downloadAndInstall(String url) async {
    // Android menolak memasang aplikasi dari luar Play Store sampai izin
    // ini diberikan. Tanpa memintanya lebih dulu, unduhannya berhasil
    // lalu layar pemasangnya muncul kosong — terlihat persis seperti
    // aplikasinya yang rusak.
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        return 'Izin memasang aplikasi belum diberikan. Aktifkan lewat '
            'Setelan HP → Aplikasi → KaataGo → Izinkan dari sumber ini.';
      }
    }

    final File file;
    try {
      file = await _download(url);
    } on _Cancelled {
      return null;
    } catch (e) {
      return 'Gagal mengunduh: $e';
    }

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      return 'Berkasnya sudah terunduh, tapi pemasangnya tidak bisa dibuka: '
          '${result.message}';
    }
    return null;
  }

  Future<File> _download(String url) async {
    final client = http.Client();
    _client = client;
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw 'server menjawab ${response.statusCode}';
      }

      // Disimpan di folder milik aplikasi sendiri, bukan folder Unduhan
      // bersama: berkas 80 MB yang tertinggal di Unduhan akan
      // membingungkan orangnya berbulan-bulan kemudian, sementara yang
      // di sini ikut terhapus saat aplikasinya dicopot.
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/KaataGo-update.apk');
      // Sisa unduhan yang gagal sebelumnya harus dibuang dulu —
      // menambahkan byte baru ke belakangnya menghasilkan berkas rusak
      // yang gagal dipasang tanpa sebab yang jelas.
      if (await file.exists()) await file.delete();

      final sink = file.openWrite();
      final total = response.contentLength;
      var received = 0;

      await for (final chunk in response.stream) {
        if (_client == null) {
          await sink.close();
          await file.delete();
          throw const _Cancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null || total == 0 ? null : received / total);
      }
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      _client?.close();
      _client = null;
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
