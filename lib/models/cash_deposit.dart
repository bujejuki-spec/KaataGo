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

  /// Email yang menyetor. Kasir bertanggung jawab atas selisih laci,
  /// jadi nama ini bukan sekadar jejak audit.
  final String createdBy;

  final DateTime createdAt;

  CashDeposit({
    required this.id,
    required this.restoId,
    required this.amount,
    this.proofBase64,
    this.note,
    required this.createdBy,
    required this.createdAt,
  });

  bool get hasProof => proofBase64 != null && proofBase64!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'amount': amount,
        'proof_base64': proofBase64,
        if (note != null) 'note': note,
        'created_by': createdBy,
      };

  factory CashDeposit.fromMap(Map<String, dynamic> map) {
    return CashDeposit(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      amount: (map['amount'] as num).toInt(),
      proofBase64: map['proof_base64'] as String?,
      note: map['note'] as String?,
      createdBy: map['created_by'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
