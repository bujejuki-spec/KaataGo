import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/absensi.dart';
import '../utils/gambar_unggah.dart';
import '../utils/mesin_wajah.dart';

/// Absensi wajah berlokasi, dan aturan gaji yang menghitung darinya.
///
/// Yang menulis absensi seluruhnya RPC, bukan insert biasa. Baris
/// absensi yang bisa disisipkan aplikasi adalah baris yang bisa
/// disisipkan tanpa wajah, tanpa GPS, dan bertanggal kapan saja — dan
/// gaji yang dihitung dari baris semacam itu tidak berarti apa-apa.
class AbsensiRepository {
  final _client = Supabase.instance.client;

  /// Ember lama, masih disebut saat MEMBACA berkas yang terlanjur
  /// tersimpan di sana sebelum gambar pindah ke base64.
  static const emberLama = 'absensi';

  static String _tgl(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Wajah ──────────────────────────────────────────────────────────

  Future<bool> wajahTerdaftar(String restoId) async {
    final hasil =
        await _client.rpc('wajah_terdaftar', params: {'p_resto_id': restoId});
    return hasil == true;
  }

  /// [setujuVersi] adalah versi teks persetujuan yang dicentang
  /// orangnya. Server menolak pendaftaran tanpa itu — kotak centang di
  /// layar menghalangi orang yang memakai aplikasi, bukan apa pun yang
  /// memanggil fungsinya langsung.
  Future<void> daftarWajah({
    required String restoId,
    required List<double> sidik,
    required String model,
    String? fotoUrl,
    required String setujuVersi,
  }) =>
      _client.rpc('daftar_wajah', params: {
        'p_resto_id': restoId,
        'p_embedding': sidik,
        'p_model': model,
        'p_foto_url': fotoUrl,
        'p_setuju_versi': setujuVersi,
      });

  Future<void> resetWajah(String restoId, String email) => _client
      .rpc('reset_wajah', params: {'p_resto_id': restoId, 'p_email': email});

  /// Memeriksa wajahnya sebelum fotonya diunggah.
  ///
  /// Jawabannya cuma ya atau tidak — skornya sengaja tidak dikembalikan
  /// server, karena fungsi yang menjawab dengan angka adalah alat untuk
  /// menaiki bukit: tebakan bisa diubah sedikit demi sedikit sambil
  /// melihat skornya naik, sampai lolos tanpa pernah menghadap kamera.
  ///
  /// Ini kenyamanan, bukan penjagaan. Yang menentukan sah tidaknya absen
  /// tetap pemeriksaan di dalam server saat absen dicatat.
  Future<bool> cocokkanWajah({
    required String restoId,
    required List<double> sidik,
  }) async {
    final hasil = await _client.rpc('cocokkan_wajah', params: {
      'p_resto_id': restoId,
      'p_embedding': sidik,
      'p_model': MesinWajah.namaModel,
    });
    return hasil == true;
  }

  // ── Absen ──────────────────────────────────────────────────────────

  Future<HasilAbsen> absen({
    required String restoId,
    required List<double> sidik,
    required double lat,
    required double lng,
    String? fotoUrl,
    required bool pulang,
  }) async {
    final rows = await _client.rpc(
      pulang ? 'absen_pulang' : 'absen_masuk',
      params: {
        'p_resto_id': restoId,
        'p_embedding': sidik,
        'p_lat': lat,
        'p_lng': lng,
        'p_foto_url': fotoUrl,
        // Ikut dikirim supaya server bisa MENOLAK kalau wajahnya
        // terdaftar dengan cara pengenalan yang lain. Sidik dari dua
        // cara berbeda tetap menghasilkan angka kalau dibandingkan, dan
        // angka itulah yang paling berbahaya: ia terlihat seperti
        // jawaban padahal tidak membandingkan apa pun.
        'p_model': MesinWajah.namaModel,
      },
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) {
      throw Exception('Absennya tidak tercatat. Coba lagi.');
    }
    return HasilAbsen.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  Future<void> ajukanTidakMasuk({
    required String restoId,
    required DateTime tanggal,
    required StatusAbsen status,
    required String alasan,
    String? buktiUrl,
  }) =>
      _client.rpc('ajukan_tidak_masuk', params: {
        'p_resto_id': restoId,
        'p_tanggal': _tgl(tanggal),
        'p_status': status.kode,
        'p_alasan': alasan,
        'p_bukti_url': buktiUrl,
      });

  // ── Membaca ────────────────────────────────────────────────────────

  /// Absensi satu rentang. RLS yang menentukan isinya: karyawan biasa
  /// hanya menerima barisnya sendiri, atasan menerima semuanya.
  Future<List<BarisAbsensi>> rentang(
    String restoId, {
    required DateTime mulai,
    required DateTime akhir,
    String? email,
  }) async {
    var q = _client
        .from('attendance')
        .select()
        .eq('resto_id', restoId)
        .gte('tanggal', _tgl(mulai))
        .lte('tanggal', _tgl(akhir));
    if (email != null) q = q.eq('employee_email', email.toLowerCase());

    final rows = await q.order('tanggal', ascending: false);
    return rows.map((r) => BarisAbsensi.fromMap(r)).toList();
  }

  /// Baris hari ini milik orang yang sedang masuk, atau null.
  Future<BarisAbsensi?> hariIni(String restoId, String email) async {
    final kini = DateTime.now().toUtc().add(const Duration(hours: 7));
    final hari = DateTime(kini.year, kini.month, kini.day);
    final rows = await _client
        .from('attendance')
        .select()
        .eq('resto_id', restoId)
        .eq('employee_email', email.toLowerCase())
        .eq('tanggal', _tgl(hari))
        .limit(1);
    if (rows.isEmpty) return null;
    return BarisAbsensi.fromMap(rows.first);
  }

  /// Foto acuan tiap karyawan — yang didaftarkan sekali di awal.
  ///
  /// Dipakai layar Absensi Karyawan untuk menyandingkannya dengan foto
  /// absen hari itu. Pemeriksaan otomatis menangkap yang bentuk
  /// wajahnya jelas berbeda; yang halus ditangkap mata orang, dan cuma
  /// bisa ditangkap kalau kedua fotonya benar-benar bersebelahan.
  /// Foto acuan tiap karyawan: base64 kalau ada, jalur lama kalau belum.
  ///
  /// Wajah yang didaftarkan sebelum gambar pindah ke base64 masih
  /// menunjuk ke berkas di Storage. Memilih salah satu saja berarti
  /// separuh acuan berubah jadi kotak kosong — tepat di layar tempat
  /// seseorang memutuskan absen ini benar orangnya atau bukan.
  Future<Map<String, ({String? base64, String? jalurLama})>> fotoAcuan(
      String restoId) async {
    final rows =
        await _client.rpc('foto_acuan_wajah', params: {'p_resto_id': restoId});
    final hasil = <String, ({String? base64, String? jalurLama})>{};
    for (final r in (rows as List? ?? const [])) {
      final m = r as Map;
      final b64 = m['foto_base64']?.toString();
      final lama = m['foto_url']?.toString();
      if ((b64 == null || b64.isEmpty) && (lama == null || lama.isEmpty)) {
        continue;
      }
      hasil[m['employee_email'].toString().toLowerCase()] =
          (base64: b64, jalurLama: lama);
    }
    return hasil;
  }

  /// Atasan membetulkan statusnya, atau memutuskan potong gaji.
  Future<void> putuskan({
    required String id,
    StatusAbsen? status,
    bool? potongGaji,
    required String oleh,
  }) =>
      _client.from('attendance').update({
        if (status != null) 'status': status.kode,
        if (potongGaji != null) 'potong_gaji': potongGaji,
        'diputuskan_oleh': oleh,
      }).eq('id', id);

  // ── Berkas ─────────────────────────────────────────────────────────

  /// Menyiapkan gambar untuk disimpan sebagai base64.
  ///
  /// Dulu ia mengunggah berkas ke Storage dan mengembalikan jalurnya.
  /// Sekarang gambarnya tersimpan di baris absensinya sendiri, jadi
  /// tidak ada yang perlu diunggah — yang tersisa memeriksa format dan
  /// ukurannya, lalu mengubahnya jadi teks.
  ///
  /// Nama parameternya di sisi server masih `p_foto_url` dan
  /// `p_bukti_url`. Tanda tangannya sengaja tidak diubah: daftar
  /// parameter yang berbeda membuat fungsi KEDUA dengan nama yang sama,
  /// dan aplikasi yang belum diperbarui akan memanggil yang lama tanpa
  /// satu pun galat yang menjelaskan kenapa fotonya tidak muncul.
  String siapkanGambar(Uint8List bytes) =>
      // Wajah dan surat sakit sama-sama harus terbaca mata orang yang
      // memutuskan gaji, jadi tidak dikecilkan sekecil foto menu.
      GambarUnggah.siapkan(bytes, sisiMaks: 1400, mutu: 82);
}
