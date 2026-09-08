/// Metode pembayaran yang dikenal aplikasi ini.
///
/// Satu tempat, dipakai kasir, layar pelanggan, pemetaan GL, dan struk.
/// Sebelumnya daftarnya ditulis ulang di tiap layar sebagai literal
/// `'cash'`, `'qris'`, `'transfer'` — dan tiap penambahan metode berarti
/// mencarinya satu per satu, dengan yang terlewat muncul sebagai metode
/// yang bisa dipilih tapi tidak pernah terjurnal.
enum MetodeBayar {
  /// Uangnya masuk laci kasir.
  tunai('cash', 'Tunai'),

  /// QRIS lewat penyedia pembayaran. Uangnya menginap di sana dulu,
  /// dicairkan menyusul dikurangi biayanya.
  ///
  /// Kodenya tetap `qris` — nilai itu tersebar di ribuan baris pesanan,
  /// jurnal, dan pencairan. Yang berubah cuma namanya, sejak QRIS Statis
  /// ada dan keduanya perlu dibedakan saat dibaca orang.
  qrisDinamis('qris', 'QRIS Dinamis'),

  /// QR cetak milik merchant sendiri. Uangnya mendarat langsung di
  /// rekening merchant tanpa melewati penyedia pembayaran — jadi tidak
  /// pernah muncul di pencairan gateway, dan akun GL-nya terpisah.
  qrisStatis('qris_static', 'QRIS Statis'),

  /// Transfer bank manual.
  transfer('transfer', 'Transfer');

  final String kode;
  final String label;

  const MetodeBayar(this.kode, this.label);

  static MetodeBayar? dariKode(String? kode) {
    for (final m in MetodeBayar.values) {
      if (m.kode == kode) return m;
    }
    return null;
  }

  /// Label yang layak dibaca orang, termasuk untuk kode lama yang tidak
  /// dikenal lagi. Struk lama tidak boleh berubah jadi kosong hanya
  /// karena kodenya sudah tidak dipakai.
  static String labelDari(String? kode) =>
      dariKode(kode)?.label ?? (kode ?? '-');

  /// Kedua rupa QRIS. Dipakai layar yang memperlakukan keduanya sama —
  /// misalnya menghitung pemasukan non-tunai.
  bool get adalahQris =>
      this == MetodeBayar.qrisDinamis || this == MetodeBayar.qrisStatis;
}

/// Metode yang ditawarkan sebuah merchant, berikut QR statisnya.
class MetodeBayarMerchant {
  final bool tunai;
  final bool qrisDinamis;
  final bool qrisStatis;
  final bool transfer;

  /// Tautan gambar QR statis di Storage. Null berarti belum diunggah —
  /// dan selama null, [qrisStatis] tidak boleh menyala.
  final String? qrisStatisUrl;

  /// Isi payload QR-nya, hasil pemindaian saat diunggah.
  final String? qrisStatisPayload;

  const MetodeBayarMerchant({
    this.tunai = true,
    this.qrisDinamis = true,
    this.qrisStatis = false,
    this.transfer = true,
    this.qrisStatisUrl,
    this.qrisStatisPayload,
  });

  factory MetodeBayarMerchant.fromMap(Map<String, dynamic> map) =>
      MetodeBayarMerchant(
        // Baris lama tidak punya kolomnya sama sekali. Yang tidak ada
        // dianggap menyala — merchant yang sudah berjualan tidak boleh
        // kehilangan metode bayarnya hanya karena aplikasinya diperbarui.
        tunai: map['allow_cash'] as bool? ?? true,
        qrisDinamis: map['allow_qris'] as bool? ?? true,
        qrisStatis: map['allow_qris_static'] as bool? ?? false,
        transfer: map['allow_transfer'] as bool? ?? true,
        qrisStatisUrl: map['qris_static_url'] as String?,
        qrisStatisPayload: map['qris_static_payload'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'allow_cash': tunai,
        'allow_qris': qrisDinamis,
        'allow_qris_static': qrisStatis,
        'allow_transfer': transfer,
        'qris_static_url': qrisStatisUrl,
        'qris_static_payload': qrisStatisPayload,
      };

  bool aktif(MetodeBayar m) => switch (m) {
        MetodeBayar.tunai => tunai,
        MetodeBayar.qrisDinamis => qrisDinamis,
        MetodeBayar.qrisStatis => qrisStatis && qrisStatisUrl != null,
        MetodeBayar.transfer => transfer,
      };

  List<MetodeBayar> get yangAktif =>
      [for (final m in MetodeBayar.values) if (aktif(m)) m];

  MetodeBayarMerchant copyWith({
    bool? tunai,
    bool? qrisDinamis,
    bool? qrisStatis,
    bool? transfer,
    String? qrisStatisUrl,
    String? qrisStatisPayload,
    bool hapusQrisStatis = false,
  }) =>
      MetodeBayarMerchant(
        tunai: tunai ?? this.tunai,
        qrisDinamis: qrisDinamis ?? this.qrisDinamis,
        // QR-nya dibuang berarti metodenya ikut mati. Menyisakan
        // saklarnya menyala tanpa gambar membuat pelanggan memilih
        // metode yang layarnya kosong.
        qrisStatis: hapusQrisStatis ? false : (qrisStatis ?? this.qrisStatis),
        transfer: transfer ?? this.transfer,
        qrisStatisUrl:
            hapusQrisStatis ? null : (qrisStatisUrl ?? this.qrisStatisUrl),
        qrisStatisPayload: hapusQrisStatis
            ? null
            : (qrisStatisPayload ?? this.qrisStatisPayload),
      );
}
