/// Menu apa saja yang bisa diatur KaataGo Admin, per peran.
///
/// Kuncinya adalah judul menunya sendiri, apa adanya. Bukan kode
/// tersendiri — kode berarti dua nama untuk satu hal, dan yang kedua
/// selalu tertinggal saat yang pertama diganti. Judul yang diganti di
/// aplikasi memang mengembalikan menunya ke akses penuh, dan itu arah
/// yang benar untuk gagal: yang terkunci karena salah nama tidak punya
/// cara menebak apa yang terjadi.
///
/// Super Admin tidak ada di sini. Ia yang mengatur; peran yang bisa
/// mengunci dirinya sendiri dari layar pengaturannya adalah pintu yang
/// kuncinya tertinggal di dalam.
///
/// Tampilan dan Keluar juga tidak ada. Keduanya bukan pekerjaan, dan
/// menutup jalan keluar dari akun bukan pembatasan melainkan jebakan.
const katalogMenu = <String, List<String>>{
  'kasir': [
    'Absensi',
    'Shift Kasir',
    'Kasir / Input Pesanan',
    'Layar Pelanggan',
    'Pending Payment',
    'Riwayat Kasir',
    'Saldo & Pengeluaran',
    'Setor Saldo Cash',
    'Diskon',
  ],
  'admin': [
    'Absensi',
    'Absensi Karyawan',
    'Shift Kasir',
    'Kasir / Input Pesanan',
    'Layar Pelanggan',
    'Pesanan Masuk',
    'Pending Payment',
    'Riwayat Kasir',
    'Laporan Penjualan',
    'Saldo & Pengeluaran',
    'Setor Saldo Cash',
    'Tutup Buku',
    'Kelola Produk',
    'Kelola Karyawan',
    'Diskon',
    'Kirim Pengumuman',
    'Kategori',
    'Level',
    'Info Merchant',
    'QR Meja',
    'Pengaturan Pembayaran',
  ],
  'finance': [
    'Absensi',
    'Absensi Karyawan',
    'Payroll',
    'Shift Kasir',
    'Pemasukan',
    'Saldo & Pengeluaran',
    'Setor Saldo Cash',
    'Terima Cash Pickup',
    'Saldo Perusahaan',
    'Pembayaran dari KaataGo',
    'Periksa Pembukuan',
    'Tutup Buku',
    'Rekonsiliasi Bank',
    'Mapping GL Account',
    'Jurnal GL',
    'Laporan Transaksi',
    'Pencairan Gateway',
    'Tagihan Langganan',
    'Pengaturan Pembayaran',
    'Rekening Perusahaan',
  ],
  'owner': [
    'Absensi',
    'Absensi Karyawan',
    'Payroll',
    'Shift Kasir',
    'Kasir / Input Pesanan',
    'Layar Pelanggan',
    'Pesanan Masuk',
    'Layar Dapur',
    'Pending Payment',
    'Riwayat Kasir',
    'Laporan Penjualan',
    'Pemasukan',
    'Saldo & Pengeluaran',
    'Setor Saldo Cash',
    'Terima Cash Pickup',
    'Saldo Perusahaan',
    'Pembayaran dari KaataGo',
    'Periksa Pembukuan',
    'Tutup Buku',
    'Rekonsiliasi Bank',
    'Mapping GL Account',
    'Pencairan Gateway',
    'Jurnal GL',
    'Laporan Transaksi',
    'Kelola Produk',
    'Kelola Karyawan',
    'Diskon',
    'Kirim Pengumuman',
    'Tagihan Langganan',
    'Kategori',
    'Level',
    'Info Merchant',
    'QR Meja',
    'Pengaturan Pembayaran',
    'Rekening Perusahaan',
  ],
  'chef': [
    'Absensi',
    'Layar Dapur',
  ],
};

/// Nama peran yang dibaca orang.
const labelPeran = <String, String>{
  'owner': 'Owner',
  'admin': 'Admin',
  'finance': 'Finance',
  'kasir': 'Kasir',
  'chef': 'Chef',
};
