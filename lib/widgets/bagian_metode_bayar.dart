import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../db/metode_bayar_repository.dart';
import '../models/metode_bayar.dart';
import '../theme.dart';
import '../utils/periksa_qris.dart';
import '../utils/pesan_galat.dart';
import 'app_toast.dart';
import 'dialog_actions.dart';

/// Metode bayar yang ditawarkan merchant, berikut QR statisnya.
///
/// Berdiri sendiri dari formulir di sekitarnya: yang di sini disimpan
/// begitu saklarnya digeser, bukan menunggu tombol Simpan formulir lain.
/// Menyatukannya dengan formulir yang punya tombol Batal akan membuat
/// "batal" berarti dua hal yang berbeda pada satu layar.
class BagianMetodeBayar extends StatefulWidget {
  final String restoId;

  /// Boleh mengubah, atau hanya melihat. Kasir dan Admin membacanya
  /// untuk tahu apa yang ditawarkan; yang mengubahnya Owner, Finance,
  /// dan KaataGo Admin.
  final bool bisaUbah;

  const BagianMetodeBayar({
    super.key,
    required this.restoId,
    required this.bisaUbah,
  });

  @override
  State<BagianMetodeBayar> createState() => _BagianMetodeBayarState();
}

class _BagianMetodeBayarState extends State<BagianMetodeBayar> {
  final _repo = MetodeBayarRepository();

