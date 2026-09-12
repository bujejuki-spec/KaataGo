import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/cash_deposit_repository.dart';
import '../utils/akses_menu.dart';
import '../models/cash_deposit.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/field_rules.dart';
import '../utils/gambar_base64.dart';
import '../utils/lebar_web.dart';
import '../utils/pesan_galat.dart';
import '../utils/photo_picker.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

/// Serah terima cash pickup.
///
/// Uang yang dijemput petugas sedang tidak berada di mana pun yang bisa
/// ditunjuk: bukan lagi di laci, belum juga di tangan perusahaan. Layar
/// ini adalah tempat perjalanan itu berakhir — dan selama belum berakhir,
/// barisnya tetap berdiri di bagian atas sebagai pekerjaan yang menunggu.
class TerimaPickupScreen extends StatefulWidget {
  const TerimaPickupScreen({super.key});

  @override
  State<TerimaPickupScreen> createState() => _TerimaPickupScreenState();
}

class _TerimaPickupScreenState extends State<TerimaPickupScreen> {
  final _repo = CashDepositRepository();
  final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _waktu = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

  List<CashDeposit> _pickup = const [];
  bool _memuat = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  String? get _restoId => context.read<AuthProvider>().restoId;

  /// Menerima uang adalah tangan kedua di sepanjang jalannya. Kalau yang
  /// membuat pickup juga yang menyatakannya diterima, tangan keduanya
  /// tidak ada. Servernya menegakkan hal yang sama.
  bool get _boleh {
    final auth = context.read<AuthProvider>();
    return auth.isOwner || auth.isFinance;
  }

  Future<void> _muat() async {
    final restoId = _restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final rows = await _repo.pickup(restoId);
      if (!mounted) return;
      setState(() {
        _pickup = rows;
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

  Future<void> _terima(CashDeposit d) async {
    final hasil = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogTerima(pickup: d),
    );
    if (hasil == true) {
      if (!mounted) return;
      showAppToast(context, 'Cash pickup diterima.');
      _muat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final belum = [
      for (final d in _pickup)
        if (!d.sudahDiterima) d
    ];
    final sudah = [
      for (final d in _pickup)
        if (d.sudahDiterima) d
    ];
    final muted = KaataTheme.mutedOf(context);

    return berdasarkanAkses(
        context,
        'Terima Cash Pickup',
        Scaffold(
          backgroundColor: KaataTheme.backgroundOf(context),
          appBar: AppBar(title: const Text('Terima Cash Pickup')),
          body: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _galat != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 44, color: Colors.red),
                            const SizedBox(height: 12),
                            Text('Gagal memuat: $_galat',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 14),
                            FilledButton(
                                onPressed: _muat,
                                child: const Text('Coba Lagi')),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _muat,
                      child: ResponsiveCenter(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: KaataTheme.softFillOf(context),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.local_shipping_outlined,
                                      size: 18, color: muted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      belum.isEmpty
                                          ? 'Tidak ada uang yang sedang di jalan.'
                                          : '${belum.length} pickup sedang di '
                                              'jalan — ${_rp.format(belum.fold<int>(0, (j, d) => j + d.amount))} '
                                              'sudah keluar laci dan belum diterima.',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text('Menunggu Diterima',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            if (belum.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: Text('Semuanya sudah diterima.',
                                      style: TextStyle(color: muted)),
                                ),
                              )
                            else
                              for (final d in belum)
                                _KartuPickup(
                                  pickup: d,
                                  rp: _rp,
                                  waktu: _waktu,
                                  onTerima: _boleh ? () => _terima(d) : null,
                                ),
                            if (sudah.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              const Text('Sudah Diterima',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              const SizedBox(height: 8),
                              for (final d in sudah)
                                _KartuPickup(
                                    pickup: d,
                                    rp: _rp,
                                    waktu: _waktu,
                                    onTerima: null),
                            ],
                          ],
                        ),
                      ),
                    ),
        ));
  }
}

