/// Kenapa seseorang tidak ada di tempat kerja hari itu.
enum StatusAbsen { hadir, izin, sakit, cuti, alpa }

extension StatusAbsenDb on StatusAbsen {
  String get kode => name;

  String get label => switch (this) {
        StatusAbsen.hadir => 'Hadir',
        StatusAbsen.izin => 'Izin',
        StatusAbsen.sakit => 'Sakit',
        StatusAbsen.cuti => 'Cuti',
        StatusAbsen.alpa => 'Alpa',
      };
}

StatusAbsen statusAbsenDari(String? kode) => switch (kode) {
      'izin' => StatusAbsen.izin,
      'sakit' => StatusAbsen.sakit,
      'cuti' => StatusAbsen.cuti,
      'alpa' => StatusAbsen.alpa,
      _ => StatusAbsen.hadir,
    };

/// Satu hari absensi satu orang.
class BarisAbsensi {
  final String id;
  final String email;
  final DateTime tanggal;
  final StatusAbsen status;

  final DateTime? masukAt;
  final DateTime? pulangAt;
  final double? masukLat;
  final double? masukLng;
  final int? masukJarakM;
  final String? masukFotoUrl;
  final double? pulangLat;
  final double? pulangLng;
  final String? pulangFotoUrl;

  final String? alasan;
  final String? buktiUrl;
  final bool potongGaji;

  /// Kemiripan wajahnya jatuh di pita ragu-ragu: diterima, tapi pantas
  /// dilihat orang sebelum gajinya dihitung.
  final bool masukRagu;
  final bool pulangRagu;

  const BarisAbsensi({
    required this.id,
    required this.email,
    required this.tanggal,
    required this.status,
    this.masukAt,
    this.pulangAt,
    this.masukLat,
    this.masukLng,
    this.masukJarakM,
    this.masukFotoUrl,
    this.pulangLat,
    this.pulangLng,
    this.pulangFotoUrl,
    this.alasan,
    this.buktiUrl,
    this.potongGaji = false,
    this.masukRagu = false,
    this.pulangRagu = false,
  });

  bool get ragu => masukRagu || pulangRagu;

  bool get sudahMasuk => masukAt != null;
  bool get sudahPulang => pulangAt != null;

  /// Berapa lama di tempat kerja, atau null kalau belum pulang.
  Duration? get lama =>
      masukAt == null || pulangAt == null ? null : pulangAt!.difference(masukAt!);

  /// "7j 45m", atau null kalau belum pulang.
  ///
  /// Diformat di satu tempat, bukan di tiap layar dan tiap ekspor.
  /// Angka jam kerja yang ditulis berbeda-beda di tiga tempat akan
  /// suatu hari dijumlahkan orang dan tidak cocok.
  String? get lamaTeks {
    final d = lama;
    if (d == null || d.isNegative) return null;
    return '${d.inHours}j ${d.inMinutes % 60}m';
  }

  /// Lama kerja dalam jam, untuk dijumlahkan.
  double get lamaJam => (lama?.inMinutes ?? 0) / 60.0;

  factory BarisAbsensi.fromMap(Map<String, dynamic> map) => BarisAbsensi(
        id: map['id']?.toString() ?? '',
        email: map['employee_email']?.toString() ?? '',
        tanggal: DateTime.parse(map['tanggal'].toString()),
        status: statusAbsenDari(map['status']?.toString()),
        masukAt: _waktu(map['masuk_at']),
        pulangAt: _waktu(map['pulang_at']),
        masukLat: (map['masuk_lat'] as num?)?.toDouble(),
        masukLng: (map['masuk_lng'] as num?)?.toDouble(),
        masukJarakM: (map['masuk_jarak_m'] as num?)?.toInt(),
        masukFotoUrl: map['masuk_foto_url'] as String?,
        pulangLat: (map['pulang_lat'] as num?)?.toDouble(),
        pulangLng: (map['pulang_lng'] as num?)?.toDouble(),
        pulangFotoUrl: map['pulang_foto_url'] as String?,
        alasan: map['alasan'] as String?,
        buktiUrl: map['bukti_url'] as String?,
        potongGaji: map['potong_gaji'] == true,
        masukRagu: map['masuk_ragu'] == true,
        pulangRagu: map['pulang_ragu'] == true,
      );

  static DateTime? _waktu(dynamic v) =>
      v == null ? null : DateTime.parse(v.toString()).toUtc();
}

/// Hasil satu absen yang diterima server.
class HasilAbsen {
  final int jarakM;
  final double skor;
  final DateTime waktu;

  const HasilAbsen(
      {required this.jarakM, required this.skor, required this.waktu});

  factory HasilAbsen.fromMap(Map<String, dynamic> map) => HasilAbsen(
        jarakM: (map['jarak_m'] as num?)?.toInt() ?? 0,
        skor: (map['skor'] as num?)?.toDouble() ?? 0,
        waktu: DateTime.parse(map['waktu'].toString()).toUtc(),
      );
}

/// Aturan gaji satu merchant.
class AturanGaji {
  final int tanggalGajian;
  final int hariKerjaPeriode;
  final double bpjsKesehatanPersen;
  final double bpjsTkPersen;
  final int radiusAbsenM;

  const AturanGaji({
    this.tanggalGajian = 25,
    this.hariKerjaPeriode = 25,
    this.bpjsKesehatanPersen = 0,
    this.bpjsTkPersen = 0,
    this.radiusAbsenM = 150,
  });

