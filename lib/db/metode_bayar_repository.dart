import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/metode_bayar.dart';
import '../utils/gambar_unggah.dart';

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

  /// Menyiapkan gambar QR statis sebagai base64.
  ///
  /// Dulu berkasnya naik ke Storage dan yang disimpan tautan publiknya,
  /// lengkap dengan penanda versi — karena nama berkasnya tetap, QR yang
  /// diganti punya tautan yang sama persis dan CDN terus menyajikan
  /// gambar lama. Yang menerima akibatnya pelanggan yang membayar ke QR
  /// yang sudah tidak dipakai.
  ///
  /// Base64 tidak punya masalah itu sama sekali: yang tersimpan gambarnya
  /// sendiri, bukan alamat yang menunjuk ke sesuatu yang bisa berubah
  /// di belakang.
  ///
  /// Mutunya dijaga tinggi dan tidak dikecilkan banyak: ini QR yang akan
  /// dipindai kamera HP pelanggan, dan kotak-kotak kecilnya adalah
  /// datanya — bukan hiasan yang boleh kabur.
  String siapkanQr(Uint8List bytes) =>
      GambarUnggah.siapkan(bytes, sisiMaks: 1200, mutu: 92);

  /// Membuang berkas QR lama di Storage, kalau merchant ini memang
  /// pernah memasangnya di sana.
  ///
  /// Dipanggil saat QR-nya dilepas. Yang base64 ikut hilang bersama
  /// barisnya; yang di Storage harus dibuang sendiri, kalau tidak ia
  /// tetap bisa dibuka siapa pun yang pernah menyimpan tautannya.
  Future<void> hapusQr(String restoId) async {
    try {
      await _client.storage.from(ember).remove(['$restoId.png']);
    } catch (_) {
      // Merchant yang QR-nya memang tidak pernah di Storage juga sampai
      // ke sini, dan itu keadaan yang benar.
    }
  }
}
