/// Bentuk potongan voucher.
enum VoucherKind { percent, amount }

/// Voucher dari KaataGo untuk pelanggan.
///
/// Berbeda dari diskon resto: diskon resto adalah promo restonya
/// sendiri, dan potongannya mengurangi pendapatan resto itu. Voucher ini
/// promo KaataGo — dipakai menarik orang memasang aplikasinya — jadi
/// yang menanggung juga KaataGo, dan dananya keluar dari saldo KaataGo
/// sebagai biaya promosi.
class Voucher {
  final String id;

  /// Kode yang diketik pelanggan. Selalu huruf besar: yang mengetiknya
  /// sedang lapar dan berdiri di depan kasir, bukan sedang teliti.
  final String code;
  final String name;

  final VoucherKind kind;
  final int value;

  /// Batas atas untuk voucher persen. Nol berarti tanpa batas.
  ///
  /// Tanpa ini, "diskon 20%" pada tagihan sejuta rupiah adalah dua ratus
  /// ribu yang keluar dari saldo KaataGo untuk satu transaksi.
  final int maxDiscount;

  final int minPurchase;

  /// Resto tempat voucher ini berlaku. Kosong berarti semua resto.
  final List<String> restoIds;

  /// Nol berarti tanpa batas.
  final int quotaTotal;
  final int quotaPerCustomer;

  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool active;
  final String? createdBy;
  final DateTime createdAt;

  /// Sudah dipakai berapa kali — hanya terisi di layar Super Admin.
  final int used;

  const Voucher({
    required this.id,
    required this.code,
    required this.name,
    this.kind = VoucherKind.percent,
    required this.value,
    this.maxDiscount = 0,
    this.minPurchase = 0,
    this.restoIds = const [],
    this.quotaTotal = 0,
    this.quotaPerCustomer = 1,
    this.startsOn,
    this.endsOn,
    this.active = true,
    this.createdBy,
    required this.createdAt,
    this.used = 0,
  });

  String get valueLabel =>
      kind == VoucherKind.percent ? '$value%' : 'Rp $value';

  bool get berlakuDiSemuaResto => restoIds.isEmpty;

  bool isLive([DateTime? now]) {
    if (!active) return false;
    final hari = now ?? DateTime.now();
    final tgl = DateTime(hari.year, hari.month, hari.day);
    if (startsOn != null && tgl.isBefore(startsOn!)) return false;
    if (endsOn != null && tgl.isAfter(endsOn!)) return false;
    return true;
  }

  /// Sisa kuota, atau null kalau tanpa batas.
  int? get sisaKuota => quotaTotal <= 0 ? null : (quotaTotal - used).clamp(0, quotaTotal);

  bool get kuotaHabis => quotaTotal > 0 && used >= quotaTotal;

  /// Potongan untuk sebuah tagihan.
  ///
  /// Dipakai layar untuk menampilkan perkiraan; yang menentukan tetap
  /// perhitungan di server. Nominal potongan yang datang dari HP bisa
  /// diubah siapa pun yang ingin membayar seribu rupiah untuk tagihan
  /// seratus ribu — dan ini uang KaataGo sendiri yang keluar.
  int amountFor(int total) {
    if (total <= 0 || total < minPurchase) return 0;
    var raw = kind == VoucherKind.percent ? total * value ~/ 100 : value;
    if (maxDiscount > 0 && raw > maxDiscount) raw = maxDiscount;
    return raw.clamp(0, total);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code.toUpperCase().trim(),
        'name': name,
        'kind': kind == VoucherKind.percent ? 'percent' : 'amount',
        'value': value,
        'max_discount': maxDiscount,
        'min_purchase': minPurchase,
        'resto_ids': restoIds,
        'quota_total': quotaTotal,
        'quota_per_customer': quotaPerCustomer,
        'starts_on': startsOn?.toIso8601String().split('T').first,
        'ends_on': endsOn?.toIso8601String().split('T').first,
        'active': active,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory Voucher.fromMap(Map<String, dynamic> map, {int used = 0}) => Voucher(
        id: map['id'] as String,
        code: map['code'] as String? ?? '',
        name: map['name'] as String? ?? 'Voucher',
        kind: map['kind'] == 'amount' ? VoucherKind.amount : VoucherKind.percent,
        value: (map['value'] as num?)?.toInt() ?? 0,
        maxDiscount: (map['max_discount'] as num?)?.toInt() ?? 0,
        minPurchase: (map['min_purchase'] as num?)?.toInt() ?? 0,
        restoIds: [
          for (final r in (map['resto_ids'] as List<dynamic>? ?? const []))
            r.toString(),
        ],
        quotaTotal: (map['quota_total'] as num?)?.toInt() ?? 0,
        quotaPerCustomer: (map['quota_per_customer'] as num?)?.toInt() ?? 1,
        startsOn: map['starts_on'] == null
            ? null
            : DateTime.parse(map['starts_on'].toString()),
        endsOn: map['ends_on'] == null
            ? null
            : DateTime.parse(map['ends_on'].toString()),
        active: map['active'] != false,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'].toString()),
        used: used,
      );

  Voucher copyWith({
    String? code,
    String? name,
    VoucherKind? kind,
    int? value,
    int? maxDiscount,
    int? minPurchase,
    List<String>? restoIds,
    int? quotaTotal,
    int? quotaPerCustomer,
    Object? startsOn = _unset,
    Object? endsOn = _unset,
    bool? active,
  }) =>
      Voucher(
        id: id,
        code: code ?? this.code,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        value: value ?? this.value,
        maxDiscount: maxDiscount ?? this.maxDiscount,
        minPurchase: minPurchase ?? this.minPurchase,
        restoIds: restoIds ?? this.restoIds,
        quotaTotal: quotaTotal ?? this.quotaTotal,
        quotaPerCustomer: quotaPerCustomer ?? this.quotaPerCustomer,
        startsOn:
            identical(startsOn, _unset) ? this.startsOn : startsOn as DateTime?,
        endsOn: identical(endsOn, _unset) ? this.endsOn : endsOn as DateTime?,
        active: active ?? this.active,
        createdBy: createdBy,
        createdAt: createdAt,
        used: used,
      );

  static const _unset = Object();
}

/// Jawaban server saat sebuah kode voucher dicoba.
///
/// Selalu membawa alasan saat ditolak. "Voucher tidak berlaku" tanpa
/// sebab membuat orang mencoba lagi dengan kode yang sama, lalu
/// menyalahkan aplikasinya.
class VoucherQuote {
  final String? voucherId;
  final String? code;
  final String? name;
  final int amount;
  final String? reason;

  const VoucherQuote({
    this.voucherId,
    this.code,
    this.name,
    this.amount = 0,
    this.reason,
  });

  bool get diterima => reason == null && amount > 0 && voucherId != null;

  factory VoucherQuote.fromMap(Map<String, dynamic> map) => VoucherQuote(
        voucherId: map['voucher_id'] as String?,
        code: map['code'] as String?,
        name: map['name'] as String?,
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        reason: map['reason'] as String?,
      );
}
