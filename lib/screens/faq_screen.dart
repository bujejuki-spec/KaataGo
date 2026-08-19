import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/app_toast.dart';

/// Nomor WhatsApp KaataGo Admin.
///
/// Sama dengan yang tertulis di landing page. Ditulis sekali di sini
/// dan dipakai bersama — dua nomor terpisah akan berpisah suatu saat,
/// dan yang menemukannya adalah orang yang mengirim pesan ke nomor yang
/// sudah tidak dipakai.
const kWhatsAppKaataGo = '6281316090867';

/// Membuka percakapan WhatsApp dengan KaataGo Admin.
Future<void> bukaWhatsAppKaataGo(BuildContext context, {String? pesan}) async {
  final teks = Uri.encodeComponent(
    pesan ?? 'Halo KaataGo, saya mau bertanya soal aplikasinya.',
  );
  final url = Uri.parse('https://wa.me/$kWhatsAppKaataGo?text=$teks');
  final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    AppToast.show(context, 'Tidak bisa membuka WhatsApp.', isError: true);
  }
}

/// Pertanyaan yang paling sering ditanyakan, sama dengan di landing page.
///
/// Disalin ke sini, bukan diambil dari webnya: halaman yang gagal dimuat
/// karena sinyal buruk berarti jawaban yang justru paling dibutuhkan
/// saat sedang bermasalah tidak bisa dibaca sama sekali.
const _faq = <(String, String)>[
  (
    'Apakah customer perlu install aplikasi juga?',
    'Tidak wajib. Customer bisa langsung memesan ke kasir yang sudah '
        'menggunakan KaataGo.',
  ),
  (
    'Kenapa customer perlu install KaataGo?',
    'Karena bisa dapat info promo menarik dari merchant yang sudah '
        'bekerja sama dengan KaataGo — langsung masuk ke kotak masuk di '
        'HP-nya, lengkap dengan nama merchantnya — dan bahkan bisa dapat '
        'voucher menarik juga dari KaataGo. Riwayat pesanannya juga '
        'tersimpan dan ikut terbawa saat ganti HP.',
  ),
  (
    'Bagaimana kalau internet mati?',
    'Data menu dan transaksi kasir disimpan juga di HP, jadi kasir tetap '
        'bisa jalan. Begitu koneksi kembali, datanya menyusul ke server.',
  ),
  (
    'Apakah pembayaran QRIS diproses oleh KaataGo?',
    'Tidak. QRIS-nya diproses Xendit, penyedia pembayaran berizin Bank '
        'Indonesia. Tiap merchant punya sub-akun sendiri di sana, jadi '
        'dananya cair langsung ke rekening merchant masing-masing — tidak '
        'pernah lewat rekening KaataGo. Yang KaataGo lakukan cuma '
        'menerbitkan QR-nya dan menandai pesanan lunas begitu Xendit '
        'mengabarkan pembayarannya masuk.',
  ),
  (
    'Tarif PPN dan biaya service bisa diatur?',
    'Bisa, per merchant, dari menu Finance. Harga menu yang dilihat '
        'customer otomatis sudah termasuk PPN, sedangkan biaya service '
        'hanya ditambahkan untuk pesanan Dine In. Produk tertentu juga '
        'bisa dikecualikan.',
  ),
  (
    'Datanya aman dan terpisah antar merchant?',
    'Ya. Setiap data terikat ke merchant-nya dan dijaga aturan akses di '
        'sisi server, bukan cuma disembunyikan di tampilan. Karyawan satu '
        'merchant tidak bisa membaca data merchant lain.',
  ),
  (
    'Berapa biaya langganan per bulannya?',
    'Jauh lebih murah daripada satu mesin kasir, dan tidak ada biaya di '
        'muka. Hubungi tim kami untuk hitungan yang pas dengan ukuran '
        'merchant kamu — sekalian klaim promo perdana yang masih kami buka '
        'untuk merchant yang bergabung lebih awal.',
  ),
];

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Pertanyaan Umum')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          for (final (tanya, jawab) in _faq)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: KaataTheme.surfaceOf(context),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: KaataTheme.borderOf(context)),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  // Terbuka sejak awal akan membuat halamannya jadi
                  // dinding teks; yang mencari satu jawaban harus
                  // menggulir melewati enam yang lain.
                  initiallyExpanded: false,
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: Text(tanya,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(jawab,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: KaataTheme.mutedOf(context))),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Masih ada yang belum terjawab? Tanya langsung ke KaataGo Admin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: KaataTheme.mutedOf(context)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
        onPressed: () => bukaWhatsAppKaataGo(context),
        icon: const Icon(Icons.chat),
        label: const Text('Chat KaataGo Admin'),
      ),
    );
  }
}
