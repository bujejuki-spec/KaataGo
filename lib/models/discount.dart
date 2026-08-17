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

/// Bagaimana jumlah sebuah menu dibandingkan.
enum QtyMode {
  /// Minimal sekian — lebih banyak tetap dapat.
  atLeast,

  /// Tepat sekian — kurang maupun lebih tidak dapat.
  ///
  /// Dipakai promo paket yang isinya sudah pasti: "paket 2 ayam + 1 nasi"
  /// dengan tiga ayam bukan lagi paket itu, dan kalau tetap diberi
  /// potongan, harga paketnya jadi tidak berarti apa-apa.
  exactly,
}

const _qtyModeDb = {
  QtyMode.atLeast: 'at_least',
  QtyMode.exactly: 'exactly',
};

const kQtyModeLabels = {
  QtyMode.atLeast: 'Minimal',
  QtyMode.exactly: 'Tepat',
};

/// Satu menu di dalam sebuah promo, berikut syarat jumlahnya sendiri.
///
/// Syaratnya menempel di menunya, bukan di promonya. Satu angka untuk
/// seluruh promo terdengar lebih sederhana sampai dipakai: "beli 2"
/// pada promo berisi Nasi Goreng dan Es Teh akan lolos oleh keranjang
/// berisi dua Nasi Goreng saja — paket yang dijanjikan spanduknya tidak
/// pernah benar-benar dibeli, tapi potongannya tetap keluar.
class DiscountItem {
  final String productId;
  final int qty;
  final QtyMode mode;

  /// Sasaran yang lebih sempit dari seluruh menunya.
  ///
  /// Diisi kalau promonya cuma mengenai satu pilihan — "Ukuran: Besar"
  /// atau topping "Keju". Yang dipotong bukan harga menunya, melainkan
  /// tambahan harga pilihan itu saja. Dengan potongan 100%, "Ukuran
  /// Besar" jadi gratis: menunya tetap dibayar penuh, tambahannya
  /// hilang.
  final String? levelGroup;
  final String? levelOption;
  final String? toppingName;

  const DiscountItem({
    required this.productId,
    this.qty = 1,
    this.mode = QtyMode.atLeast,
    this.levelGroup,
    this.levelOption,
    this.toppingName,
  });

  /// Mengenai tambahan harga saja, bukan seluruh menunya.
  bool get targetsAddOn => levelOption != null || toppingName != null;

  /// Nama sasarannya untuk ditampilkan, atau null kalau seluruh menu.
  String? get targetLabel {
    if (toppingName != null) return 'Topping: $toppingName';
    if (levelOption != null) return '$levelGroup: $levelOption';
    return null;
  }

  /// Terpenuhi oleh [ordered] buah menu ini di keranjang.
  bool satisfiedBy(int ordered) =>
      mode == QtyMode.exactly ? ordered == qty : ordered >= qty;

  String get label =>
      mode == QtyMode.exactly ? 'tepat $qty pcs' : 'min $qty pcs';

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'qty': qty,
        'mode': _qtyModeDb[mode],
        if (levelGroup != null) 'level_group': levelGroup,
        if (levelOption != null) 'level_option': levelOption,
        if (toppingName != null) 'topping': toppingName,
      };

  factory DiscountItem.fromMap(Map<String, dynamic> map) => DiscountItem(
        productId: map['product_id'].toString(),
        qty: (map['qty'] as num?)?.toInt() ?? 1,
        mode: _qtyModeDb.entries
            .firstWhere((e) => e.value == map['mode'],
                orElse: () => _qtyModeDb.entries.first)
            .key,
        levelGroup: map['level_group'] as String?,
        levelOption: map['level_option'] as String?,
        toppingName: map['topping'] as String?,
      );

  DiscountItem copyWith({
    int? qty,
    QtyMode? mode,
    Object? levelGroup = _unset,
    Object? levelOption = _unset,
    Object? toppingName = _unset,
  }) =>
      DiscountItem(
        productId: productId,
        qty: qty ?? this.qty,
        mode: mode ?? this.mode,
        levelGroup: identical(levelGroup, _unset)
            ? this.levelGroup
            : levelGroup as String?,
        levelOption: identical(levelOption, _unset)
            ? this.levelOption
            : levelOption as String?,
        toppingName: identical(toppingName, _unset)
            ? this.toppingName
            : toppingName as String?,
      );

  static const _unset = Object();
}

/// Satu aturan diskon milik sebuah resto.
class Discount {
  final String id;
  final String restoId;
  final String name;

  final DiscountBasis basis;
  final DiscountKind kind;

