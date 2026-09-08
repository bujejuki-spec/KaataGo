import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/metode_bayar.dart';

/// Metode bayar yang ditawarkan merchant, berikut QR statisnya.
///
/// Dibaca dari baris `settings` yang sama dengan info pembayaran lain —
/// satu baris per merchant, dan sudah disiarkan realtime ke layar
/// pelanggan. Gambarnya sendiri di Storage, bukan di baris itu: tabel
/// yang disiarkan mengirim ulang seluruh barisnya tiap kali satu kolom
/// berubah, ke semua orang yang sedang membuka layarnya.
class MetodeBayarRepository {
  static const ember = 'qris-statis';

  final _client = Supabase.instance.client;

  Future<MetodeBayarMerchant> baca(String restoId) async {
    final rows = await _client
        .from('settings')
        .select()
        .eq('resto_id', restoId)
        .limit(1);
    if (rows.isEmpty) return const MetodeBayarMerchant();
    return MetodeBayarMerchant.fromMap(rows.first);
  }

  /// Aliran langsung, supaya layar pembayaran pelanggan ikut berubah
  /// saat merchant mematikan sebuah metode — tanpa pelanggan perlu
  /// memuat ulang halamannya.
  Stream<MetodeBayarMerchant> pantau(String restoId) => _client
      .from('settings')
      .stream(primaryKey: ['resto_id'])
      .eq('resto_id', restoId)
      .limit(1)
      .map((rows) => rows.isEmpty
          ? const MetodeBayarMerchant()
          : MetodeBayarMerchant.fromMap(rows.first));

  Future<void> simpan(String restoId, MetodeBayarMerchant metode) async {
    await _client.from('settings').upsert({
      'resto_id': restoId,
      ...metode.toMap(),
    });
  }

  /// Mengunggah gambar QR statisnya, lalu mengembalikan tautannya.
  ///
  /// Berkasnya bernama menurut id restonya dan ditimpa tiap kali diganti:
  /// tiap merchant hanya punya satu QR statis, dan menyimpan yang lama
  /// berarti menyimpan QR yang tidak lagi dipakai siapa pun tapi tetap
  /// bisa dibuka siapa pun yang punya tautannya.
  Future<String> unggahQr(String restoId, Uint8List bytes) async {
    final nama = '$restoId.png';
    await _client.storage.from(ember).uploadBinary(
          nama,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    // Penanda versi: nama berkasnya tetap, jadi QR yang diganti punya
    // tautan yang sama persis dengan yang lama — dan CDN akan terus
    // menyajikan gambar lama entah sampai kapan. Yang menerima akibatnya
    // pelanggan yang membayar ke QR yang sudah tidak dipakai.
    final dasar = _client.storage.from(ember).getPublicUrl(nama);
    return '$dasar?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> hapusQr(String restoId) async {
    await _client.storage.from(ember).remove(['$restoId.png']);
  }
}
