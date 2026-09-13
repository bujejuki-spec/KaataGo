import 'dart:typed_data';

import 'unduh_web.dart';

/// Di peramban, berkasnya diunduh langsung — tidak ada lembar bagikan
/// untuk dibuka, dan folder Unduhan memang tujuan yang diharapkan
/// orangnya.
Future<void> simpanLaluBagikan(
    Uint8List bytes, String nama, String tipe) async {
  unduhBerkasWeb(bytes, nama, tipe);
}
