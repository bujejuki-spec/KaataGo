import 'package:supabase_flutter/supabase_flutter.dart';

/// Apa yang sedang ditampilkan layar depan sebuah resto.
enum StatusLayar { menganggur, menunggu, lunas }

/// Satu baris rincian pesanan di layar depan.
class BarisTampilan {
  final String nama;
  final int qty;
  final int total;

  const BarisTampilan(
      {required this.nama, required this.qty, required this.total});

  Map<String, dynamic> toMap() =>
      {'nama': nama, 'qty': qty, 'total': total};

  factory BarisTampilan.fromMap(Map<String, dynamic> map) => BarisTampilan(
        nama: map['nama']?.toString() ?? '',
        qty: (map['qty'] as num?)?.toInt() ?? 1,
        total: (map['total'] as num?)?.toInt() ?? 0,
      );
}

class TampilanLayar {
  final StatusLayar status;
  final int? amount;
  final String? qrString;
  final String? label;

  /// 'cash' | 'qris' | 'qris_static' | 'transfer'
  final String? paymentMethod;

  /// Rincian pesanannya. Kosong berarti tidak ada yang dirinci — layar
  /// lamanya tetap menampilkan nominal saja, tanpa ruang kosong.
  final List<BarisTampilan> items;

  final String? qrImageUrl;
  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;

  const TampilanLayar({
    this.status = StatusLayar.menganggur,
    this.amount,
    this.qrString,
    this.label,
    this.paymentMethod,
    this.items = const [],
    this.qrImageUrl,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
  });

  bool get adaQr => qrString != null && qrString!.isNotEmpty;
  bool get adaGambarQr => qrImageUrl != null && qrImageUrl!.isNotEmpty;
  bool get adaRekening =>
      accountNumber != null && accountNumber!.trim().isNotEmpty;

  factory TampilanLayar.fromMap(Map<String, dynamic> map) => TampilanLayar(
        status: switch (map['status']) {
          'awaiting' => StatusLayar.menunggu,
          'paid' => StatusLayar.lunas,
          _ => StatusLayar.menganggur,
        },
        amount: (map['amount'] as num?)?.toInt(),
        qrString: map['qr_string'] as String?,
        label: map['label'] as String?,
        paymentMethod: map['payment_method'] as String?,
        items: [
          for (final r in (map['items'] as List? ?? const []))
            BarisTampilan.fromMap(Map<String, dynamic>.from(r as Map)),
        ],
        qrImageUrl: map['qr_image_url'] as String?,
        bankName: map['bank_name'] as String?,
        accountNumber: map['account_number'] as String?,
        accountHolder: map['account_holder'] as String?,
      );
}

/// Layar pelanggan di meja kasir.
///
/// Barisnya membawa isi tampilannya, bukan penunjuk ke pesanan: di alur
/// kasir, pesanannya baru dibuat sesudah pembayaran dikonfirmasi — saat
/// QR-nya tampil, belum ada baris pesanan untuk ditunjuk.
class CustomerDisplayRepository {
  final _client = Supabase.instance.client;

  Future<void> _tulis(
    String restoId,
    String status, {
    int? amount,
    String? qrString,
    String? label,
    String? paymentMethod,
    List<BarisTampilan>? items,
    String? qrImageUrl,
    String? bankName,
    String? accountNumber,
    String? accountHolder,
  }) async {
    await _client.rpc('set_customer_display', params: {
      'p_resto_id': restoId,
      'p_status': status,
      'p_amount': amount,
      'p_qr_string': qrString,
      'p_label': label,
      'p_payment_method': paymentMethod,
      'p_items': items == null ? null : [for (final i in items) i.toMap()],
      'p_qr_image_url': qrImageUrl,
      'p_bank_name': bankName,
      'p_account_number': accountNumber,
      'p_account_holder': accountHolder,
    });
  }

  /// Menampilkan tagihan yang menunggu dibayar.
  Future<void> tampilkan(
    String restoId, {
    required int amount,
    String? qrString,
    String? label,
    String? paymentMethod,
    List<BarisTampilan>? items,
    String? qrImageUrl,
    String? bankName,
    String? accountNumber,
    String? accountHolder,
  }) =>
      _tulis(
        restoId,
        'awaiting',
        amount: amount,
        qrString: qrString,
        label: label,
        paymentMethod: paymentMethod,
        items: items,
        qrImageUrl: qrImageUrl,
        bankName: bankName,
        accountNumber: accountNumber,
        accountHolder: accountHolder,
      );

  /// Menyatakan lunas — tampil sebentar sebagai konfirmasi.
  Future<void> lunas(String restoId, {required int amount, String? label}) =>
      _tulis(restoId, 'paid', amount: amount, label: label);

  /// Mengembalikannya ke keadaan menganggur.
  ///
  /// Dipanggil saat kasir menutup layar pembayarannya. Tanpa ini,
  /// tagihan orang sebelumnya tetap terpampang di depan pelanggan
  /// berikutnya — termasuk nominalnya dan QR-nya, yang masih bisa
  /// dipindai.
  Future<void> kosongkan(String restoId) => _tulis(restoId, 'idle');

  /// Berubah seketika, tanpa perlu dimuat ulang.
  Stream<TampilanLayar> watch(String restoId) {
    return _client
        .from('customer_displays')
        .stream(primaryKey: ['resto_id'])
        .eq('resto_id', restoId)
        .map((rows) => rows.isEmpty
            ? const TampilanLayar()
            : TampilanLayar.fromMap(rows.first));
  }
}