class _KartuPickup extends StatelessWidget {
  final CashDeposit pickup;
  final NumberFormat rp;
  final DateFormat waktu;
  final VoidCallback? onTerima;

  const _KartuPickup({
    required this.pickup,
    required this.rp,
    required this.waktu,
    required this.onTerima,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final selesai = pickup.sudahDiterima;
    final warna = selesai ? const Color(0xFF10B981) : const Color(0xFFF59E0B);

    // Selisih hitung ditulis apa adanya. Angka yang dipaksa sama dengan
    // catatan awal tidak pernah bisa menemukan apa pun.
    final selisih = pickup.selisihTerima;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(rp.format(pickup.amount),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: warna.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(pickup.statusPickup,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: warna)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Nomor pendeknya, sama dengan yang tertulis di jurnal GL —
            // supaya baris di dua layar bisa ditemukan satu sama lain.
            Text('ID ${pickup.id.substring(0, 8).toUpperCase()}',
                style: TextStyle(fontSize: 11.5, color: muted)),
            const SizedBox(height: 2),
            Text(
                'Dibuat ${waktu.format(pickup.createdAt.toLocal())} · '
                '${pickup.createdBy}',
                style: TextStyle(fontSize: 11.5, color: muted)),
            if (pickup.pickedUpBy != null && pickup.pickedUpBy!.isNotEmpty)
              Text('Dijemput ${pickup.pickedUpBy}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            if (pickup.sealNumber != null && pickup.sealNumber!.isNotEmpty)
              Text('Segel ${pickup.sealNumber}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            // Bukti yang diunggah kasir atau admin saat uangnya dijemput.
            //
            // Tanpa ini, yang menerima uangnya harus percaya pada angka
            // saja — padahal foto kantong dan segelnya itulah satu-
            // satunya hal yang bisa dibandingkan dengan apa yang
            // sekarang ada di tangannya.
            if (pickup.hasProof) ...[
              const SizedBox(height: 10),
              _Bukti(
                judul: 'Bukti pickup dari kasir',
                base64: pickup.proofBase64!,
              ),
            ],
            if (pickup.receiptProof != null &&
                pickup.receiptProof!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Bukti(
                judul: 'Bukti terima',
                base64: pickup.receiptProof!,
              ),
            ],
            if (selesai) ...[
              const Divider(height: 18),
              Text('Diterima ${rp.format(pickup.receivedAmount ?? 0)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (selisih != 0)
                Text(
                  selisih > 0
                      ? 'Lebih ${rp.format(selisih)} dari yang dicatat'
                      : 'Kurang ${rp.format(-selisih)} dari yang dicatat',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDC2626)),
                ),
              Text(
                  'oleh ${pickup.receivedByName ?? pickup.receivedBy ?? '-'} · '
                  '${waktu.format(pickup.receivedAt!.toLocal())}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
              if (pickup.receivedSeal != null &&
                  pickup.receivedSeal!.isNotEmpty)
                Text('Segel diterima ${pickup.receivedSeal}',
                    style: TextStyle(fontSize: 11.5, color: muted)),
            ],
            if (onTerima != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onTerima,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Terima'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Foto bukti, kecil di kartunya dan penuh saat diketuk.
class _Bukti extends StatelessWidget {
  final String judul;
  final String base64;

  const _Bukti({required this.judul, required this.base64});

  @override
  Widget build(BuildContext context) {
    final gambar = byteGambar(base64);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(judul,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: KaataTheme.mutedOf(context))),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: insetDialogWeb(context),
              child: InteractiveViewer(child: Image.memory(gambar)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(gambar,
                width: 72, height: 72, fit: BoxFit.cover),
          ),
        ),
      ],
    );
  }
}

class _DialogTerima extends StatefulWidget {
  final CashDeposit pickup;

  const _DialogTerima({required this.pickup});

  @override
  State<_DialogTerima> createState() => _DialogTerimaState();
}

class _DialogTerimaState extends State<_DialogTerima> {
  final _formKey = GlobalKey<FormState>();
  final _jumlah = TextEditingController();
  final _petugas = TextEditingController();
  final _segel = TextEditingController();
  final _repo = CashDepositRepository();

  Uint8List? _bukti;
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    // Jumlahnya sengaja kosong.
    //
    // Diisi lebih dulu dengan angka kasir, yang menerimanya cukup
    // menekan Terima tanpa menghitung — dan perhitungan ulang itulah
    // satu-satunya alasan layar ini ada. Kotak kosong menuntut
    // angkanya datang dari uang yang benar-benar dihitung.
    _petugas.text = widget.pickup.pickedUpBy ?? '';
    _segel.text = widget.pickup.sealNumber ?? '';
  }

  @override
  void dispose() {
    _jumlah.dispose();
    _petugas.dispose();
    _segel.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_bukti == null) {
      showAppToast(context, 'Bukti terima wajib dilampirkan.', isError: true);
      return;
    }
    setState(() => _menyimpan = true);
    try {
      await _repo.terimaPickup(
        id: widget.pickup.id,
        jumlahDiterima: parseRupiah(_jumlah.text)!,
        namaPetugas: _petugas.text.trim(),
        bukti: base64Encode(_bukti!),
        nomorSeal: _segel.text.trim().isEmpty ? null : _segel.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menerima: ${pesanGalat(e)}', isError: true);
      setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rp =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final muted = KaataTheme.mutedOf(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          // Isinya yang menggulung, bukan seluruh dialognya: tombol
          // Terima yang ikut tergulung jauh ke bawah pada layar ponsel
          // terbaca sebagai tombol yang tidak ada sama sekali.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Terima Cash Pickup',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Uangnya keluar dari GL Cash Pickup dan masuk ke GL Saldo '
                  'Cash Perusahaan begitu ini tersimpan.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: KaataTheme.softFillOf(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'ID ${widget.pickup.id.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text('Dicatat ${rp.format(widget.pickup.amount)}',
                          style: TextStyle(fontSize: 12.5, color: muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _jumlah,
                  decoration: InputDecoration(
                    label: requiredLabel('Jumlah Diterima'),
                    helperText: 'Yang benar-benar dihitung saat menerima',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  validator: (v) {
                    final n = parseRupiah(v ?? '');
                    if (n == null || n <= 0) return 'Wajib diisi, angka > 0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _petugas,
                  decoration:
                      InputDecoration(label: requiredLabel('Nama Petugas')),
                  inputFormatters: nameFormatters,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      validateName(v, label: 'Nama petugas penjemput'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _segel,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Segel (opsional)',
                    helperText: 'Yang terbaca di kantongnya saat diterima',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 14),
                Text('Bukti Terima',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted)),
                const SizedBox(height: 8),
                if (_bukti == null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final dipilih = await pickProofPhoto(context);
                      if (dipilih != null && mounted) {
                        setState(() => _bukti = dipilih);
                      }
                    },
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Ambil Bukti Terima'),
                  )
                else
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_bukti!,
                            width: 58, height: 58, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => setState(() => _bukti = null),
                        child: const Text('Ganti'),
                      ),
                    ],
                  ),
              ],
            ),
                ),
              ),
              const SizedBox(height: 18),
              // Bentuk yang sama dengan dialog lain: yang dikerjakan
              // selebar dialognya di atas, Batal di bawahnya. Dua dialog
              // yang menanyakan hal sejenis dengan susunan tombol
              // berbeda membuat orang membaca ulang tiap kali.
              //
              // Tombolnya hidup meski bukti terimanya belum dilampirkan:
              // tombol mati di ujung formulir panjang terbaca sebagai
              // tombol yang tidak ada, dan yang mencarinya tidak punya
              // cara tahu apa yang kurang. Ditekan tanpa bukti, ia
              // mengatakan apa yang kurang.
              DialogActions(
                confirmLabel: 'Terima',
                busy: _menyimpan,
                onConfirm: _simpan,
                onCancel: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
