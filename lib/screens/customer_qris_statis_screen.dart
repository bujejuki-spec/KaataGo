import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../db/metode_bayar_repository.dart';
import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../theme.dart';
import '../utils/gambar_unggah.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/gambar_tersimpan.dart';
import '../widgets/hitung_mundur_bayar.dart';

/// Pelanggan membayar QRIS Statis dari HP-nya sendiri.
///
/// ── Kenapa tidak disuruh ke kasir seperti tunai ──────────────────────
///
/// Dulu QRIS Statis diperlakukan sama persis dengan tunai: pesanan
/// masuk, lalu pelanggan disuruh berdiri di meja kasir. Padahal justru
/// inilah cara bayar yang paling tidak perlu ke kasir — QR-nya bisa
/// dipindai dari HP sendiri, dan buktinya ada di HP itu juga.
///
/// ── Yang tetap dipegang kasir ────────────────────────────────────────
///
/// Pernyataan lunasnya. QR statis tidak membawa nominal dan tidak ada
/// satu pun kabar yang datang dari penyedia pembayaran, jadi tidak ada
/// yang bisa memastikan uangnya benar-benar masuk selain orang yang
/// melihat mutasinya. Tombol "sudah bayar" yang bisa ditekan pelanggan
/// bukan bukti pembayaran — ia cuma tombol.
///
/// Yang dilakukan layar ini memindahkan buktinya lebih awal, supaya
/// kasir tinggal mencocokkan alih-alih menunggu orangnya datang.
class CustomerQrisStatisScreen extends StatefulWidget {
  final String orderId;
  final int amount;
  final String restoId;

  /// Kapan pesanannya dibuat — titik nol tenggang membayar.
  final DateTime? createdAt;

  const CustomerQrisStatisScreen({
    super.key,
    required this.orderId,
    required this.amount,
    required this.restoId,
    this.createdAt,
  });

  @override
  State<CustomerQrisStatisScreen> createState() =>
      _CustomerQrisStatisScreenState();
}

class _CustomerQrisStatisScreenState extends State<CustomerQrisStatisScreen> {
  final _repo = OrderRepository();

  late final DateTime _tenggat =
      (widget.createdAt ?? DateTime.now()).add(CustomerOrder.paymentWindow);

  RefGambar? _qr;
  bool _memuat = true;
  bool _mengirim = false;
  bool _terkirim = false;

  @override
  void initState() {
    super.initState();
    _muatQr();
  }

