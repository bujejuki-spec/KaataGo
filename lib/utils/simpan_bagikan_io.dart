import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Menyimpan ke berkas sementara lalu membuka lembar bagikan.
///
/// Tidak langsung ditaruh di folder Unduhan: Android sejak versi 10
/// tidak mengizinkannya tanpa izin penyimpanan yang lebih luas daripada
/// yang pantas diminta aplikasi kasir. Lembar bagikan membuat orangnya
/// sendiri yang memilih tujuannya — Drive, WhatsApp, atau Berkas.
Future<void> simpanLaluBagikan(
    Uint8List bytes, String nama, String tipe) async {
  final dir = await getTemporaryDirectory();
  final berkas = File('${dir.path}/$nama');
  await berkas.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(berkas.path, mimeType: tipe)], subject: nama);
}
