import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/absensi.dart';

/// Absensi wajah berlokasi, dan aturan gaji yang menghitung darinya.
///
/// Yang menulis absensi seluruhnya RPC, bukan insert biasa. Baris
/// absensi yang bisa disisipkan aplikasi adalah baris yang bisa
/// disisipkan tanpa wajah, tanpa GPS, dan bertanggal kapan saja — dan
/// gaji yang dihitung dari baris semacam itu tidak berarti apa-apa.
class AbsensiRepository {
  final _client = Supabase.instance.client;

  static const _ember = 'absensi';

  static String _tgl(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Wajah ──────────────────────────────────────────────────────────

  Future<bool> wajahTerdaftar(String restoId) async {
    final hasil =
        await _client.rpc('wajah_terdaftar', params: {'p_resto_id': restoId});
    return hasil == true;
  }

  Future<void> daftarWajah({
    required String restoId,
    required List<double> sidik,
    required String model,
    String? fotoUrl,
  }) =>
      _client.rpc('daftar_wajah', params: {
        'p_resto_id': restoId,
        'p_embedding': sidik,
        'p_model': model,
        'p_foto_url': fotoUrl,
      });

  Future<void> resetWajah(String restoId, String email) => _client
      .rpc('reset_wajah', params: {'p_resto_id': restoId, 'p_email': email});

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
  Future<Map<String, String>> fotoAcuan(String restoId) async {
    final rows =
        await _client.rpc('foto_acuan_wajah', params: {'p_resto_id': restoId});
    return {
      for (final r in (rows as List? ?? const []))
        if ((r as Map)['foto_url'] != null)
          r['employee_email'].toString().toLowerCase():
              r['foto_url'].toString(),
    };
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

  /// Mengunggah foto absen atau surat sakit, mengembalikan JALUR-nya.
  ///
  /// Jalur, bukan URL publik. Embernya tertutup — alamat publiknya
  /// selalu ditolak, dan penolakannya baru terlihat berbulan-bulan
  /// kemudian sebagai kotak "Gagal dimuat". Yang menampilkannya membuat
  /// URL bertanda tangan saat gambarnya mau dilihat.
  ///
  /// Namanya memuat email dan waktunya, bukan angka acak: berkas yang
  /// tidak bisa dikenali dari namanya hanya bisa ditelusuri lewat baris
  /// yang menunjuknya — dan kalau barisnya yang hilang, yang tersisa
  /// adalah ember berisi ribuan gambar tanpa pemilik.
  Future<String> unggah({
    required String restoId,
    required String email,
    required Uint8List bytes,
    required String jenis,
    String ekstensi = 'jpg',
  }) async {
    final nama = '$restoId/$jenis/'
        '${email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_'
        '${DateTime.now().millisecondsSinceEpoch}.$ekstensi';
    await _client.storage.from(_ember).uploadBinary(
          nama,
          bytes,
          fileOptions: FileOptions(
            contentType: ekstensi == 'pdf' ? 'application/pdf' : 'image/jpeg',
            upsert: true,
          ),
        );
    return nama;
  }
}
