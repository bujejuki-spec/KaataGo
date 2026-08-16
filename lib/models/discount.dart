import '../utils/promo_period.dart';

/// Dasar perhitungan diskon.
enum DiscountBasis {
  /// Menu tertentu — satu atau beberapa sekaligus, untuk kasus bundling.
  products,

  /// Seluruh tagihan, asal mencapai nilai minimum.
  minPurchase,
}

/// Bentuk potongannya.
enum DiscountKind { percent, amount }

/// Bagaimana nilai minimum dibandingkan.
///
/// Dipisah dan bisa dipilih karena keduanya benar-benar berbeda di
/// telinga pelanggan: "belanja 200 ribu dapat diskon" hampir selalu
/// dimaksudkan termasuk yang pas 200 ribu, tapi tidak selalu. Menebak
/// salah satunya berarti ada transaksi di batas persis yang ditolak
/// kasirnya sementara spanduknya menjanjikan sebaliknya.
enum MinCompare {
  /// ≥ — yang pas nilainya ikut dapat.
  atLeast,

  /// > — harus melebihi.
  moreThan,
}

const _basisDb = {
  DiscountBasis.products: 'products',
  DiscountBasis.minPurchase: 'min_purchase',
};

const _kindDb = {
  DiscountKind.percent: 'percent',
  DiscountKind.amount: 'amount',
};

const _compareDb = {
  MinCompare.atLeast: 'at_least',
  MinCompare.moreThan: 'more_than',
};

const kDiscountBasisLabels = {
  DiscountBasis.products: 'Menu tertentu',
  DiscountBasis.minPurchase: 'Minimum belanja',
};

const kMinCompareLabels = {
  MinCompare.atLeast: '≥ (termasuk nilainya)',
  MinCompare.moreThan: '> (harus lebih dari)',
};

/// Satu aturan diskon milik sebuah resto.
class Discount {
  final String id;
  final String restoId;
  final String name;

  final DiscountBasis basis;
  final DiscountKind kind;

  /// Persen (1–100) atau rupiah, tergantung [kind].
  final int value;

  /// Id menu yang kena diskon — hanya untuk [DiscountBasis.products].
  /// Boleh lebih dari satu: itulah cara bundling dinyatakan.
  final List<String> productIds;

  /// Ambang minimum belanja — hanya untuk [DiscountBasis.minPurchase].
  final int minPurchase;
  final MinCompare compare;

  /// Berapa banyak menunya harus dipesan supaya promonya berlaku.
  ///
  /// "Beli 2 Mont Blanc diskon 30%" — tanpa ini, promo yang dimaksud
  /// untuk pembelian kedua ikut terpakai oleh yang membeli satu, dan
  /// alasan promonya ada (mendorong orang menambah satu lagi) hilang.
  ///
  /// Dihitung per menu, bukan per keranjang: pada bundling, tiap menu
  /// yang ikut harus mencapai jumlah ini sendiri. Dua Mont Blanc tidak
  /// menutupi Nasi Goreng yang tidak dipesan.
  ///
  /// Bawaannya 1 — promo lama yang tidak menyebut jumlah tetap berlaku
  /// persis seperti sebelumnya.
  final int minQty;

  final DateTime? startsOn;
  final DateTime? endsOn;

  final bool active;
  final String? createdBy;
  final DateTime createdAt;

  const Discount({
    required this.id,
    required this.restoId,
    required this.name,
    required this.basis,
    required this.kind,
    required this.value,
    this.productIds = const [],
    this.minPurchase = 0,
    this.compare = MinCompare.atLeast,
    this.minQty = 1,
    this.startsOn,
    this.endsOn,
    this.active = true,
    this.createdBy,
    required this.createdAt,
  });

  PromoPeriod get period => PromoPeriod(startsOn: startsOn, endsOn: endsOn);

  /// Berlaku hari ini dan tidak dimatikan.
  bool isLive([DateTime? now]) => active && period.isLive(now);

  /// Potongan untuk sebuah nilai dasar.
  ///
  /// Dibulatkan ke bawah, dan tidak pernah melebihi dasarnya sendiri.
  /// Diskon yang lebih besar daripada tagihannya menghasilkan total
  /// negatif — uang yang harus dikembalikan resto kepada orang yang
  /// belum membayar apa pun.
  int amountFor(int base) {
    if (base <= 0) return 0;
    final raw = kind == DiscountKind.percent ? base * value ~/ 100 : value;
    return raw.clamp(0, base);
  }

  /// Ambang minimumnya terpenuhi.
  bool meetsMinimum(int total) => compare == MinCompare.atLeast
      ? total >= minPurchase
      : total > minPurchase;

  String get valueLabel =>
      kind == DiscountKind.percent ? '$value%' : 'Rp $value';

