import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/paket_langganan_repository.dart';
import '../models/paket_langganan.dart';
import '../theme.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/gambar_bertanda.dart';
import '../widgets/kotak_cari.dart';
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
  static final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

  List<PengajuanLangganan> _semua = const [];
  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  final _cari = TextEditingController();
  String _kata = '';

  /// Rentang riwayat yang sedang dilihat. Bawaannya hari ini saja.
  ///
  /// Riwayat sebulan penuh terbuka tiap kali layar ini dibuka berarti
  /// pengajuan yang MENUNGGU — satu-satunya yang benar-benar butuh
  /// seseorang — harus dicari di antara puluhan baris yang sudah
  /// selesai. Yang lewat dari hari ini tetap bisa dibuka, tapi dimintai
  /// dulu.
  late DateTimeRange _rentang = _hariIni();

  static DateTimeRange _hariIni() {
    final k = DateTime.now();
    final h = DateTime(k.year, k.month, k.day);
    return DateTimeRange(start: h, end: h);
  }

  bool _diRentang(DateTime t) {
    final l = t.toLocal();
    final hari = DateTime(l.year, l.month, l.day);
    return !hari.isBefore(_rentang.start) && !hari.isAfter(_rentang.end);
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _pilihRentang() async {
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _rentang,
      helpText: 'Periode riwayat',
      saveText: 'Terapkan',
    );
    if (hasil == null || !mounted) return;
    setState(() => _rentang = hasil);
  }

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
    // Pencarian berlaku untuk keduanya — yang dicari nama merchant,
    // dan yang mencarinya tidak tahu lebih dulu pengajuan itu sudah
    // diputuskan atau belum.
    bool cocok(PengajuanLangganan p) =>
        cocokCari(_kata, [p.namaResto, p.restoId]);

    // Yang menunggu TIDAK ikut disaring periode.
    //
    // Ia pekerjaan yang belum selesai, bukan riwayat. Pengajuan yang
    // masuk kemarin dan belum diputuskan tetap harus terlihat hari ini
    // — kalau ia ikut hilang bersama tanggalnya, yang hilang adalah
    // merchant yang sedang tidak bisa berjualan.
    final menunggu = _semua.where((p) => p.menunggu && cocok(p)).toList();
    final riwayat = _semua
        .where((p) => !p.menunggu && cocok(p) && _diRentang(p.diajukanAt))
        .toList();

    final satuHari = _rentang.start == _rentang.end;
    final labelRentang = satuHari
        ? (_rentang.start == _hariIni().start
            ? 'Hari ini'
            : _tanggal.format(_rentang.start))
        : '${_tanggal.format(_rentang.start)} – '
            '${_tanggal.format(_rentang.end)}';

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
                    const SizedBox(height: 14),
                    KotakCari(
                      controller: _cari,
                      petunjuk: 'Cari nama merchant',
                      onUbah: (v) => setState(() => _kata = v),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 14),
                    if (menunggu.isEmpty)
                      Text(
                          _kata.isEmpty
                              ? 'Tidak ada pengajuan yang menunggu.'
                              : 'Tidak ada pengajuan menunggu yang cocok '
                                  'dengan "$_kata".',
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
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Text('Riwayat',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: muted)),
                        const Spacer(),
                        // Periodenya disebut di tombolnya sendiri.
                        //
                        // Daftar yang kosong tanpa menyebut sedang
                        // menampilkan tanggal berapa terbaca sebagai
                        // "tidak ada apa-apa", padahal yang benar
                        // "tidak ada apa-apa HARI INI".
                        OutlinedButton.icon(
                          onPressed: _pilihRentang,
                          icon: const Icon(Icons.calendar_today, size: 15),
                          label: Text(labelRentang,
                              style: const TextStyle(fontSize: 12.5)),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                          ),
                        ),
                        if (!satuHari || _rentang.start != _hariIni().start)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: IconButton(
                              icon: const Icon(Icons.today, size: 18),
                              tooltip: 'Kembali ke hari ini',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => _rentang = _hariIni()),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (riwayat.isEmpty)
                      Text(
                          'Tidak ada pengajuan yang diputuskan pada '
                          '${labelRentang.toLowerCase()}.',
                          style: TextStyle(fontSize: 12.5, color: muted))
                    else
                      for (final p in riwayat)
                        _Kartu(
                          pengajuan: p,
                          rp: _rp,
                          waktu: _waktu,
                          sibuk: _sibuk,
                        ),
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

class _Kartu extends StatefulWidget {
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
  State<_Kartu> createState() => _KartuState();
}

class _KartuState extends State<_Kartu> {
  /// Buktinya terbuka untuk yang MENUNGGU, terlipat untuk riwayat.
  ///
  /// Keduanya bukan pekerjaan yang sama. Yang menunggu memang datang
  /// untuk dilihat buktinya — melipatnya berarti menambah satu ketukan
  /// di depan hal yang harus diperiksa, dan yang butuh ketukan tambahan
  /// akan disetujui tanpa dilihat.
  ///
  /// Riwayat sudah diputuskan. Gambar setinggi 200 piksel untuk tiap
  /// baris yang sudah selesai membuat daftar sepuluh pengajuan sepanjang
  /// dua ribu piksel, dan yang dicari orang di riwayat biasanya cuma
  /// satu nama.
  late bool _terbuka = widget.onSetujui != null;

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final p = widget.pengajuan;
    final rp = widget.rp;
    final waktu = widget.waktu;
    final sibuk = widget.sibuk;
    final onSetujui = widget.onSetujui;
    final onTolak = widget.onTolak;

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
          //
          // Yang bisa dilipat cuma tingginya. Judulnya tetap menyebut
          // buktinya ada, jadi yang terlipat tidak pernah terbaca
          // sebagai pengajuan tanpa bukti.
          InkWell(
            onTap: () => setState(() => _terbuka = !_terbuka),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Text('Bukti transfer',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                  const Spacer(),
                  Icon(_terbuka ? Icons.expand_less : Icons.expand_more,
                      size: 19, color: muted),
                ],
              ),
            ),
          ),
          if (_terbuka) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: GambarBertanda(
                    simpanan: p.buktiUrl,
                    kosong: 'Bukti transfernya tidak ada'),
              ),
            ),
          ],
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
