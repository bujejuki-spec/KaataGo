import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/voucher_payout_repository.dart';
import '../models/voucher_payout.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/akses_menu.dart';
import '../utils/periode_laporan.dart';
import '../utils/pesan_galat.dart';
import '../widgets/responsive.dart';

/// Yang dibayarkan KaataGo ke merchant ini.
///
/// Pelanggan menebus voucher KaataGo di sini: restonya menyerahkan
/// makanan dan menerima nol rupiah dari pelanggan, jadi KaataGo yang
/// menggantinya. Uangnya sudah lama berjalan sendiri — lewat antrean
/// pencairan ke sub-akun restonya — tapi sampai sekarang merchant tidak
/// punya satu halaman pun untuk memeriksanya. Yang ada cuma baris
/// jurnal, dan tidak ada yang membaca jurnal untuk menanyakan haknya.
///
/// Layar ini menjawab tiga pertanyaan yang selama ini tidak bisa
/// ditanyakan: berapa yang ditebus di tempat saya, berapa yang sudah
/// dibayar, dan berapa yang masih menggantung.
class PembayaranKaataGoScreen extends StatefulWidget {
  const PembayaranKaataGoScreen({super.key});

  @override
  State<PembayaranKaataGoScreen> createState() =>
      _PembayaranKaataGoScreenState();
}

class _PembayaranKaataGoScreenState extends State<PembayaranKaataGoScreen> {
  final _repo = VoucherPayoutRepository();
  final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _waktu = DateFormat('d MMM yyyy, HH:mm', 'id_ID');
  final _tanggal = DateFormat('dd MMM yyyy', 'id_ID');

  DateTime _mulai = DateTime.now().subtract(const Duration(days: 29));
  DateTime _akhir = DateTime.now();

  List<VoucherPayout> _baris = const [];
  bool _memuat = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  String? get _restoId => context.read<AuthProvider>().restoId;

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
      final rows = await _repo.untukResto(
        restoId,
        mulai: DateTime(_mulai.year, _mulai.month, _mulai.day),
        akhir: DateTime(_akhir.year, _akhir.month, _akhir.day, 23, 59, 59),
      );
      if (!mounted) return;
      setState(() {
        _baris = rows;
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

  Future<void> _pilihPeriode() async {
    final dipilih =
        await pilihPeriodeLaporan(context, mulai: _mulai, akhir: _akhir);
    if (dipilih == null) return;
    setState(() {
      _mulai = dipilih.start;
      _akhir = dipilih.end;
    });
    _muat();
  }

  int get _total => _baris.fold(0, (j, b) => j + b.amount);
  int get _sudah =>
      _baris.where((b) => b.terkirim).fold(0, (j, b) => j + b.amount);
  int get _belum =>
      _baris.where((b) => b.belumSampai).fold(0, (j, b) => j + b.amount);

  @override
  Widget build(BuildContext context) {
    return berdasarkanAkses(
      context,
      'Pembayaran dari KaataGo',
      Scaffold(
        backgroundColor: KaataTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Pembayaran dari KaataGo'),
          actions: [
            IconButton(
              icon: const Icon(Icons.date_range),
              tooltip: 'Pilih periode',
              onPressed: _memuat ? null : _pilihPeriode,
            ),
          ],
        ),
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
                              onPressed: _muat, child: const Text('Coba Lagi')),
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
                          InkWell(
                            onTap: _pilihPeriode,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.date_range, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_tanggal.format(_mulai)} — '
                                      '${_tanggal.format(_akhir)}',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const Text('Ubah',
                                      style: TextStyle(fontSize: 12.5)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _KartuTotal(total: _total, rp: _rp),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _KartuKecil(
                                  ikon: Icons.check_circle_outline,
                                  judul: 'Sudah dibayar',
                                  nilai: _rp.format(_sudah),
                                  warna: const Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _KartuKecil(
                                  ikon: Icons.hourglass_bottom,
                                  judul: 'Masih menggantung',
                                  nilai: _rp.format(_belum),
                                  warna: _belum > 0
                                      ? const Color(0xFFF59E0B)
                                      : KaataTheme.mutedOf(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: KaataTheme.softFillOf(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Voucher KaataGo yang ditebus pelanggan di sini '
                              'dibayarkan KaataGo ke akun pembayaran merchant. '
                              'Dari sana dananya ikut jadwal pencairan '
                              'merchant sendiri, ke rekening yang didaftarkan '
                              'sendiri.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: KaataTheme.mutedOf(context)),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text('Rincian',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          if (_baris.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  'Belum ada voucher KaataGo yang ditebus di '
                                  'periode ini.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: KaataTheme.mutedOf(context)),
                                ),
                              ),
                            )
                          else
                            for (final b in _baris)
                              _Baris(baris: b, rp: _rp, waktu: _waktu),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _KartuTotal extends StatelessWidget {
  final int total;
  final NumberFormat rp;

  const _KartuTotal({required this.total, required this.rp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF3730A3)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Voucher ditebus di periode ini',
              style: TextStyle(color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 6),
          Text(rp.format(total),
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _KartuKecil extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String nilai;
  final Color warna;

  const _KartuKecil({
    required this.ikon,
    required this.judul,
    required this.nilai,
    required this.warna,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: warna),
          const SizedBox(height: 8),
          Text(judul,
              style:
                  TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context))),
          const SizedBox(height: 2),
          Text(nilai,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _Baris extends StatelessWidget {
  final VoucherPayout baris;
  final NumberFormat rp;
  final DateFormat waktu;

  const _Baris({required this.baris, required this.rp, required this.waktu});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final warna = baris.terkirim
        ? const Color(0xFF10B981)
        : baris.gagal
            ? const Color(0xFFDC2626)
            : const Color(0xFFF59E0B);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(rp.format(baris.amount),
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
                  child: Text(baris.labelStatus,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: warna)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Ditebus ${waktu.format(baris.createdAt.toLocal())}',
                style: TextStyle(fontSize: 11.5, color: muted)),
            if (baris.sentAt != null)
              Text('Dibayar ${waktu.format(baris.sentAt!.toLocal())}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            // Nomor transfernya ikut ditulis: itu yang dipakai
            // mencocokkan baris ini dengan mutasi di akun pembayaran,
            // tanpa menebak-nebak.
            if (baris.transferId != null && baris.transferId!.isNotEmpty)
              Text('No. transfer ${baris.transferId}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            // Yang gagal menyebutkan sebabnya, apa adanya dari penyedia.
            // Merchant yang menanyakannya besok pagi berhak tahu apa
            // yang sedang ditunggu.
            if (baris.gagal &&
                baris.lastError != null &&
                baris.lastError!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Akan dicoba lagi. ${baris.lastError}',
                style: const TextStyle(
                    fontSize: 11.5, color: Color(0xFFDC2626)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
