import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tagihan QRIS yang sudah terbit di penyedia pembayaran.
class QrisCharge {
  /// Isi kode QR-nya, apa adanya dari penyedia.
  final String qrString;

  /// Nominal yang benar-benar ditagihkan, dibaca dari pesanan di server.
  ///
  /// Ditampilkan dari sini, bukan dari hitungan di HP: yang dibayar
  /// orang harus berasal dari sumber yang sama dengan yang dituntut
  /// QR-nya. Dua tempat menghitung angka yang sama adalah dua tempat
  /// yang bisa berbeda.
  final int amount;

  final DateTime expiresAt;

  QrisCharge({
    required this.qrString,
    required this.amount,
    required this.expiresAt,
  });

  Duration get remaining => expiresAt.difference(DateTime.now());
  bool get isExpired => remaining.isNegative;
}

/// Meminta tagihan QRIS ke penyedia lewat Edge Function.
///
/// Aplikasi hanya menyebut nomor pesanannya. Nominalnya sengaja tidak
/// ikut dikirim — server yang membacanya sendiri dari pesanan itu.
/// Nominal yang datang dari HP bisa diubah siapa pun yang mau membayar
/// seratus ribu dengan seribu rupiah.
class PaymentGatewayService {
  final _client = Supabase.instance.client;

  /// Membuat (atau memakai ulang) tagihan untuk sebuah pesanan.
  ///
  /// Mengembalikan null kalau penyedia pembayarannya belum dipasang di
  /// resto ini — dan itu bukan kegagalan: layar pemanggilnya kembali ke
  /// QR simulasi seperti sebelumnya. Resto yang belum punya akun
  /// gateway tetap harus bisa menerima pesanan.
  Future<QrisCharge?> createQris(String orderId) async {
    try {
      final res = await _client.functions.invoke(
        'create-qris',
        body: {'order_id': orderId},
      );

      final data = res.data;
      if (data is! Map || data['qr_string'] == null) {
        debugPrint('[QRIS] jawaban tidak terduga: $data');
        return null;
      }

      return QrisCharge(
        qrString: data['qr_string'] as String,
        amount: (data['amount'] as num).toInt(),
        expiresAt: DateTime.parse(data['expires_at'] as String).toLocal(),
      );
    } catch (e) {
      // Termasuk saat kuncinya belum dipasang. Dicatat, tapi tidak
      // dilempar ke atas: layar pembayaran yang gagal terbuka jauh lebih
      // merugikan daripada layar pembayaran yang jatuh ke cara lama.
      debugPrint('[QRIS] gagal membuat tagihan: $e');
      return null;
    }
  }
}