  Map<String, dynamic> toMap() => {
        'id': id,
        'resto_id': restoId,
        'name': name,
        'basis': _basisDb[basis],
        'kind': _kindDb[kind],
        'value': value,
        'product_ids': productIds,
        'min_purchase': minPurchase,
        'compare_mode': _compareDb[compare],
        'min_qty': minQty,
        'starts_on': startsOn?.toIso8601String().split('T').first,
        'ends_on': endsOn?.toIso8601String().split('T').first,
        'active': active,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory Discount.fromMap(Map<String, dynamic> map) => Discount(
        id: map['id'] as String,
        restoId: map['resto_id'] as String,
        name: map['name'] as String? ?? 'Diskon',
        basis: _basisDb.entries
            .firstWhere((e) => e.value == map['basis'],
                orElse: () => _basisDb.entries.first)
            .key,
        kind: _kindDb.entries
            .firstWhere((e) => e.value == map['kind'],
                orElse: () => _kindDb.entries.first)
            .key,
        value: (map['value'] as num?)?.toInt() ?? 0,
        productIds: [
          for (final id in (map['product_ids'] as List<dynamic>? ?? const []))
            id.toString(),
        ],
        minPurchase: (map['min_purchase'] as num?)?.toInt() ?? 0,
        compare: _compareDb.entries
            .firstWhere((e) => e.value == map['compare_mode'],
                orElse: () => _compareDb.entries.first)
            .key,
        minQty: (map['min_qty'] as num?)?.toInt() ?? 1,
        startsOn: _date(map['starts_on']),
        endsOn: _date(map['ends_on']),
        active: map['active'] != false,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v.toString());

  Discount copyWith({
    String? name,
    DiscountBasis? basis,
    DiscountKind? kind,
    int? value,
    List<String>? productIds,
    int? minPurchase,
    MinCompare? compare,
    int? minQty,
    Object? startsOn = _unset,
    Object? endsOn = _unset,
    bool? active,
  }) =>
      Discount(
        id: id,
        restoId: restoId,
        name: name ?? this.name,
        basis: basis ?? this.basis,
        kind: kind ?? this.kind,
        value: value ?? this.value,
        productIds: productIds ?? this.productIds,
        minPurchase: minPurchase ?? this.minPurchase,
        compare: compare ?? this.compare,
        minQty: minQty ?? this.minQty,
        startsOn:
            identical(startsOn, _unset) ? this.startsOn : startsOn as DateTime?,
        endsOn: identical(endsOn, _unset) ? this.endsOn : endsOn as DateTime?,
        active: active ?? this.active,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  static const _unset = Object();
}

/// Diskon terpilih untuk sebuah tagihan, berikut potongannya.
class AppliedDiscount {
  final Discount discount;
  final int amount;

  const AppliedDiscount(this.discount, this.amount);
}

/// Memilih diskon terbaik untuk sebuah tagihan.
///
/// Satu diskon, bukan ditumpuk semuanya. Menumpuk terdengar murah hati
/// sampai ada dua promo yang kebetulan berlaku bersamaan dan totalnya
/// melebihi harga barangnya — dan yang menemukan itu lebih dulu selalu
/// bukan restonya.
///
/// [subtotalOf] mengembalikan nilai baris untuk sebuah produk; dipakai
/// diskon berbasis menu supaya potongannya hanya mengenai menu yang
/// memang ikut promo, bukan seluruh tagihan.
///
/// [qtyOf] mengembalikan jumlah menu itu di keranjang — dipakai promo
/// yang mensyaratkan pembelian lebih dari satu.
AppliedDiscount? bestDiscountFor({
  required List<Discount> discounts,
  required int total,
  required int Function(String productId) subtotalOf,
  required int Function(String productId) qtyOf,
  required Iterable<String> productIds,
  DateTime? now,
}) {
  AppliedDiscount? terbaik;

  for (final d in discounts) {
    if (!d.isLive(now)) continue;

    int potongan;
    if (d.basis == DiscountBasis.minPurchase) {
      if (!d.meetsMinimum(total)) continue;
      potongan = d.amountFor(total);
    } else {
      // Jumlahnya diperiksa per menu. Promo "beli 2" yang lolos karena
      // keranjangnya kebetulan berisi dua menu berbeda bukan promo yang
      // dijanjikan spanduknya.
      final kena = productIds
          .where((id) => d.productIds.contains(id) && qtyOf(id) >= d.minQty);
      if (kena.isEmpty) continue;
      // Bundling: semua menu yang ikut promo dijumlahkan dulu, baru
      // dipotong. Memotong tiap baris sendiri-sendiri membuat diskon
      // rupiah tetap (misal "potong 10.000") terkalikan sebanyak menu
      // yang ikut.
      final dasar = kena.fold<int>(0, (sum, id) => sum + subtotalOf(id));
      potongan = d.amountFor(dasar);
    }

    if (potongan <= 0) continue;
    if (terbaik == null || potongan > terbaik.amount) {
      terbaik = AppliedDiscount(d, potongan);
    }
  }
  return terbaik;
}
