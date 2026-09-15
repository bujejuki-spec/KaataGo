import 'faq_screen.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/setelan_platform_repository.dart';
import '../theme.dart';
import '../widgets/kaata_logo.dart';

/// "Tentang KaataGo" — what the app is and what each role can do with
/// it. Reached from the small info icon on the role-choice screen, so
/// someone handed the app for the first time can work out what it's for
/// without having to log in as anything.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = 'Versi ${info.version} (${info.buildNumber})');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Tentang KaataGo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                const KaataLogo(size: 72),
                const SizedBox(height: 14),
                const Text(
                  'KaataGo',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: KaataTheme.brandDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Order Cepat, Merchant Hebat',
                  style: TextStyle(
                    color: KaataTheme.brand,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (_version.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_version,
                      style: TextStyle(color: KaataTheme.mutedOf(context), fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _WebsiteLink(),
          const SizedBox(height: 14),
          _Section(
            title: 'Apa itu KaataGo?',
            child: Text(
              'KaataGo adalah aplikasi kasir sekaligus pemesanan mandiri untuk '
              'restoran, kafe, dan warung. Satu aplikasi dipakai bersama oleh '
              'pemilik, karyawan, dan pelanggan — masing-masing masuk dengan '
              'akun sendiri dan langsung diarahkan ke tampilan sesuai perannya.\n\n'
              'Pelanggan bisa memesan sendiri dari mejanya dengan scan QR, '
              'kasir tetap bisa melayani pesanan langsung, dapur melihat semua '
              'pesanan masuk secara real-time, dan bagian keuangan mendapat '
              'catatan yang rapi dari setiap transaksi tanpa input ulang.',
              style: TextStyle(fontSize: 13.5, height: 1.55, color: KaataTheme.mutedOf(context)),
            ),
          ),
          const SizedBox(height: 14),
          const _Section(
            title: 'Untuk Pelanggan',
            child: _Features([
              (Icons.qr_code_scanner, 'Scan QR di meja', 'Langsung lihat menu merchant tanpa install apa pun'),
              (Icons.storefront_outlined, 'Pilih merchant', 'Pesan dari daftar merchant walau tidak sedang di tempat'),
              (Icons.restaurant_menu, 'Dine In / Take Away', 'Pilih makan di tempat atau dibungkus saat checkout'),
              (Icons.tune, 'Level & catatan', 'Atur tingkat pedas, ukuran, atau catatan khusus per item'),
              (Icons.timelapse, 'Lacak pesanan', 'Pantau pesanan dari dimasak sampai siap diambil'),
              (Icons.receipt_long_outlined, 'Struk digital', 'Simpan struk ke galeri atau kirim ke email'),
              (Icons.history, 'Riwayat pesanan', 'Tetap tersimpan walau memesan tanpa login'),
              (Icons.confirmation_number_outlined, 'Voucher KaataGo', 'Tebus kode voucher dan pakai di merchant mana pun yang berlaku'),
              (Icons.pin_outlined, 'Nomor pesanan', 'Nomor antrean harian, muncul sejak pesanan dibuat'),
              (Icons.near_me_outlined, 'Merchant terdekat', 'Daftar tempat dalam radius 5 km berikut fasilitasnya'),
              (Icons.star_outline, 'Beri penilaian', 'Bintang, komentar, dan foto untuk merchant maupun menunya'),
              (Icons.qr_code_2_outlined, 'QRIS Dinamis & Statis', 'Bayar dari HP sendiri, atau pindai QR milik merchant lalu bayar di kasir'),
            ]),
          ),
          const SizedBox(height: 14),
          const _Section(
            title: 'Untuk Merchant',
            child: _Features([
              (Icons.point_of_sale_outlined, 'Kasir', 'Input pesanan, hitung total, terima Tunai/QRIS/Transfer'),
              (Icons.inventory_2_outlined, 'Kelola produk', 'Foto, harga, stok, kategori, dan varian produk'),
              (Icons.soup_kitchen_outlined, 'Layar dapur', 'Pesanan masuk real-time, dari Baru sampai Selesai'),
              (Icons.qr_code_2_outlined, 'Generator QR meja', 'Buat dan cetak QR untuk tiap nomor meja'),
              (Icons.list_alt_outlined, 'Pesanan masuk', 'Rekap harian, dikelompokkan Dine In dan Take Away'),
              (Icons.storefront_outlined, 'Multi merchant', 'Satu akun pusat mengelola banyak cabang'),
              (Icons.tv_outlined, 'Layar pelanggan', 'Perangkat kedua menghadap pelanggan, QR dan totalnya tampil di sana'),
              (Icons.search, 'Cari menu', 'Temukan satu item tanpa menggulir seluruh kategori'),
              (Icons.local_offer_outlined, 'Diskon & bundling', 'Potongan per menu, minimal qty, sampai paket beli-2'),
              (Icons.add_circle_outline, 'Topping & level', 'Tambahan berbayar dan varian, masing-masing dengan harganya'),
              (Icons.photo_size_select_actual_outlined, 'Banner promo', 'Tampil di halaman menu pelanggan, lengkap dengan masa berlakunya'),
              (Icons.chair_outlined, 'Fasilitas tempat', 'AC, Smoking Area, Live Music — tampil saat pelanggan memilih'),
              (Icons.point_of_sale, 'Shift kasir', 'Buka dan tutup shift dengan menghitung laci; selisihnya ketahuan hari itu juga'),
              (Icons.hourglass_bottom, 'Pending payment', 'Pesanan dari HP pelanggan yang dibayar di kasir, lengkap dengan hitung mundurnya'),
              (Icons.account_balance_outlined, 'Setor & cash pickup', 'Setor tunai ke rekening atau serahkan ke petugas penjemput, keduanya berikut buktinya'),
              (Icons.badge_outlined, 'Kelola karyawan', 'Tambah, ubah, dan nonaktifkan akun kasir, chef, admin, dan finance'),
              (Icons.show_chart, 'Laporan penjualan bergrafik', 'Tren omzet harian sampai bulanan, pembagian per cara bayar dan kategori, menu terlaris, dan jam ramai'),
              (Icons.fingerprint, 'Absensi wajah', 'Absen masuk dan pulang lewat kamera depan, dicocokkan dengan wajah yang didaftarkan dan titik GPS merchant'),
              (Icons.event_busy_outlined, 'Izin, sakit, dan cuti', 'Diajukan dari aplikasi berikut lampiran suratnya'),
              (Icons.access_time, 'Jam kerja', 'Dihitung dari absen masuk sampai absen pulang, ikut di rekap dan cetakannya'),
              (Icons.star_outline, 'Penilaian pelanggan', 'Bintang, komentar, dan foto yang masuk dari pelanggan'),
              (Icons.inbox_outlined, 'Kotak masuk', 'Pengumuman KaataGo dan pemberitahuan yang menunggu ditindaklanjuti'),
            ]),
          ),
          const SizedBox(height: 14),
          const _Section(
            title: 'Untuk Keuangan',
            child: _Features([
              (Icons.trending_up, 'Pemasukan', 'Rekap harian dengan rincian per metode pembayaran'),
              (Icons.account_balance_wallet_outlined, 'Saldo & Petty Cash', 'Pantau saldo penghasilan dan kas kecil'),
              (Icons.trending_down, 'Pengeluaran', 'Catat biaya lengkap dengan foto bukti nota'),
              (Icons.numbers, 'Mapping GL Account', 'Hubungkan tiap transaksi ke nomor akun akuntansi'),
              (Icons.menu_book_outlined, 'Jurnal GL', 'Catatan otomatis setiap pergerakan uang, bisa diekspor'),
              (Icons.picture_as_pdf_outlined, 'Laporan PDF', 'Laporan transaksi siap cetak seperti rekening koran'),
              (Icons.savings_outlined, 'Setoran modal', 'Uang masuk dari luar penjualan, tercatat di akunnya sendiri'),
              (Icons.receipt_long_outlined, 'Tagihan langganan', 'Bayar lewat Virtual Account, invoice PDF-nya bisa diunduh'),
              (Icons.sync_alt, 'Pencairan gateway', 'Catat dana QRIS yang masuk rekening berikut potongannya'),
              (Icons.account_balance_wallet_outlined, 'Saldo Perusahaan', 'Uang tunai yang dipegang dan uang di rekening, masing-masing dengan saldonya sendiri'),
              (Icons.event_available_outlined, 'Tutup buku harian', 'Kunci angka sehari per metode bayar; koreksi belakangan muncul sebagai selisih'),
              (Icons.compare_arrows, 'Rekonsiliasi bank', 'Cocokkan mutasi rekening dengan setoran dan pembayaran yang tercatat'),
              (Icons.local_shipping_outlined, 'Terima cash pickup', 'Serah terima uang yang dijemput petugas: segel, jumlah, dan bukti terimanya'),
              (Icons.account_balance_outlined, 'Rekening perusahaan', 'Satu rekening bisa dipakai beberapa cabang, mutasinya tertaut ke rekeningnya'),
              (Icons.date_range, 'Laporan per periode', 'Jurnal GL dan laporan transaksi dipilih rentang tanggalnya sebelum dicetak'),
              (Icons.payments_outlined, 'Payroll', 'Gaji per karyawan, tanggal gajian, hari kerja per periode, dan potongan BPJS'),
              (Icons.calculate_outlined, 'Potongan otomatis', 'Gaji disesuaikan sendiri dengan hari yang tidak masuk, dan tidak pernah jadi minus'),
              (Icons.description_outlined, 'Cetak absensi & payroll', 'PDF dan XLSX berikut kode bank, siap dipakai menyusun daftar transfer'),
              (Icons.receipt_outlined, 'Slip gaji', 'Diunduh sendiri oleh karyawan, dirinci sampai asal tiap potongan'),
              (Icons.rule_folder_outlined, 'Periksa pembukuan', 'Memeriksa enam aturan yang tidak boleh dilanggar, dan hanya melaporkan yang dilanggar'),
              (Icons.flag_outlined, 'Saldo awal', 'Menyatakan isi kas dan rekening per tanggal, supaya cocok dengan mutasi bank sungguhan'),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => bukaWhatsAppKaataGo(context),
              icon: const Icon(Icons.chat, size: 18, color: Color(0xFF25D366)),
              label: const Text('Chat KaataGo Admin di WhatsApp'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: Color(0xFF25D366)),
                foregroundColor: const Color(0xFF25D366),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => bukaEmailKaataGo(context),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text(kEmailKaataGo),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Butuh bantuan? Hubungi KaataGo Admin lewat WhatsApp atau '
              'surel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context)),
            ),
          ),
          const SizedBox(height: 18),
          // Atribusi yang memang dituntut lisensinya.
          //
          // Apache-2.0 mengizinkan pemakaian komersial, dengan satu
          // syarat yang tidak boleh dilewati: menyebut asalnya dan
          // menyertakan salinan lisensinya. Salinannya ada di
          // assets/face/LICENSE-facenet.txt, dan penyebutannya di sini.
          Center(
            child: Text(
              'Pengenalan wajah untuk absensi memakai model FaceNet dari '
              'shubham0204/FaceRecognition_With_FaceNet_Android, berlisensi '
              'Apache License 2.0. Modelnya berjalan di HP ini — foto '
              'wajah tidak dikirim ke pihak mana pun.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: KaataTheme.mutedOf(context)),
            ),
          ),
          // Ruang untuk tombol mengambang di bawah — tanpa ini baris
          // terakhirnya selalu tertutup.
          const SizedBox(height: 72),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FaqScreen()),
        ),
        icon: const Icon(Icons.help_outline),
        label: const Text('FAQ'),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: KaataTheme.brand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Tautan ke situs KaataGo.
///
/// Ditaruh di layar ini karena inilah satu-satunya halaman yang bisa
/// dibuka sebelum login — yang membukanya sering justru orang yang
/// belum punya akun dan sedang menimbang, dan yang dia butuhkan
/// berikutnya ada di situsnya: cara berlangganan, dan berkas
/// pemasangnya.
class _WebsiteLink extends StatefulWidget {
  const _WebsiteLink();

  @override
  State<_WebsiteLink> createState() => _WebsiteLinkState();
}

class _WebsiteLinkState extends State<_WebsiteLink> {
  /// Tautannya dibaca dari basis data, disetel KaataGo Admin.
  ///
  /// Dulu ditulis mati di dalam APK, jadi mengganti alamat situs berarti
  /// merilis APK baru — dan HP yang belum memperbarui terus membuka
  /// alamat lama selamanya. Sambil menunggu jawabannya, tombolnya sudah
  /// bisa ditekan dengan alamat bawaan: tombol yang mati karena sinyal
  /// lemah di halaman login lebih buruk daripada alamat yang sedikit tua.
  String _url = SetelanPlatformRepository.tautanSitusBawaan;

  @override
  void initState() {
    super.initState();
    SetelanPlatformRepository().tautanSitus().then((t) {
      if (mounted && t != _url) setState(() => _url = t);
    });
  }

  /// Alamat untuk dibaca orang: tanpa https:// dan garis miring penutup.
  String get _tampil => _url
      .replaceFirst(RegExp(r'^https://'), '')
      .replaceFirst(RegExp(r'/$'), '');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KaataTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => launchUrl(
          Uri.parse(_url),
          // Di browser, bukan di dalam aplikasi: halamannya memuat
          // tautan unduhan APK, dan tampilan web di dalam aplikasi
          // menangani unduhan berkas dengan cara yang berbeda-beda di
          // tiap HP — sebagian diam saja.
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: KaataTheme.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.language, size: 18, color: KaataTheme.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Situs KaataGo',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      _tampil,
                      style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new, size: 17, color: KaataTheme.mutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Features extends StatelessWidget {
  final List<(IconData, String, String)> items;

  const _Features(this.items);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (icon, title, desc) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: KaataTheme.brand.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: KaataTheme.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(desc,
                          style: TextStyle(
                              fontSize: 12, height: 1.35, color: KaataTheme.mutedOf(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
