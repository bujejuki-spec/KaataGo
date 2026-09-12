/// Setoran dari uang tunai perusahaan ke rekeningnya sendiri.
///
/// Berbeda dari `CashDeposit`, yang memindahkan uang dari LACI KASIR.
/// Yang di sini sudah lama meninggalkan laci — ia masuk lewat serah
/// terima cash pickup — jadi kalau dicatat di tabel yang sama, isi laci
/// kasir akan dikurangi untuk kedua kalinya oleh uang yang tidak pernah
/// menyentuhnya.
class CompanyDeposit {
  final String id;
  final String restoId;
  final int amount;

  /// Rekening tujuannya, kalau disebut. Merchant yang punya beberapa
  /// rekening perlu tahu uangnya mendarat di mana saat mencocokkan
  /// mutasi.
  final String? bankAccountId;

  final String? note;
  final String? proofBase64;
  final String? createdBy;
  final DateTime createdAt;

  const CompanyDeposit({
    required this.id,
    required this.restoId,
    required this.amount,
    this.bankAccountId,
    this.note,
    this.proofBase64,
    this.createdBy,
    required this.createdAt,
  });

  bool get adaBukti => proofBase64 != null && proofBase64!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'amount': amount,
        if (bankAccountId != null) 'bank_account_id': bankAccountId,
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
        if (proofBase64 != null) 'proof_base64': proofBase64,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory CompanyDeposit.fromMap(Map<String, dynamic> map) => CompanyDeposit(
        id: map['id'].toString(),
        restoId: map['resto_id'].toString(),
        amount: (map['amount'] as num).toInt(),
        bankAccountId: map['bank_account_id']?.toString(),
        note: map['note'] as String?,
        proofBase64: map['proof_base64'] as String?,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'].toString()).toUtc(),
      );
}