  MetodeBayarMerchant _metode = const MetodeBayarMerchant();
  bool _memuat = true;
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final m = await _repo.baca(widget.restoId);
      if (!mounted) return;
      setState(() {
        _metode = m;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat metode bayar: ${pesanGalat(e)}',
          isError: true);
    }
  }

  Future<void> _simpan(MetodeBayarMerchant baru) async {
    // Setidaknya satu harus menyala. Merchant yang mematikan semuanya
    // berhenti bisa menerima uang sama sekali — dan itu bukan keadaan
    // yang pantas dicapai lewat satu ketukan yang tidak bertanya apa-apa.
    if (baru.yangAktif.isEmpty) {
      showAppToast(context, 'Setidaknya satu metode bayar harus menyala.',
          isError: true);
      return;
    }

    final sebelum = _metode;
    setState(() {
      _metode = baru;
      _sibuk = true;
    });
    try {
      await _repo.simpan(widget.restoId, baru);
    } catch (e) {
      if (!mounted) return;
      // Dikembalikan ke keadaan sebelumnya. Saklar yang tetap bergeser
      // padahal servernya menolak adalah kebohongan yang baru ketahuan
      // saat pelanggan pertama memilih metode yang sebenarnya mati.
      setState(() => _metode = sebelum);
      showAppToast(context, 'Gagal menyimpan: ${pesanGalat(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  /// Mengunggah QR statis, setelah dipastikan isinya benar QRIS.
  ///
  /// Pemindaiannya hanya ada di aplikasi HP. Di peramban, mobile_scanner
  /// melempar UnsupportedError untuk analyzeImage — dan mengunggah tanpa
  /// memeriksa berarti melepas satu-satunya hal yang membuat fitur ini
  /// bisa dipercaya: bahwa yang tampil di depan pelanggan memang QRIS
  /// merchant ini, bukan foto lain yang kebetulan terpilih.
  Future<void> _unggahQr() async {
    if (kIsWeb) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Unggah dari Aplikasi HP'),
          content: const Text(
            'QR statis diunggah lewat aplikasi KaataGo di HP.\n\n'
            'Di peramban, gambarnya tidak bisa dipindai untuk dipastikan '
            'benar QRIS — dan memasang QR yang tidak diperiksa berarti '
            'pelanggan bisa diarahkan membayar ke tempat yang salah.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d), child: const Text('Mengerti')),
          ],
        ),
      );
      return;
    }

    final XFile? dipilih;
    try {
      dipilih = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Tidak dikecilkan. QR yang diperkecil kehilangan ketajaman
        // kotak-kotaknya, dan yang gagal dipindai bukan cuma pemeriksaan
        // di sini — kamera pelanggan juga.
        imageQuality: 100,
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal membuka galeri: ${pesanGalat(e)}',
          isError: true);
      return;
    }
    if (dipilih == null || !mounted) return;

    setState(() => _sibuk = true);
    try {
      final hasil = await MobileScannerController().analyzeImage(dipilih.path);
      final payload = hasil?.barcodes.isNotEmpty == true
          ? hasil!.barcodes.first.rawValue
          : null;

      final periksa = periksaPayloadQris(payload);
      if (!periksa.sah) {
        if (!mounted) return;
        setState(() => _sibuk = false);
        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Gambarnya Bukan QRIS'),
            content: Text(periksa.alasan!),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Tutup')),
            ],
          ),
        );
        return;
      }

      // Ditunjukkan nama merchantnya sebelum disimpan. Pemeriksaan
      // otomatis bisa memastikan ini QRIS; ia tidak bisa memastikan ini
      // QRIS MILIKMU — dan satu-satunya yang tahu itu orang yang sedang
      // memegang layarnya.
      if (!mounted) return;
      final lanjut = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Pastikan QR-nya Benar'),
          content: Text(
            periksa.namaMerchant == null
                ? 'QR ini terbaca sebagai QRIS yang sah. Pastikan ini QR '
                    'milik merchantmu sendiri sebelum dipasang.'
                : 'QR ini terdaftar atas nama:\n\n'
                    '${periksa.namaMerchant}\n\n'
                    'Kalau itu bukan merchantmu, jangan dipasang — '
                    'pelanggan akan membayar ke sana.',
          ),
          actions: [
            DialogActions(
              confirmLabel: 'Pasang QR Ini',
              onCancel: () => Navigator.pop(d, false),
              onConfirm: () => Navigator.pop(d, true),
            ),
          ],
          actionsAlignment: MainAxisAlignment.center,
        ),
      );
      if (lanjut != true || !mounted) {
        setState(() => _sibuk = false);
        return;
      }

      final Uint8List bytes = await dipilih.readAsBytes();
      final url = await _repo.unggahQr(widget.restoId, bytes);
      await _simpan(_metode.copyWith(
        qrisStatisUrl: url,
        qrisStatisPayload: payload,
        qrisStatis: true,
      ));
      if (!mounted) return;
      showAppToast(context, 'QR statis terpasang.');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal memasang QR: ${pesanGalat(e)}',
          isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _hapusQr() async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Hapus QR Statis?'),
        content: const Text(
          'QRIS Statis ikut dimatikan, dan pelanggan tidak lagi bisa '
          'memilihnya.',
        ),
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onCancel: () => Navigator.pop(d, false),
            onConfirm: () => Navigator.pop(d, true),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
    if (yakin != true || !mounted) return;

    // Barisnya dilepas lebih dulu, berkasnya menyusul. Kalau urutannya
    // dibalik dan penghapusan barisnya gagal, yang tersisa adalah metode
    // menyala yang gambarnya sudah tidak ada.
    await _simpan(_metode.copyWith(hapusQrisStatis: true));
    try {
      await _repo.hapusQr(widget.restoId);
    } catch (_) {
      // Berkas yatim di Storage jauh lebih ringan daripada metode bayar
      // yang gagal dimatikan.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final url = _metode.qrisStatisUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Metode Pembayaran',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          'Yang dimatikan tidak ditawarkan ke kasir maupun ke pelanggan.',
          style: TextStyle(fontSize: 12.5, color: KaataTheme.mutedOf(context)),
        ),
        const SizedBox(height: 8),
        _saklar(MetodeBayar.tunai, _metode.tunai,
            (v) => _simpan(_metode.copyWith(tunai: v)),
            catatan: 'Uangnya masuk laci kasir'),
        _saklar(MetodeBayar.qrisDinamis, _metode.qrisDinamis,
            (v) => _simpan(_metode.copyWith(qrisDinamis: v)),
            catatan: 'Lewat penyedia pembayaran, dicairkan menyusul'),
        _saklar(
          MetodeBayar.qrisStatis,
          _metode.qrisStatis,
          url == null ? null : (v) => _simpan(_metode.copyWith(qrisStatis: v)),
          catatan: url == null
              ? 'Unggah QR-nya dulu di bawah'
              : 'QR cetak sendiri — dibayar lewat kasir',
        ),
        _saklar(MetodeBayar.transfer, _metode.transfer,
            (v) => _simpan(_metode.copyWith(transfer: v)),
            catatan: 'Transfer bank manual'),
        const SizedBox(height: 16),
        _kartuQr(url),
      ],
    );
  }

  Widget _saklar(MetodeBayar m, bool nyala, ValueChanged<bool>? onUbah,
      {required String catatan}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: nyala,
      onChanged: (!widget.bisaUbah || _sibuk) ? null : onUbah,
      title: Text(m.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(catatan,
          style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context))),
    );
  }

  Widget _kartuQr(String? url) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('QR Statis',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            'Gambarnya diperiksa dulu — yang bukan QRIS ditolak, dan nama '
            'merchant di dalamnya ditunjukkan sebelum dipasang.',
            style:
                TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
          ),
          const SizedBox(height: 12),
          if (url != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                height: 190,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(
                  'Gambarnya gagal dimuat.',
                  style: TextStyle(color: KaataTheme.mutedOf(context)),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (widget.bisaUbah)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sibuk ? null : _unggahQr,
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(url == null ? 'Unggah QR' : 'Ganti QR'),
                  ),
                ),
                if (url != null) ...[
                  const SizedBox(width: 9),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sibuk ? null : _hapusQr,
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      label: const Text('Hapus',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
