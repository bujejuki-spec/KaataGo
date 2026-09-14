import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/paket_langganan_repository.dart';
import '../models/paket_langganan.dart';
import '../theme.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/gambar_bertanda.dart';
import '../widgets/lencana_paket_aktif.dart';
import '../widgets/responsive.dart';
import 'harga_paket_screen.dart';

/// KaataGo Admin memeriksa pengajuan berlangganan.
///
/// Yang menunggu ditaruh di atas dan tidak pernah tertimbun riwayat:
/// merchant yang sudah membayar sedang tidak bisa memakai aplikasinya,
/// dan tiap jam yang lewat di sini adalah jam merchant itu berhenti
/// berjualan.
class PengajuanLanggananScreen extends StatefulWidget {
  const PengajuanLanggananScreen({super.key});

  @override
  State<PengajuanLanggananScreen> createState() =>
      _PengajuanLanggananScreenState();
}

class _PengajuanLanggananScreenState extends State<PengajuanLanggananScreen> {
  final _repo = PaketLanggananRepository();

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _waktu = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

  List<PengajuanLangganan> _semua = const [];
  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final hasil = await _repo.pengajuan();
      if (!mounted) return;
      setState(() {
        _semua = hasil;
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

  Future<void> _setujui(PengajuanLangganan p) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Setujui ${p.namaResto}?'),
        content: Text(
          'Pastikan ${_rp.format(p.harga)} sudah benar-benar masuk ke '
          'rekening KaataGo.\n\n'
          'Setelah disetujui: paket ${p.paket.label} langsung berjalan, '
          'akses menunya disesuaikan otomatis, penagihan bulanannya mulai '
          'hari ini, dan merchant bisa memakai aplikasinya lagi.',
        ),
        actions: [
          DialogActions(
            confirmLabel: 'Sudah masuk, setujui',
            onConfirm: () => Navigator.pop(c, true),
          ),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    await _putuskan(p, true, null);
  }

  Future<void> _tolak(PengajuanLangganan p) async {
    final alasan = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogTolak(),
    );
    if (alasan == null || !mounted) return;
    await _putuskan(p, false, alasan);
  }

  Future<void> _putuskan(
      PengajuanLangganan p, bool setuju, String? alasan) async {
    setState(() => _sibuk = true);
    try {
      await _repo.putuskan(id: p.id, setuju: setuju, alasan: alasan);
      // Lencana paket merchant itu ikut berubah — ingatannya dibuang
      // supaya layarnya tidak menampilkan paket yang sudah lama.
      LencanaPaketAktif.lupakan(p.restoId);
      if (!mounted) return;
      showAppToast(
        context,
        setuju
            ? 'Paket ${p.paket.label} berjalan untuk ${p.namaResto}.'
            : 'Pengajuan ${p.namaResto} ditolak.',
      );
      await _muat();
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final menunggu = _semua.where((p) => p.menunggu).toList();
    final riwayat = _semua.where((p) => !p.menunggu).toList();

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Pengajuan Langganan'),
        actions: [
          // Harganya di sini, bukan di menu tersendiri: yang membuka
          // layar ini sedang mengurus langganan, dan harga paket adalah
          // hal yang sama.
          IconButton(
            icon: const Icon(Icons.sell_outlined),
            tooltip: 'Harga Paket',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const HargaPaketScreen()));
              if (mounted) _muat();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _memuat ? null : _muat,
          ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                  children: [
                    if (_galat != null)
                      Text(_galat!, style: const TextStyle(color: Colors.red)),
                    _Ringkasan(jumlah: menunggu.length),
                    const SizedBox(height: 16),
                    if (menunggu.isEmpty)
                      Text('Tidak ada pengajuan yang menunggu.',
                          style: TextStyle(fontSize: 12.5, color: muted))
                    else
                      for (final p in menunggu)
                        _Kartu(
                          pengajuan: p,
                          rp: _rp,
                          waktu: _waktu,
                          sibuk: _sibuk,
                          onSetujui: () => _setujui(p),
                          onTolak: () => _tolak(p),
                        ),
                    if (riwayat.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text('Riwayat',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: muted)),
                      const SizedBox(height: 8),
                      for (final p in riwayat)
                        _Kartu(
                          pengajuan: p,
                          rp: _rp,
                          waktu: _waktu,
                          sibuk: _sibuk,
                        ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _Ringkasan extends StatelessWidget {
  final int jumlah;

  const _Ringkasan({required this.jumlah});

  @override
  Widget build(BuildContext context) {
    final ada = jumlah > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ada
              ? [const Color(0xFFF59E0B), const Color(0xFFB45309)]
              : [const Color(0xFF10B981), const Color(0xFF0F766E)],
        ),
      ),
      child: Row(
        children: [
          Icon(ada ? Icons.pending_actions : Icons.verified_outlined,
              color: Colors.white, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ada ? '$jumlah pengajuan menunggu' : 'Tidak ada antrean',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  ada
                      ? 'Merchant yang menunggu sedang tidak bisa memakai '
                          'aplikasinya. Janjinya 1×24 jam.'
                      : 'Semua pengajuan sudah diputuskan.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withOpacity(0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kartu extends StatelessWidget {
  final PengajuanLangganan pengajuan;
  final NumberFormat rp;
  final DateFormat waktu;
  final bool sibuk;
  final VoidCallback? onSetujui;
  final VoidCallback? onTolak;

  const _Kartu({
    required this.pengajuan,
    required this.rp,
    required this.waktu,
    required this.sibuk,
    this.onSetujui,
    this.onTolak,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final p = pengajuan;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.namaResto,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('${p.restoId} · ${waktu.format(p.diajukanAt.toLocal())}',
                        style: TextStyle(fontSize: 11.5, color: muted)),
                  ],
                ),
              ),
              LencanaPaket(paket: p.paket, kecil: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(rp.format(p.harga),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text('/bulan', style: TextStyle(fontSize: 12, color: muted)),
              const Spacer(),
              _Status(status: p.status),
            ],
          ),
          if (p.diajukanOleh?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Diajukan ${p.diajukanOleh}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ),
          if (p.catatan?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Catatan: ${p.catatan}',
                  style: TextStyle(fontSize: 12, color: muted)),
            ),
          if (p.alasanTolak?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Ditolak: ${p.alasanTolak}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFB91C1C))),
            ),
          const SizedBox(height: 12),
          // Buktinya ditampilkan, bukan cuma ditautkan. Yang memeriksa
          // puluhan pengajuan tidak akan membuka tautan satu per satu —
          // dan yang tidak dibuka akan disetujui tanpa dilihat.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: GambarBertanda(
                  simpanan: p.buktiUrl, kosong: 'Bukti transfernya tidak ada'),
            ),
          ),
          if (onSetujui != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Tolak'),
                    onPressed: sibuk ? null : onTolak,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Setujui'),
                    onPressed: sibuk ? null : onSetujui,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final String status;

  const _Status({required this.status});

  @override
  Widget build(BuildContext context) {
    final (teks, warna) = switch (status) {
      'selesai' => ('Selesai', const Color(0xFF10B981)),
      'ditolak' => ('Ditolak', const Color(0xFFEF4444)),
      _ => ('Verifikasi', const Color(0xFFF59E0B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: warna.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(teks,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: warna)),
    );
  }
}

class _DialogTolak extends StatefulWidget {
  const _DialogTolak();

  @override
  State<_DialogTolak> createState() => _DialogTolakState();
}

class _DialogTolakState extends State<_DialogTolak> {
  final _alasan = TextEditingController();

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tolak pengajuan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Alasannya ditampilkan ke merchant. Sebutkan apa yang harus '
            'diperbaiki — penolakan tanpa alasan membuat merchant '
            'mengirim ulang bukti yang sama.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _alasan,
            maxLines: 3,
            maxLength: 200,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Alasan',
              hintText: 'Contoh: nominal transfer kurang Rp 50.000',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        DialogActions(
          confirmLabel: 'Tolak',
          destructive: true,
          onConfirm: _alasan.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _alasan.text.trim()),
        ),
      ],
    );
  }
}
