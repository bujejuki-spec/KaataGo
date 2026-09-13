import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/bank_account_repository.dart';
import '../db/paket_langganan_repository.dart';
import '../models/bank_account.dart';
import '../models/paket_langganan.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/pesan_galat.dart';
import '../utils/photo_picker.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/lencana_paket_aktif.dart';
import '../widgets/responsive.dart';

/// Merchant memilih paket lalu membayarnya.
///
/// Satu layar, tiga langkah yang tidak dipisah jadi tiga halaman: pilih
/// paketnya, transfer ke rekening KaataGo, unggah buktinya. Memisahnya
/// jadi wizard berarti orang yang sudah transfer harus mengulang dari
/// halaman pertama begitu aplikasinya tertutup — dan yang sudah
/// mengirim uang adalah orang yang paling tidak pantas disuruh
/// mengulang.
class PilihPaketScreen extends StatefulWidget {
  const PilihPaketScreen({super.key});

  @override
  State<PilihPaketScreen> createState() => _PilihPaketScreenState();
}

class _PilihPaketScreenState extends State<PilihPaketScreen> {
  final _repo = PaketLanggananRepository();

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<InfoPaket> _paket = const [];
  List<BankAccount> _rekening = const [];
  KeadaanLangganan _keadaan = const KeadaanLangganan();

  Paket? _dipilih;
  Uint8List? _bukti;
  final _catatan = TextEditingController();

  bool _memuat = true;
  bool _mengirim = false;
  String? _galat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  @override
  void dispose() {
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) {
      setState(() {
        _memuat = false;
        _galat = 'Akunmu belum terhubung ke merchant mana pun.';
      });
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final hasil = await Future.wait([
        _repo.daftarPaket(),
        // Rekening KaataGo, bukan rekening merchantnya sendiri.
        BankAccountRepository().untukResto('kaatago'),
        _repo.keadaan(restoId),
      ]);
      if (!mounted) return;
      setState(() {
        _paket = hasil[0] as List<InfoPaket>;
        _rekening = hasil[1] as List<BankAccount>;
        _keadaan = hasil[2] as KeadaanLangganan;
        _dipilih ??= _keadaan.paket;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = pesanGalat(e);
        _memuat = false;
      });
    }
  }

  Future<void> _ambilBukti() async {
    final bytes = await pickProofPhoto(context);
    if (bytes != null && mounted) setState(() => _bukti = bytes);
  }

  Future<void> _kirim() async {
    final restoId = context.read<AuthProvider>().restoId;
    final paket = _dipilih;
    final bukti = _bukti;
    if (restoId == null || paket == null || bukti == null) return;

    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Berlangganan ${paket.label}?'),
        content: Text(
          'Pengajuanmu akan diperiksa KaataGo, paling lama 1×24 jam.\n\n'
          'Selama diperiksa, aplikasi belum bisa dipakai kembali. Begitu '
          'pembayarannya dipastikan masuk, paket ${paket.label} langsung '
          'berjalan.',
        ),
        actions: [
          DialogActions(
            confirmLabel: 'Kirim Pengajuan',
            onConfirm: () => Navigator.pop(c, true),
          ),
        ],
      ),
    );
    if (yakin != true || !mounted) return;

    setState(() => _mengirim = true);
    try {
      final url = await _repo.unggahBukti(restoId: restoId, bytes: bukti);
      await _repo.ajukan(
        restoId: restoId,
        paket: paket,
        buktiUrl: url,
        catatan: _catatan.text.trim().isEmpty ? null : _catatan.text.trim(),
      );
      if (!mounted) return;
      showAppToast(context, 'Pengajuan terkirim. Menunggu diperiksa KaataGo.');
      await _muat();
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Langganan KaataGo')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_galat != null)
                    Text(_galat!, style: const TextStyle(color: Colors.red))
                  else if (_keadaan.sedangDiperiksa)
                    const _SedangDiperiksa()
                  else ...[
                    if (_keadaan.pengajuanDitolak)
                      _Ditolak(alasan: _keadaan.alasanTolak),
                    _Pengantar(keadaan: _keadaan),
                    const SizedBox(height: 18),
                    Text('Pilih paket',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: muted)),
                    const SizedBox(height: 10),
                    for (final p in _paket)
                      _KartuPaket(
                        info: p,
                        rp: _rp,
                        dipilih: _dipilih == p.paket,
                        sedangDipakai: _keadaan.paket == p.paket,
                        onTap: () => setState(() => _dipilih = p.paket),
                      ),
                    if (_dipilih != null) ...[
                      const SizedBox(height: 20),
                      Text('Transfer ke rekening KaataGo',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: muted)),
                      const SizedBox(height: 10),
                      if (_rekening.isEmpty)
                        _Kotak(
                          child: Text(
                            'Rekening KaataGo belum tersedia di aplikasi. '
                            'Hubungi KaataGo Support lewat tombol bantuan.',
                            style: TextStyle(fontSize: 12.5, color: muted),
                          ),
                        )
                      else
                        for (final r in _rekening) _KartuRekening(rekening: r),
                      const SizedBox(height: 20),
                      Text('Bukti transfer',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: muted)),
                      const SizedBox(height: 4),
                      Text(
                        'Wajib. Pengajuan tanpa bukti tidak bisa diperiksa '
                        'siapa pun.',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                      const SizedBox(height: 10),
                      _PetakBukti(
                          bukti: _bukti,
                          onAmbil: _ambilBukti,
                          onHapus: () => setState(() => _bukti = null)),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _catatan,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'Catatan (opsional)',
                          hintText: 'Contoh: transfer atas nama Budi Santoso',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          icon: _mengirim
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send, size: 18),
                          label: Text(_mengirim
                              ? 'Mengirim...'
                              : 'Kirim Pengajuan Langganan'),
                          onPressed:
                              _bukti == null || _mengirim ? null : _kirim,
                        ),
                      ),
                      if (_bukti == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Unggah bukti transfernya dulu untuk bisa mengirim.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _Pengantar extends StatelessWidget {
  final KeadaanLangganan keadaan;

  const _Pengantar({required this.keadaan});

  @override
  Widget build(BuildContext context) {
    final habis = keadaan.percobaanHabis;
    final sisa = keadaan.sisaHari;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: habis
              ? [const Color(0xFFDC2626), const Color(0xFF991B1B)]
              : [KaataTheme.brand, KaataTheme.brandDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            habis
                ? 'Masa percobaan sudah berakhir'
                : sisa != null && keadaan.dalamPercobaan
                    ? 'Masa percobaan tinggal $sisa hari'
                    : 'Pilih paket langgananmu',
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            habis
                ? 'Pilih paket dan kirim bukti transfernya. Begitu KaataGo '
                    'memastikan pembayarannya masuk, aplikasinya bisa dipakai '
                    'lagi seperti semula — data merchantmu tetap utuh.'
                : 'Berlangganan sekarang supaya aplikasinya tidak berhenti '
                    'bisa dipakai saat percobaannya habis.',
            style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Colors.white.withOpacity(0.9)),
          ),
        ],
      ),
    );
  }
}