  factory AturanGaji.fromMap(Map<String, dynamic> map) => AturanGaji(
        tanggalGajian: (map['tanggal_gajian'] as num?)?.toInt() ?? 25,
        hariKerjaPeriode: (map['hari_kerja_periode'] as num?)?.toInt() ?? 25,
        bpjsKesehatanPersen:
            (map['bpjs_kesehatan_persen'] as num?)?.toDouble() ?? 0,
        bpjsTkPersen: (map['bpjs_tk_persen'] as num?)?.toDouble() ?? 0,
        radiusAbsenM: (map['radius_absen_m'] as num?)?.toInt() ?? 150,
      );

  Map<String, dynamic> toMap() => {
        'tanggal_gajian': tanggalGajian,
        'hari_kerja_periode': hariKerjaPeriode,
        'bpjs_kesehatan_persen': bpjsKesehatanPersen,
        'bpjs_tk_persen': bpjsTkPersen,
        'radius_absen_m': radiusAbsenM,
      };

  /// Periode gaji yang berakhir pada tanggal gajian di [bulan].
  ///
  /// Gajian tanggal 25 berarti periode 26 bulan lalu sampai 25 bulan ini.
  /// Bukan bulan kalender: yang dibayar tanggal 25 adalah kerja sampai
  /// tanggal 25, dan memakai 1-31 berarti membayar lima hari yang belum
  /// dikerjakan.
  ({DateTime mulai, DateTime akhir}) periodeUntuk(DateTime bulan) {
    final akhir = DateTime(bulan.year, bulan.month, tanggalGajian);
    final mulai = DateTime(bulan.year, bulan.month - 1, tanggalGajian + 1);
    return (mulai: mulai, akhir: akhir);
  }
}

/// Gaji dan rekening satu karyawan.
class GajiKaryawan {
  final String email;
  final int gajiPokok;
  final int tunjangan;
  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;

  const GajiKaryawan({
    required this.email,
    this.gajiPokok = 0,
    this.tunjangan = 0,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
  });

  factory GajiKaryawan.fromMap(Map<String, dynamic> map) => GajiKaryawan(
        email: map['employee_email']?.toString() ?? '',
        gajiPokok: (map['gaji_pokok'] as num?)?.toInt() ?? 0,
        tunjangan: (map['tunjangan'] as num?)?.toInt() ?? 0,
        bankName: map['bank_name'] as String?,
        accountNumber: map['account_number'] as String?,
        accountHolder: map['account_holder'] as String?,
      );
}

/// Satu baris rekap gaji — hasil hitungan server untuk satu periode.
class BarisPayroll {
  final String email;
  final String nama;
  final String peran;

  final int gajiPokok;
  final int tunjangan;
  final int hariKerja;

  final int hadir;
  final int izin;
  final int sakit;
  final int cuti;
  final int alpa;
  final int hariPotong;

  final int potonganAbsen;
  final int potonganBpjsKesehatan;
  final int potonganBpjsTk;
  final int gajiBersih;

  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;

  const BarisPayroll({
    required this.email,
    required this.nama,
    required this.peran,
    required this.gajiPokok,
    required this.tunjangan,
    required this.hariKerja,
    required this.hadir,
    required this.izin,
    required this.sakit,
    required this.cuti,
    required this.alpa,
    required this.hariPotong,
    required this.potonganAbsen,
    required this.potonganBpjsKesehatan,
    required this.potonganBpjsTk,
    required this.gajiBersih,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
  });

  int get totalPotongan =>
      potonganAbsen + potonganBpjsKesehatan + potonganBpjsTk;

  /// Belum disetel gajinya sama sekali.
  ///
  /// Dibedakan dari gaji nol supaya layarnya bisa menyebut "belum
  /// disetel" — angka nol yang tampil begitu saja terbaca sebagai
  /// hitungan yang sudah selesai dan hasilnya memang nol.
  bool get belumDisetel => gajiPokok == 0 && tunjangan == 0;

  factory BarisPayroll.fromMap(Map<String, dynamic> map) => BarisPayroll(
        email: map['employee_email']?.toString() ?? '',
        nama: map['nama']?.toString() ?? '',
        peran: map['peran']?.toString() ?? '',
        gajiPokok: (map['gaji_pokok'] as num?)?.toInt() ?? 0,
        tunjangan: (map['tunjangan'] as num?)?.toInt() ?? 0,
        hariKerja: (map['hari_kerja'] as num?)?.toInt() ?? 0,
        hadir: (map['hadir'] as num?)?.toInt() ?? 0,
        izin: (map['izin'] as num?)?.toInt() ?? 0,
        sakit: (map['sakit'] as num?)?.toInt() ?? 0,
        cuti: (map['cuti'] as num?)?.toInt() ?? 0,
        alpa: (map['alpa'] as num?)?.toInt() ?? 0,
        hariPotong: (map['hari_potong'] as num?)?.toInt() ?? 0,
        potonganAbsen: (map['potongan_absen'] as num?)?.toInt() ?? 0,
        potonganBpjsKesehatan:
            (map['potongan_bpjs_kesehatan'] as num?)?.toInt() ?? 0,
        potonganBpjsTk: (map['potongan_bpjs_tk'] as num?)?.toInt() ?? 0,
        gajiBersih: (map['gaji_bersih'] as num?)?.toInt() ?? 0,
        bankName: map['bank_name'] as String?,
        accountNumber: map['account_number'] as String?,
        accountHolder: map['account_holder'] as String?,
      );
}
