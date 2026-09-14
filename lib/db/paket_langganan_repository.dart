import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/paket_langganan.dart';

/// Paket langganan: harganya, keadaan merchant, dan pengajuannya.
///
/// Yang mengubah keadaan seluruhnya RPC. Baris yang menentukan uang dan
/// akses tidak boleh bisa disisipkan aplikasi — yang bisa menyisipkannya
/// sendiri bisa menyisipkan yang statusnya sudah 'selesai'.
class PaketLanggananRepository {
  final _client = Supabase.instance.client;

  static const _ember = 'absensi';

  Future<List<InfoPaket>> daftarPaket() async {
    final rows =
        await _client.from('paket_langganan').select().order('urutan');
    return rows.map((r) => InfoPaket.fromMap(r)).toList();
  }

  /// Mengubah harga dan keterangan sebuah paket.
  ///
  /// Tidak menyentuh merchant yang sudah berlangganan. Harga mereka
  /// sudah disalin ke `resto_billing` saat paketnya disetel, dan
  /// mengubahnya dari sini berarti menaikkan tagihan orang yang tidak
  /// pernah menyepakati angka barunya.
  Future<void> simpanHarga({
    required Paket paket,
    required int harga,
    required String keterangan,
    required String oleh,
  }) =>
      _client.from('paket_langganan').update({
        'harga_bulanan': harga,
        'keterangan': keterangan,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': oleh,
      }).eq('kode', paket.kode);

  Future<KeadaanLangganan> keadaan(String restoId) async {
    final rows = await _client
        .rpc('keadaan_langganan', params: {'p_resto_id': restoId});
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return const KeadaanLangganan();
    return KeadaanLangganan.fromMap(
        Map<String, dynamic>.from(list.first as Map));
  }

  // ── Merchant ────────────────────────────────────────────────────────

  /// Mengunggah bukti transfer, mengembalikan JALUR-nya.
  ///
  /// Menumpang ember `absensi` yang sudah tertutup dari umum, bukan
  /// membuat ember baru: bukti transfer sama tidak pantasnya untuk bisa
  /// dibuka siapa pun yang menebak URL-nya.
  Future<String> unggahBukti({
    required String restoId,
    required Uint8List bytes,
  }) async {
    final nama = '$restoId/langganan/'
        '${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from(_ember).uploadBinary(
          nama,
          bytes,
          fileOptions: const FileOptions(
              contentType: 'image/jpeg', upsert: true),
        );
    return nama;
  }

  Future<String> ajukan({
    required String restoId,
    required Paket paket,
    required String buktiUrl,
    String? catatan,
  }) async {
    final id = await _client.rpc('ajukan_langganan', params: {
      'p_resto_id': restoId,
      'p_paket': paket.kode,
      'p_bukti_url': buktiUrl,
      'p_catatan': catatan,
    });
    return id.toString();
  }

  // ── KaataGo Admin ───────────────────────────────────────────────────

  Future<List<PengajuanLangganan>> pengajuan({String? status}) async {
    var q = _client
        .from('subscription_requests')
        .select('*, restaurants(name)');
    if (status != null) q = q.eq('status', status);
    final rows = await q.order('diajukan_at', ascending: false).limit(200);
    return rows.map((r) => PengajuanLangganan.fromMap(r)).toList();
  }

  Future<void> putuskan({
    required String id,
    required bool setuju,
    String? alasan,
  }) =>
      _client.rpc('putuskan_langganan', params: {
        'p_request_id': id,
        'p_setuju': setuju,
        'p_alasan': alasan,
      });

  /// Menyetel paket merchant langsung, tanpa lewat pengajuan.
  ///
  /// Dipakai saat merchant membayar di luar aplikasi, atau saat
  /// KaataGo memindahkan merchant lama ke jalur paket.
  Future<void> setelPaket({
    required String restoId,
    required Paket? paket,
    int? harga,
  }) =>
      _client.rpc('set_paket_resto', params: {
        'p_resto_id': restoId,
        'p_paket': paket?.kode,
        'p_harga': harga,
      });

  /// Memberi masa percobaan sekian hari, dihitung dari hari ini.
  ///
  /// Paketnya ikut disebut: yang mencoba Basic memang harus melihat
  /// Basic, bukan mencicipi Premium dua minggu lalu kehilangan separuh
  /// menunya persis di hari dia mulai membayar.
  Future<DateTime> setelPercobaan({
    required String restoId,
    required int hari,
    required Paket paket,
  }) async {
    final sampai = await _client.rpc('set_trial_resto', params: {
      'p_resto_id': restoId,
      'p_hari': hari,
      'p_paket': paket.kode,
    });
    return DateTime.parse(sampai.toString());
  }

  /// Keadaan seluruh merchant sekaligus, untuk layar KaataGo Admin.
  ///
  /// Satu panggilan, bukan satu per baris: layarnya menampilkan puluhan
  /// merchant, dan menanyakannya satu per satu berarti puluhan
  /// panggilan tiap kali layarnya dibuka.
  Future<Map<String, KeadaanLangganan>> keadaanSemua() async {
    final rows = await _client.rpc('keadaan_langganan_semua');
    return {
      for (final r in (rows as List? ?? const []))
        (r as Map)['resto_id'].toString():
            KeadaanLangganan.fromMap(Map<String, dynamic>.from(r)),
    };
  }

  /// Berapa pengajuan yang menunggu diperiksa — isi penanda merah di
  /// menu KaataGo Admin.
  Future<int> jumlahMenunggu() async {
    return await _client
        .from('subscription_requests')
        .count(CountOption.exact)
        .eq('status', 'verifikasi');
  }
}