/// Selama diperiksa, tidak ada yang bisa dilakukan selain menunggu.
///
/// Layar ini menyebut batas waktunya. Menunggu tanpa tahu sampai kapan
/// adalah keadaan yang membuat orang menekan tombolnya berulang kali,
/// lalu mengirim pengajuan kedua untuk uang yang sama.
class _SedangDiperiksa extends StatelessWidget {
  const _SedangDiperiksa();

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: KaataTheme.tintOf(context, Colors.orange),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.hourglass_top,
              size: 40, color: KaataTheme.onTintOf(context, Colors.orange)),
        ),
        const SizedBox(height: 18),
        const Text('Pembayaranmu sedang diperiksa',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Paling lama 1×24 jam. Begitu KaataGo memastikan pembayarannya '
          'masuk, paketmu langsung berjalan dan aplikasinya bisa dipakai '
          'kembali.\n\nTidak perlu mengirim ulang — pengajuan kedua untuk '
          'uang yang sama justru membuat pemeriksaannya lebih lama.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: muted),
        ),
      ],
    );
  }
}

class _Ditolak extends StatelessWidget {
  final String? alasan;

  const _Ditolak({this.alasan});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pengajuan sebelumnya ditolak',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB91C1C))),
                if (alasan?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(alasan!,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFB91C1C))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KartuPaket extends StatelessWidget {
  final InfoPaket info;
  final NumberFormat rp;
  final bool dipilih;
  final bool sedangDipakai;
  final VoidCallback onTap;

  const _KartuPaket({
    required this.info,
    required this.rp,
    required this.dipilih,
    required this.sedangDipakai,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final warna = warnaPaket(info.paket);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: dipilih ? warna : KaataTheme.borderOf(context),
                width: dipilih ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LencanaPaket(paket: info.paket),
                    const Spacer(),
                    if (sedangDipakai)
                      Text('paket sekarang',
                          style: TextStyle(fontSize: 11, color: muted)),
                    const SizedBox(width: 8),
                    Icon(
                      dipilih
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: dipilih ? warna : muted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(rp.format(info.harga),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Text('/bulan',
                        style: TextStyle(fontSize: 12.5, color: muted)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(info.keterangan,
                    style:
                        TextStyle(fontSize: 12.5, height: 1.45, color: muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rekening KaataGo, nomornya bisa disalin.
///
/// Nomor rekening yang harus diketik ulang dari layar adalah nomor yang
/// salah ketik — dan uang yang masuk ke rekening lain tidak bisa
/// diperiksa siapa pun di sini.
class _KartuRekening extends StatelessWidget {
  final BankAccount rekening;

  const _KartuRekening({required this.rekening});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: KaataTheme.softFillOf(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rekening.bankName,
                    style: TextStyle(fontSize: 11.5, color: muted)),
                const SizedBox(height: 2),
                Text(rekening.accountNumber,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
                if (rekening.accountHolder.isNotEmpty)
                  Text('a.n. ${rekening.accountHolder}',
                      style: TextStyle(fontSize: 11.5, color: muted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Salin nomor rekening',
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: rekening.accountNumber));
              if (context.mounted) {
                showAppToast(context, 'Nomor rekening disalin.');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PetakBukti extends StatelessWidget {
  final Uint8List? bukti;
  final VoidCallback onAmbil;
  final VoidCallback onHapus;

  const _PetakBukti(
      {required this.bukti, required this.onAmbil, required this.onHapus});

  @override
  Widget build(BuildContext context) {
    if (bukti == null) {
      return SizedBox(
        height: 46,
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Unggah Bukti Transfer'),
          onPressed: onAmbil,
        ),
      );
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bukti!,
              height: 180, width: double.infinity, fit: BoxFit.cover),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Ganti'),
              onPressed: onAmbil,
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Hapus'),
              onPressed: onHapus,
            ),
          ],
        ),
      ],
    );
  }
}

class _Kotak extends StatelessWidget {
  final Widget child;

  const _Kotak({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KaataTheme.softFillOf(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}
