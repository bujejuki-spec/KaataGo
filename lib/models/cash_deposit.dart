/// Tahap persetujuan sebuah setoran.
///
/// Saat kasir menekan simpan, yang terjadi baru "klaim sudah disetor" —
/// belum ada yang memeriksa buktinya. Karena itu uangnya berhenti dulu di
/// GL Suspense, bukan langsung diakui masuk kas resto.
enum DepositStatus { pending, approved, rejected }

const _statusDbValues = {
  DepositStatus.pending: 'pending',
  DepositStatus.approved: 'approved',
  DepositStatus.rejected: 'rejected',
};

/// Yang dilakukan Finance bukan menyetujui permintaan, melainkan
/// memastikan uangnya benar-benar sudah masuk rekening — karena itu
/// istilahnya "konfirmasi", dan hasilnya "Completed", bukan "Disetujui".
const kDepositStatusLabels = {
  DepositStatus.pending: 'Pending',
  DepositStatus.approved: 'Completed',
  DepositStatus.rejected: 'Ditolak',
};

extension DepositStatusDb on DepositStatus {
  String get dbValue => _statusDbValues[this]!;

  static DepositStatus fromDb(String? value) => _statusDbValues.entries
      .firstWhere((e) => e.value == value,
          orElse: () => const MapEntry(DepositStatus.pending, 'pending'))
      .key;
}

/// Uang tunai dari laci kasir yang disetorkan ke rekening resto.
///
/// Ini pemindahan, bukan pengeluaran: Saldo Cash berkurang dan GL Total
/// Saldo bertambah dengan jumlah yang sama, jadi saldo total resto tidak
/// berubah karenanya.
class CashDeposit {
  final String id;
  final String restoId;
  final int amount;

  /// Foto bukti setor/transfer sebagai base64. Boleh kosong — ada resto
  /// yang menyetor langsung ke pemilik tanpa slip, dan memaksakan bukti
  /// hanya akan membuat setoran tidak dicatat sama sekali.
  final String? proofBase64;

  final String? note;

  /// Rekening tujuan. Tanpa ini, "sudah disetor" tidak menyebut ke mana —
  /// dan saat Finance mencocokkan dengan mutasi bank, tidak ada yang bisa
  /// dipakai selain nominalnya.
  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;

  /// Rekening tujuannya, sejak rekening punya keberadaan sendiri.
  ///
  /// Null untuk baris lama: menebak setoran tahun lalu masuk ke rekening
  /// mana berarti membuat data yang terlihat pasti padahal karangan.
  final String? bankAccountId;

  /// 'setor' — kasir menyetorkan sendiri ke bank.
  /// 'pickup' — uangnya dijemput petugas penjemputan.
  ///
  /// Keduanya satu tabel karena yang terjadi pada uangnya sama persis:
  /// lembarannya keluar dari laci, dan Saldo Cash sudah tahu cara
  /// menghitung itu. Tabel terpisah berarti Saldo Cash harus diajari
  /// sumber kedua — dan selama belum diajari, uang yang sudah dibawa
  /// pergi masih dihitung ada di laci.
  final String method;

  /// Siapa yang menjemput uangnya. Hanya untuk pickup, dan wajib di
  /// sana: uang yang keluar laci tanpa nama penerima adalah uang yang
  /// tidak bisa ditanyakan ke siapa pun besok pagi.
  final String? pickedUpBy;

  /// Nomor segel kantong uangnya. Opsional — sebagian jasa penjemputan
  /// memakainya, sebagian tidak.
  final String? sealNumber;

  bool get isPickup => method == 'pickup';

  /// Email yang menyetor. Kasir bertanggung jawab atas selisih laci,
  /// jadi nama ini bukan sekadar jejak audit.
  final String createdBy;

  final DateTime createdAt;

  final DepositStatus status;

  /// Email Finance/Admin yang menyetujui atau menolak, beserta waktunya.
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;

  CashDeposit({
    required this.id,
    required this.restoId,
    required this.amount,
    this.proofBase64,
    this.note,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
    this.bankAccountId,
    this.method = 'setor',
    this.pickedUpBy,
    this.sealNumber,
    required this.createdBy,
    required this.createdAt,
    this.status = DepositStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
  });

  bool get isPending => status == DepositStatus.pending;
  bool get isApproved => status == DepositStatus.approved;

  bool get hasProof => proofBase64 != null && proofBase64!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'amount': amount,
        'proof_base64': proofBase64,
        if (note != null) 'note': note,
        if (bankName != null) 'bank_name': bankName,
        if (accountNumber != null) 'account_number': accountNumber,
        if (accountHolder != null) 'account_holder': accountHolder,
        if (bankAccountId != null) 'bank_account_id': bankAccountId,
        'method': method,
        if (pickedUpBy != null) 'picked_up_by': pickedUpBy,
        if (sealNumber != null) 'seal_number': sealNumber,
        'created_by': createdBy,
      };

  factory CashDeposit.fromMap(Map<String, dynamic> map) {
    return CashDeposit(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      amount: (map['amount'] as num).toInt(),
      proofBase64: map['proof_base64'] as String?,
      note: map['note'] as String?,
      bankName: map['bank_name'] as String?,
      accountNumber: map['account_number'] as String?,
      accountHolder: map['account_holder'] as String?,
      bankAccountId: map['bank_account_id']?.toString(),
      method: map['method'] as String? ?? 'setor',
      pickedUpBy: map['picked_up_by'] as String?,
      sealNumber: map['seal_number'] as String?,
      createdBy: map['created_by'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      status: DepositStatusDb.fromDb(map['status'] as String?),
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] == null
          ? null
          : DateTime.parse(map['reviewed_at'] as String).toUtc(),
      reviewNote: map['review_note'] as String?,
    );
  }
}
