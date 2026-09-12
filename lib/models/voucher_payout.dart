/// Pembayaran KaataGo ke merchant atas voucher yang ditebus di sana.
///
/// Pelanggan menebus voucher KaataGo di sebuah resto: restonya
/// menyerahkan makanan dan menerima nol rupiah dari pelanggan, jadi
/// KaataGo yang menggantinya. Baris ini adalah janji itu — dan kalau
/// statusnya belum 'sent', uangnya memang belum berpindah.
class VoucherPayout {
  final String id;
  final String restoId;
  final String claimId;
  final String? orderId;
  final int amount;

  /// 'pending' — antre dibayar
  /// 'sent'    — sudah dikirim ke sub-akun restonya
  /// 'failed'  — gagal, dan akan dicoba lagi
  final String status;

  /// Nomor transfer dari penyedia pembayaran, supaya barisnya bisa
  /// dicocokkan dengan mutasi tanpa menebak.
  final String? transferId;

  /// Alasan gagalnya, apa adanya dari penyedia.
  final String? lastError;
  final int attempts;

  final DateTime createdAt;
  final DateTime? sentAt;

  const VoucherPayout({
    required this.id,
    required this.restoId,
    required this.claimId,
    this.orderId,
    required this.amount,
    this.status = 'pending',
    this.transferId,
    this.lastError,
    this.attempts = 0,
    required this.createdAt,
    this.sentAt,
  });

  bool get terkirim => status == 'sent';
  bool get gagal => status == 'failed';

  /// Yang belum sampai ke merchant: antre maupun gagal. Keduanya sama
  /// saja dari sisi merchant — uangnya belum ada.
  bool get belumSampai => !terkirim;

  String get labelStatus => switch (status) {
        'sent' => 'Sudah dibayar',
        'failed' => 'Gagal, akan diulang',
        _ => 'Menunggu dibayar',
      };

  factory VoucherPayout.fromMap(Map<String, dynamic> map) => VoucherPayout(
        id: map['id'].toString(),
        restoId: map['resto_id'].toString(),
        claimId: map['claim_id'].toString(),
        orderId: map['order_id']?.toString(),
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        status: map['status']?.toString() ?? 'pending',
        transferId: map['transfer_id'] as String?,
        lastError: map['last_error'] as String?,
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(map['created_at'].toString()).toUtc(),
        sentAt: map['sent_at'] == null
            ? null
            : DateTime.parse(map['sent_at'].toString()).toUtc(),
      );
}
