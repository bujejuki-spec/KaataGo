/// Ringkasan penjualan satu merchant dalam sebuah rentang tanggal.
class RingkasanPenjualan {
  final int jumlahPesanan;
  final int omzet;
  final int rataTransaksi;
  final int menuTerjual;

  const RingkasanPenjualan({
    this.jumlahPesanan = 0,
    this.omzet = 0,
    this.rataTransaksi = 0,
    this.menuTerjual = 0,
  });

  bool get kosong => jumlahPesanan == 0;

  factory RingkasanPenjualan.fromMap(Map<String, dynamic> map) =>
      RingkasanPenjualan(
        jumlahPesanan: (map['orders_count'] as num?)?.toInt() ?? 0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
        rataTransaksi: (map['rata_transaksi'] as num?)?.toInt() ?? 0,
        menuTerjual: (map['menu_terjual'] as num?)?.toInt() ?? 0,
      );
}

/// Satu baris peringkat menu.
class PenjualanMenu {
  final String productId;

  /// Nama saat dipesan, bukan nama sekarang. Menu yang sudah dihapus
  /// tetap punya sejarah penjualan.
  final String nama;

  final int qty;
  final int omzet;

  const PenjualanMenu({
    required this.productId,
    required this.nama,
    required this.qty,
    required this.omzet,
  });

  factory PenjualanMenu.fromMap(Map<String, dynamic> map) => PenjualanMenu(
        productId: map['product_id']?.toString() ?? '',
        nama: map['product_name']?.toString() ?? 'Menu sudah dihapus',
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
      );
}

/// Menu yang tidak terjual sama sekali sepanjang rentangnya.
class MenuTidakLaku {
  final String productId;
  final String nama;
  final String kategori;
  final int harga;

  const MenuTidakLaku({
    required this.productId,
    required this.nama,
    required this.kategori,
    required this.harga,
  });

  factory MenuTidakLaku.fromMap(Map<String, dynamic> map) => MenuTidakLaku(
        productId: map['product_id']?.toString() ?? '',
        nama: map['product_name']?.toString() ?? '',
        kategori: map['category']?.toString() ?? '',
        harga: (map['price'] as num?)?.toInt() ?? 0,
      );
}

/// Satu jam dalam sehari, berikut ramainya.
class JamRamai {
  final int jam;
  final int jumlahPesanan;
  final int omzet;

  const JamRamai({
    required this.jam,
    required this.jumlahPesanan,
    required this.omzet,
  });

  /// "14:00"
  String get label => '${jam.toString().padLeft(2, '0')}:00';

  factory JamRamai.fromMap(Map<String, dynamic> map) => JamRamai(
        jam: (map['jam'] as num?)?.toInt() ?? 0,
        jumlahPesanan: (map['orders_count'] as num?)?.toInt() ?? 0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
      );
}

/// Satu titik pada deret waktu penjualan.
///
/// Titik yang nol tetap ada. Grafik yang cuma menggambar hari-hari yang
/// punya penjualan menyambung Senin langsung ke Rabu dengan garis yang
/// naik mulus — dan hari Selasa yang tutup total terbaca sebagai hari
/// biasa.
class TitikPenjualan {
  final DateTime periode;
  final int jumlahPesanan;
  final int omzet;
  final int porsi;

  const TitikPenjualan({
    required this.periode,
    required this.jumlahPesanan,
    required this.omzet,
    required this.porsi,
  });

  factory TitikPenjualan.fromMap(Map<String, dynamic> map) => TitikPenjualan(
        periode: DateTime.parse(map['periode'].toString()),
        jumlahPesanan: (map['orders_count'] as num?)?.toInt() ?? 0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
        porsi: (map['qty'] as num?)?.toInt() ?? 0,
      );
}

/// Satu potong pembagian omzet — cara bayar, jenis pesanan, asal
/// pesanan, kasir, atau kategori menu.
class PotongPenjualan {
  final String kunci;
  final int jumlahPesanan;
  final int omzet;

  const PotongPenjualan({
    required this.kunci,
    required this.jumlahPesanan,
    required this.omzet,
  });

  factory PotongPenjualan.fromMap(Map<String, dynamic> map) => PotongPenjualan(
        kunci: map['kunci']?.toString() ?? 'lainnya',
        // Pembagian per kategori menghitung baris menu, bukan pesanan —
        // jadi kolomnya `qty`, bukan `orders_count`.
        jumlahPesanan: (map['orders_count'] as num?)?.toInt() ??
            (map['qty'] as num?)?.toInt() ??
            0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
      );
}
