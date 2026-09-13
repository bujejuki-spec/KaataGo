/// Paket langganan yang ditawarkan KaataGo.
enum Paket { basic, premium }

extension PaketKode on Paket {
  String get kode => name;

  String get label => switch (this) {
        Paket.basic => 'Basic',
        Paket.premium => 'Premium',
      };
}

Paket? paketDari(String? kode) => switch (kode) {
      'basic' => Paket.basic,
      'premium' => Paket.premium,
      _ => null,
    };

/// Satu paket berikut harganya, dibaca dari server.
///
/// Harganya tidak ditulis di aplikasi. Harga yang tertanam di kode
/// berarti menaikkannya menuntut merilis APK baru — dan selama sebagian
/// merchant belum memperbarui aplikasinya, dua merchant melihat dua
/// harga berbeda untuk paket yang sama.
class InfoPaket {
  final Paket paket;
  final String nama;
  final int harga;
  final String keterangan;

  const InfoPaket({
    required this.paket,
    required this.nama,
    required this.harga,
    required this.keterangan,
  });

  factory InfoPaket.fromMap(Map<String, dynamic> map) => InfoPaket(
        paket: paketDari(map['kode']?.toString()) ?? Paket.basic,
        nama: map['nama']?.toString() ?? '',
        harga: (map['harga_bulanan'] as num?)?.toInt() ?? 0,
        keterangan: map['keterangan']?.toString() ?? '',
      );
}

/// Bagaimana langganan sebuah merchant berdiri saat ini.
class KeadaanLangganan {
  final Paket? paket;
  final String? namaPaket;
  final int harga;

  final DateTime? trialSampai;
  final int? trialHari;

  /// Sisa hari percobaan. Negatif berarti sudah lewat.
  final int? sisaHari;

  final bool dalamPercobaan;
  final bool percobaanHabis;

  /// 'verifikasi' | 'selesai' | 'ditolak' | null
  final String? statusPengajuan;
  final String? alasanTolak;

  final bool terkunciPaket;

  const KeadaanLangganan({
    this.paket,
    this.namaPaket,
    this.harga = 0,
    this.trialSampai,
    this.trialHari,
    this.sisaHari,
    this.dalamPercobaan = false,
    this.percobaanHabis = false,
    this.statusPengajuan,
    this.alasanTolak,
    this.terkunciPaket = false,
  });

  /// Merchant ini memang tidak pernah dimasukkan ke jalur paket.
  ///
  /// Yang belum pernah disentuh KaataGo Admin berjalan persis seperti
  /// sebelumnya — tanpa paket, tanpa percobaan, tanpa kunci.
  bool get diluarJalurPaket => paket == null && trialSampai == null;

  bool get sedangDiperiksa => statusPengajuan == 'verifikasi';
  bool get pengajuanDitolak => statusPengajuan == 'ditolak';

  /// Sudah waktunya diingatkan: dua hari lagi atau kurang.
  bool get mendekatiHabis =>
      dalamPercobaan && sisaHari != null && sisaHari! <= 2;

  factory KeadaanLangganan.fromMap(Map<String, dynamic> map) =>
      KeadaanLangganan(
        paket: paketDari(map['paket']?.toString()),
        namaPaket: map['nama_paket']?.toString(),
        harga: (map['harga'] as num?)?.toInt() ?? 0,
        trialSampai: map['trial_until'] == null
            ? null
            : DateTime.parse(map['trial_until'].toString()),
        trialHari: (map['trial_days'] as num?)?.toInt(),
        sisaHari: (map['sisa_hari'] as num?)?.toInt(),
        dalamPercobaan: map['dalam_percobaan'] == true,
        percobaanHabis: map['percobaan_habis'] == true,
        statusPengajuan: map['status_pengajuan']?.toString(),
        alasanTolak: map['alasan_tolak']?.toString(),
        terkunciPaket: map['terkunci_paket'] == true,
      );
}

/// Satu pengajuan berlangganan, dilihat KaataGo Admin.
class PengajuanLangganan {
  final String id;
  final String restoId;
  final String namaResto;
  final Paket paket;
  final int harga;
  final String status;
  final String buktiUrl;
  final String? catatan;
  final String? diajukanOleh;
  final DateTime diajukanAt;
  final String? alasanTolak;

  const PengajuanLangganan({
    required this.id,
    required this.restoId,
    required this.namaResto,
    required this.paket,
    required this.harga,
    required this.status,
    required this.buktiUrl,
    this.catatan,
    this.diajukanOleh,
    required this.diajukanAt,
    this.alasanTolak,
  });

  bool get menunggu => status == 'verifikasi';

  factory PengajuanLangganan.fromMap(Map<String, dynamic> map) =>
      PengajuanLangganan(
        id: map['id']?.toString() ?? '',
        restoId: map['resto_id']?.toString() ?? '',
        // Nama restonya ikut lewat join; kalau tidak ada, idnya sendiri
        // sudah cukup untuk dikenali KaataGo Admin.
        namaResto: (map['restaurants'] is Map
                ? (map['restaurants'] as Map)['name']?.toString()
                : null) ??
            map['nama_resto']?.toString() ??
            map['resto_id']?.toString() ??
            '',
        paket: paketDari(map['paket']?.toString()) ?? Paket.basic,
        harga: (map['harga'] as num?)?.toInt() ?? 0,
        status: map['status']?.toString() ?? 'verifikasi',
        buktiUrl: map['bukti_url']?.toString() ?? '',
        catatan: map['catatan'] as String?,
        diajukanOleh: map['diajukan_oleh'] as String?,
        diajukanAt: DateTime.parse(map['diajukan_at'].toString()).toUtc(),
        alasanTolak: map['alasan_tolak'] as String?,
      );
}
