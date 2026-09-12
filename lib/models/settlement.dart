/// Tutup buku satu hari.
///
/// Angkanya dibekukan saat ditutup — alasannya sama dengan
/// `expected_cash` di tutup shift: angka yang sudah ditandatangani
/// seseorang tidak boleh berubah karena ada pesanan yang dikoreksi tiga
/// hari kemudian. Koreksi sesudahnya terlihat sebagai selisih, bukan
/// diam-diam menimpa angka lamanya.
class DailySettlement {
  final String id;
  final String restoId;
  final DateTime settledOn;

  final int cashExpected;
  final int qrisExpected;
  final int qrisStaticExpected;
  final int transferExpected;

  final int cashCounted;
  final int qrisSettled;
  final int qrisStaticSettled;
  final int transferSettled;

  final int gatewayFee;

  final String status;
  final String? note;
  final String? settledBy;
  final DateTime? settledAt;

  const DailySettlement({
    required this.id,
    required this.restoId,
    required this.settledOn,
    this.cashExpected = 0,
    this.qrisExpected = 0,
    this.qrisStaticExpected = 0,
    this.transferExpected = 0,
    this.cashCounted = 0,
    this.qrisSettled = 0,
    this.qrisStaticSettled = 0,
    this.transferSettled = 0,
    this.gatewayFee = 0,
    this.status = 'open',
    this.note,
    this.settledBy,
    this.settledAt,
  });

  bool get ditutup => status == 'settled';

  int get totalSeharusnya =>
      cashExpected + qrisExpected + qrisStaticExpected + transferExpected;

  /// Yang terbukti sampai. Biaya gateway ditambahkan kembali karena ia
  /// memang terpotong di jalan — uangnya tidak hilang, ia jadi biaya.
  /// Tanpa ini, tiap hari yang memakai QRIS Dinamis selalu terlihat
  /// kurang sebesar MDR-nya, dan selisih yang selalu ada berhenti
  /// dibaca orang.
  int get totalTerbukti =>
      cashCounted + qrisSettled + gatewayFee + qrisStaticSettled +
      transferSettled;

  int get selisih => totalTerbukti - totalSeharusnya;

  factory DailySettlement.fromMap(Map<String, dynamic> map) => DailySettlement(
        id: map['id'].toString(),
        restoId: map['resto_id'].toString(),
        settledOn: DateTime.parse(map['settled_on'].toString()),
        cashExpected: (map['cash_expected'] as num?)?.toInt() ?? 0,
        qrisExpected: (map['qris_expected'] as num?)?.toInt() ?? 0,
        qrisStaticExpected:
            (map['qris_static_expected'] as num?)?.toInt() ?? 0,
        transferExpected: (map['transfer_expected'] as num?)?.toInt() ?? 0,
        cashCounted: (map['cash_counted'] as num?)?.toInt() ?? 0,
        qrisSettled: (map['qris_settled'] as num?)?.toInt() ?? 0,
        qrisStaticSettled: (map['qris_static_settled'] as num?)?.toInt() ?? 0,
        transferSettled: (map['transfer_settled'] as num?)?.toInt() ?? 0,
        gatewayFee: (map['gateway_fee'] as num?)?.toInt() ?? 0,
        status: map['status']?.toString() ?? 'open',
        note: map['note'] as String?,
        settledBy: map['settled_by'] as String?,
        settledAt: map['settled_at'] == null
            ? null
            : DateTime.parse(map['settled_at'].toString()).toUtc(),
      );
}

/// Satu baris mutasi rekening.
class BankMutation {
  final String id;
  final String bankAccountId;
  final DateTime mutatedOn;
  final int amount;

  /// 'in' atau 'out'. Nominalnya selalu positif — angka negatif untuk
  /// uang keluar terlihat rapi di satu kolom dan menyusahkan di semua
  /// penjumlahan berikutnya.
  final String direction;

  final String? description;
  final String? reference;

  /// 'deposit' | 'order' | 'gateway' | 'other', atau null kalau belum
  /// dicocokkan. Yang null adalah pekerjaan yang menunggu.
  final String? matchedKind;
  final String? matchedId;
  final String? matchedBy;

  final String? note;
  final String? createdBy;
  final DateTime? createdAt;

  const BankMutation({
    required this.id,
    required this.bankAccountId,
    required this.mutatedOn,
    required this.amount,
    this.direction = 'in',
    this.description,
    this.reference,
    this.matchedKind,
    this.matchedId,
    this.matchedBy,
    this.note,
    this.createdBy,
    this.createdAt,
  });

  bool get masuk => direction == 'in';
  bool get sudahCocok => matchedKind != null;

  static const labelJenis = {
    'deposit': 'Setoran / Pickup',
    'order': 'Pembayaran Pelanggan',
    'gateway': 'Pencairan Gateway',
    'other': 'Bukan dari Penjualan',
  };

  factory BankMutation.fromMap(Map<String, dynamic> map) => BankMutation(
        id: map['id'].toString(),
        bankAccountId: map['bank_account_id'].toString(),
        mutatedOn: DateTime.parse(map['mutated_on'].toString()),
        amount: (map['amount'] as num).toInt(),
        direction: map['direction']?.toString() ?? 'in',
        description: map['description'] as String?,
        reference: map['reference'] as String?,
        matchedKind: map['matched_kind'] as String?,
        matchedId: map['matched_id'] as String?,
        matchedBy: map['matched_by'] as String?,
        note: map['note'] as String?,
        createdBy: map['created_by'] as String?,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'].toString()).toUtc(),
      );

  Map<String, dynamic> toMap() => {
        'bank_account_id': bankAccountId,
        'mutated_on': mutatedOn.toIso8601String().substring(0, 10),
        'amount': amount,
        'direction': direction,
        if (description != null) 'description': description,
        if (reference != null && reference!.trim().isNotEmpty)
          'reference': reference!.trim(),
        if (note != null) 'note': note,
        if (createdBy != null) 'created_by': createdBy,
      };
}

/// Setoran atau pembayaran yang belum punya mutasinya.
///
/// Inilah sisi yang mahal: uang yang keluar laci dan tidak pernah sampai
/// ke bank, atau pembayaran yang diakui lunas tapi uangnya tidak ada.
class BelumCocok {
  final String id;
  final int amount;

  /// Untuk setoran: 'setor' atau 'pickup'.
  /// Untuk pembayaran: 'qris_static' atau 'transfer'.
  final String jenis;

  final DateTime waktu;
  final String? oleh;

  const BelumCocok({
    required this.id,
    required this.amount,
    required this.jenis,
    required this.waktu,
    this.oleh,
  });
}