  Future<void> _muatQr() async {
    try {
      final m = await MetodeBayarRepository().baca(widget.restoId);
      if (mounted) {
        setState(() {
          _qr = m.adaQrStatis
              ? (base64: m.qrisStatisBase64, jalurLama: m.qrisStatisUrl)
              : null;
          _memuat = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _unggahBukti() async {
    // Galeri, bukan kamera.
    //
    // Buktinya tangkapan layar aplikasi bank atau dompet digital yang
    // baru saja dipakai — ia sudah ada di galeri, dan menyuruh orang
    // memotret layarnya sendiri dengan kamera adalah jalan memutar yang
    // menghasilkan foto miring dan silau.
    final foto = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 80,
    );
    if (foto == null) return;

    final Uint8List bytes = await foto.readAsBytes();
    if (!mounted) return;

    setState(() => _mengirim = true);
    try {
      await _repo.lampirkanBuktiBayar(
        orderId: widget.orderId,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _terkirim = true);
      showAppToast(context, 'Bukti terkirim. Kasir akan memastikannya.');
    } on GambarDitolak catch (e) {
      // Formatnya salah atau terlalu besar — disebut apa adanya, bukan
      // dibungkus jadi "gagal mengirim".
      if (mounted) showAppToast(context, e.pesan, isError: true);
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  /// Menahan tombol kembali selama buktinya belum ada.
  ///
  /// ── Kenapa tetap ada jalan keluarnya ─────────────────────────────
  ///
  /// Layar ini dibuka pelanggan dari peramban HP-nya sendiri, hasil
  /// memindai QR meja. Menutup tabnya tidak bisa dicegah siapa pun, jadi
  /// "wajib" yang benar-benar mengunci tidak ada — yang terjebak hanya
  /// akan menutup tabnya, dan pesanannya tetap menggantung tanpa bukti.
  ///
  /// Bedanya: kalau ia keluar lewat tab, ia keluar tanpa tahu
  /// akibatnya. Kalau ia keluar lewat sini, ia sudah diberi tahu.
  /// Itulah yang bisa dilakukan layar ini, dan itu memang yang berguna.
  Future<void> _tanyaKeluar() async {
    final keluar = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.receipt_long_outlined,
            size: 32, color: Colors.orange),
        title: const Text('Buktinya belum diunggah',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 17)),
        content: Text(
          'Kasir tidak punya cara memastikan pembayaranmu tanpa bukti '
          'transfernya, jadi pesanan ini belum akan disiapkan.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5, height: 1.45, color: KaataTheme.mutedOf(context)),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Unggah Sekarang',
            onConfirm: () => Navigator.pop(d, false),
            cancelLabel: 'Keluar Tanpa Bukti',
            onCancel: () => Navigator.pop(d, true),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (keluar == true) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      await _unggahBukti();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rp = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final ref = widget.orderId.length >= 8
        ? widget.orderId.substring(0, 8).toUpperCase()
        : widget.orderId.toUpperCase();
    final muted = KaataTheme.mutedOf(context);

    return PopScope(
      canPop: _terkirim,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tanyaKeluar();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Bayar QRIS'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nominalnya di ATAS QR-nya, dan sengaja paling besar.
              //
              // QR statis tidak membawa nominal: yang mengetik jumlahnya
              // adalah pelanggan sendiri, di aplikasi banknya. Yang
              // paling mungkin keliru bukan QR-nya melainkan angka itu.
              Text('Yang harus dibayar',
                  style: TextStyle(fontSize: 12.5, color: muted)),
              const SizedBox(height: 2),
              Text(
                rp.format(widget.amount),
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold, height: 1.1),
              ),
              const SizedBox(height: 4),
              Text('Pesanan #$ref',
                  style: TextStyle(fontSize: 12.5, color: muted)),
              const SizedBox(height: 18),

              if (_memuat)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: CircularProgressIndicator(),
                )
              else if (_qr == null)
                _Kotak(
                  warna: Colors.red,
                  child: Text(
                    'QR pembayaran merchant belum terpasang. Silakan '
                    'selesaikan pembayaran di kasir dengan menyebutkan '
                    'nomor pesanan di atas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: KaataTheme.borderOf(context)),
                  ),
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: GambarTersimpan.dariRef(
                      _qr,
                      ember: 'qris-statis',
                      fit: BoxFit.contain,
                      kosong: 'QR gagal dimuat',
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              HitungMundurBayar(deadline: _tenggat),
              const SizedBox(height: 16),

              if (_terkirim)
                _Kotak(
                  warna: Colors.green,
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF10B981), size: 28),
                      const SizedBox(height: 8),
                      const Text('Bukti pembayaran terkirim',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(
                        'Pesanan kamu sudah diteruskan ke dapur. Kasir '
                        'memastikan pembayarannya, dan statusnya berubah '
                        'sendiri begitu dipastikan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ),
                )
              else
                _Kotak(
                  warna: Colors.amber,
                  child: Column(
                    children: [
                      Text(
                        'Pindai QR di atas, bayar sejumlah yang tertera, '
                        'lalu unggah bukti pembayarannya di sini. Tanpa '
                        'bukti, pesananmu belum akan disiapkan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: _mengirim
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.upload_file, size: 18),
                          label: Text(_mengirim
                              ? 'Mengirim…'
                              : 'Unggah Bukti Pembayaran'),
                          onPressed: _mengirim ? null : _unggahBukti,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 10),
              // Boleh diunggah ulang. Yang salah kirim tanpa jalan
              // membetulkan akan menghubungi kasir — dan kasir tidak
              // punya cara memperbaikinya dari sisinya.
              if (_terkirim)
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Ganti bukti'),
                  onPressed: _mengirim ? null : _unggahBukti,
                ),

              const SizedBox(height: 14),
              // Selesai terkunci sampai buktinya terkirim.
              //
              // Inilah yang dulu membuat unggahannya opsional: tombol
              // ini memulangkan orangnya ke awal tanpa peduli buktinya
              // sudah ada atau belum. Yang sudah membayar lalu menekan
              // Selesai merasa urusannya tuntas — padahal kasir tidak
              // punya satu pun bukti untuk dicocokkan, dan pesanannya
              // menggantung sampai tenggangnya habis.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _terkirim
                      ? () => Navigator.of(context).popUntil((r) => r.isFirst)
                      : null,
                  child: Text(_terkirim ? 'Selesai' : 'Unggah bukti dulu'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _Kotak extends StatelessWidget {
  final MaterialColor warna;
  final Widget child;

  const _Kotak({required this.warna, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KaataTheme.tintOf(context, warna),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: warna.withOpacity(0.35)),
        ),
        child: child,
      );
}