  /// Persen (1–100) atau rupiah, tergantung [kind].
  final int value;

  /// Menu yang kena diskon — hanya untuk [DiscountBasis.products].
  /// Boleh lebih dari satu: itulah cara bundling dinyatakan, dan tiap
  /// menu membawa syarat jumlahnya sendiri.
  final List<DiscountItem> items;

  /// Id menunya saja. Masih ditulis ke database supaya baris ini tetap
  /// terbaca oleh versi aplikasi yang lebih lama.
  List<String> get productIds => [for (final i in items) i.productId];

  /// Ambang minimum belanja — hanya untuk [DiscountBasis.minPurchase].
  final int minPurchase;
  final MinCompare compare;

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
    this.items = const [],
    this.minPurchase = 0,
    this.compare = MinCompare.atLeast,
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
        'product_rules': [for (final i in items) i.toMap()],
        'min_purchase': minPurchase,
        'compare_mode': _compareDb[compare],
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
        items: _items(map),
        minPurchase: (map['min_purchase'] as num?)?.toInt() ?? 0,
        compare: _compareDb.entries
            .firstWhere((e) => e.value == map['compare_mode'],
                orElse: () => _compareDb.entries.first)
            .key,
        startsOn: _date(map['starts_on']),
        endsOn: _date(map['ends_on']),
        active: map['active'] != false,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  /// Menu berikut syarat jumlahnya.
  ///
  /// Baris yang ditulis versi lama tidak punya product_rules — cuma
  /// daftar id, dan mungkin satu min_qty untuk seluruh promo. Keduanya
  /// dibaca sebagai aturan per menu supaya promo lama tetap berarti
  /// persis seperti saat dibuat.
  static List<DiscountItem> _items(Map<String, dynamic> map) {
    final rules = map['product_rules'] as List<dynamic>?;
    if (rules != null && rules.isNotEmpty) {
      return [
        for (final r in rules)
          DiscountItem.fromMap(Map<String, dynamic>.from(r as Map)),
      ];
    }
    final qty = (map['min_qty'] as num?)?.toInt() ?? 1;
    return [
      for (final id in (map['product_ids'] as List<dynamic>? ?? const []))
        DiscountItem(productId: id.toString(), qty: qty),
    ];
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v.toString());

  Discount copyWith({
    String? name,
    DiscountBasis? basis,
    DiscountKind? kind,
    int? value,
    List<DiscountItem>? items,
    int? minPurchase,
    MinCompare? compare,
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
        items: items ?? this.items,
        minPurchase: minPurchase ?? this.minPurchase,
        compare: compare ?? this.compare,
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
/// [subtotalOf] mengembalikan nilai yang boleh dipotong untuk sebuah
/// sasaran: seluruh baris menunya, atau — kalau sasarannya menyempit ke
/// sebuah level/topping — tambahan harga pilihan itu saja.
///
/// [qtyOf] mengembalikan jumlah yang cocok dengan sasaran itu, nol kalau
/// tidak ada. Keduanya menerima [DiscountItem] utuh, bukan sekadar id
/// produk: sasaran yang menyempit tidak bisa dijawab hanya dari id-nya.
AppliedDiscount? bestDiscountFor({
  required List<Discount> discounts,
  required int total,
  required int Function(DiscountItem item) subtotalOf,
  required int Function(DiscountItem item) qtyOf,
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
      if (d.items.isEmpty) continue;

      // Seluruh menu yang disebut promo harus terpenuhi, bukan salah
      // satunya. Sebagian-cukup terdengar murah hati sampai dilihat apa
      // artinya: promo "Nasi Goreng + Es Teh" akan keluar untuk
      // keranjang berisi dua Nasi Goreng dan segelas kopi — paket yang
      // dijanjikan spanduknya tidak pernah benar-benar dibeli, tapi
      // restonya tetap membayar potongannya.
      final lengkap = d.items.every((i) => i.satisfiedBy(qtyOf(i)));
      if (!lengkap) continue;

      // Bundling: semua menu yang ikut promo dijumlahkan dulu, baru
      // dipotong. Memotong tiap baris sendiri-sendiri membuat diskon
      // rupiah tetap (misal "potong 10.000") terkalikan sebanyak menu
      // yang ikut.
      final dasar = d.items.fold<int>(0, (sum, i) => sum + subtotalOf(i));
      potongan = d.amountFor(dasar);
    }

    if (potongan <= 0) continue;
    if (terbaik == null || potongan > terbaik.amount) {
      terbaik = AppliedDiscount(d, potongan);
    }
  }
  return terbaik;
}
