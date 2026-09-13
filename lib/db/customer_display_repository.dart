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

/// Dari mana totalnya berasal.
///
/// Baris pesanan di layar depan sudah membawa harga menunya berikut PPN
/// yang menempel di harga itu — jadi yang disebut di sini bukan ulangan
/// melainkan yang TIDAK terlihat di baris mana pun: service yang
/// ditambahkan per tagihan, dan potongan yang dikurangkan dari totalnya.
class RincianBiaya {
  /// Jumlah harga menunya seperti yang tertulis di daftar — sudah
  /// termasuk PPN, persis seperti yang dijumlahkan pelanggan sendiri
  /// dari baris-baris pesanannya.
  ///
  /// Bukan nilai sebelum pajak. Yang sebelum pajak tidak pernah dilihat
  /// pelanggan di mana pun, dan menaruhnya di baris "Subtotal" membuat
  /// tidak satu pun angka di layar ini bisa dijumlahkan ke bawah.
  final int subtotal;
  final int service;
  final int ppn;
  final int discount;
  final String? discountName;

  /// Tarif PPN-nya, bukan cuma nominalnya.
  ///
  /// Dipakai menulis "Harga sudah termasuk PPN 11%" — kalimat yang
  /// menjelaskan kenapa PPN tidak muncul sebagai baris tambahan, dan
  /// tanpanya pelanggan menyimpulkan pajaknya memang tidak ditagihkan.
  final double ppnPercent;

  final double servicePercent;

  const RincianBiaya({
    this.subtotal = 0,
    this.service = 0,
    this.ppn = 0,
    this.discount = 0,
    this.discountName,
    this.ppnPercent = 0,
    this.servicePercent = 0,
  });

  /// Tidak ada yang perlu dirinci: totalnya memang persis jumlah
  /// barisnya. Daftar rincian berisi satu baris yang mengulang angka di
  /// atasnya cuma menambah yang harus dibaca.
  bool get kosong => service == 0 && ppn == 0 && discount == 0;

  /// Yang perlu diuraikan baris per baris. PPN tidak termasuk: ia sudah
  /// menempel di harga tiap menu, dan menyebutnya lagi sebagai baris
  /// tersendiri berarti menjumlahkannya dua kali di mata pembacanya.
  bool get adaBaris => service > 0 || discount > 0;

  Map<String, dynamic> toMap() => {
        'subtotal': subtotal,
        'service': service,
        'ppn': ppn,
        'discount': discount,
        'discount_name': discountName,
        'ppn_percent': ppnPercent,
        'service_percent': servicePercent,
      };

  factory RincianBiaya.fromMap(Map<String, dynamic> map) => RincianBiaya(
        subtotal: (map['subtotal'] as num?)?.toInt() ?? 0,
        service: (map['service'] as num?)?.toInt() ?? 0,
        ppn: (map['ppn'] as num?)?.toInt() ?? 0,
        discount: (map['discount'] as num?)?.toInt() ?? 0,
        discountName: map['discount_name'] as String?,
        ppnPercent: (map['ppn_percent'] as num?)?.toDouble() ?? 0,
        servicePercent: (map['service_percent'] as num?)?.toDouble() ?? 0,
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

  /// Null berarti tidak ada biaya tambahan maupun potongan.
  final RincianBiaya? rincian;

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
    this.rincian,
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
        rincian: map['breakdown'] == null
            ? null
            : RincianBiaya.fromMap(
                Map<String, dynamic>.from(map['breakdown'] as Map)),
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
    RincianBiaya? rincian,
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
      'p_breakdown': rincian?.toMap(),
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
    RincianBiaya? rincian,
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
        rincian: rincian,
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
