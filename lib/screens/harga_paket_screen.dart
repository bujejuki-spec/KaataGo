import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/paket_langganan_repository.dart';
import '../models/paket_langganan.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/pesan_galat.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/lencana_paket_aktif.dart';
import '../widgets/responsive.dart';

/// KaataGo Admin menyetel harga paket.
///
/// Harganya memang disimpan di basis data supaya bisa diubah tanpa
/// merilis APK — tapi selama satu-satunya cara mengubahnya adalah SQL,
/// "bisa diubah" itu cuma berlaku bagi orang yang memegang akses basis
/// data. Layar ini yang membuatnya benar-benar bisa diubah.
class HargaPaketScreen extends StatefulWidget {
  const HargaPaketScreen({super.key});

  @override
  State<HargaPaketScreen> createState() => _HargaPaketScreenState();
}

class _HargaPaketScreenState extends State<HargaPaketScreen> {
  final _repo = PaketLanggananRepository();

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<InfoPaket> _paket = const [];
  final _harga = <Paket, TextEditingController>{};
  final _keterangan = <Paket, TextEditingController>{};

  bool _memuat = true;
  bool _menyimpan = false;
  String? _galat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  @override
  void dispose() {
    for (final c in [..._harga.values, ..._keterangan.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final hasil = await _repo.daftarPaket();
      if (!mounted) return;
      setState(() {
        _paket = hasil;
        for (final p in hasil) {
          _harga[p.paket] =
              TextEditingController(text: formatRupiahInput(p.harga));
          _keterangan[p.paket] = TextEditingController(text: p.keterangan);
        }
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

  Future<void> _simpan(InfoPaket info) async {
    final harga = parseRupiah(_harga[info.paket]?.text ?? '') ?? 0;
    final keterangan = _keterangan[info.paket]?.text.trim() ?? '';

    if (harga <= 0) {
      showAppToast(context, 'Harganya harus lebih dari nol.', isError: true);
      return;
    }
    if (keterangan.isEmpty) {
      showAppToast(context, 'Keterangannya jangan dikosongkan — inilah yang '
          'dibaca merchant saat memilih.', isError: true);
      return;
    }

    setState(() => _menyimpan = true);
    try {
      await _repo.simpanHarga(
        paket: info.paket,
        harga: harga,
        keterangan: keterangan,
        oleh: context.read<AuthProvider>().user?.email ?? '',
      );
      // Lencana dan layar pilih paket membaca angka ini — ingatannya
      // dibuang supaya harganya tidak tertinggal satu versi.
      LencanaPaketAktif.lupakan();
      if (!mounted) return;
      showAppToast(context, 'Harga ${info.paket.label} tersimpan.');
      await _muat();
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Harga Paket')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                children: [
                  if (_galat != null)
                    Text(_galat!, style: const TextStyle(color: Colors.red)),
                  _Pengantar(),
                  const SizedBox(height: 16),
                  for (final p in _paket)
                    _KartuHarga(
                      info: p,
                      rp: _rp,
                      harga: _harga[p.paket]!,
                      keterangan: _keterangan[p.paket]!,
                      menyimpan: _menyimpan,
                      onSimpan: () => _simpan(p),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Menu apa saja yang dibuka tiap paket ditentukan di '
                    'server, bukan di sini. Yang bisa diubah dari layar ini '
                    'harganya dan kalimat yang dibaca merchant.',
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: muted),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Yang paling mudah disalahpahami tentang layar ini, disebut di depan.
class _Pengantar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.tintOf(context, Colors.blue),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: KaataTheme.onTintOf(context, Colors.blue)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Harga baru hanya berlaku untuk yang berlangganan setelah ini. '
              'Merchant yang sudah berjalan tetap dibayar dengan harga yang '
              'disepakati waktu itu — mengubahnya dari sini tidak menaikkan '
              'tagihan siapa pun.\n\n'
              'Untuk menaikkan harga merchant tertentu, ubah harganya di '
              'Billing Merchant.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: KaataTheme.onTintOf(context, Colors.blue)),
            ),
          ),
        ],
      ),
    );
  }
}

class _KartuHarga extends StatelessWidget {
  final InfoPaket info;
  final NumberFormat rp;
  final TextEditingController harga;
  final TextEditingController keterangan;
  final bool menyimpan;
  final VoidCallback onSimpan;

  const _KartuHarga({
    required this.info,
    required this.rp,
    required this.harga,
    required this.keterangan,
    required this.menyimpan,
    required this.onSimpan,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
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
              LencanaPaket(paket: info.paket),
              const Spacer(),
              Text('sekarang ${rp.format(info.harga)}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: harga,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Harga per bulan',
              prefixText: 'Rp ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: keterangan,
            maxLines: 3,
            maxLength: 240,
            decoration: const InputDecoration(
              labelText: 'Keterangan',
              helperText: 'Kalimat yang dibaca merchant saat memilih paket',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: warnaPaket(info.paket)),
              icon: menyimpan
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 16),
              label: Text('Simpan ${info.paket.label}'),
              onPressed: menyimpan ? null : onSimpan,
            ),
          ),
        ],
      ),
    );
  }
}
