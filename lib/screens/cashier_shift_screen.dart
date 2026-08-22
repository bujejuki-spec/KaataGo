import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/cashier_shift_repository.dart';
import '../models/cashier_shift.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';

/// Tutup Shift Kasir — satu momen yang berbunyi "uang di laci dihitung
/// sekarang, dan segini isinya".
///
/// Saldo Cash di layar Saldo & Pengeluaran sudah lama benar secara
/// pembukuan, tapi tidak seorang pun pernah membandingkannya dengan uang
/// yang benar-benar ada. Selisih baru ketahuan saat rekonsiliasi
/// bulanan, dan pada saat itu tidak ada lagi yang ingat hari mana,
/// apalagi siapa yang memegang lacinya.
class CashierShiftScreen extends StatefulWidget {
  const CashierShiftScreen({super.key});

  @override
  State<CashierShiftScreen> createState() => _CashierShiftScreenState();
}

class _CashierShiftScreenState extends State<CashierShiftScreen> {
  final _repo = CashierShiftRepository();

  CashierShift? _terbuka;
  List<CashierShift> _riwayat = const [];
  bool _memuat = true;
  bool _sibuk = false;

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _waktu = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  String? get _restoId => context.read<AuthProvider>().restoId;

  Future<void> _muat() async {
    final restoId = _restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    try {
      final hasil = await Future.wait([
        _repo.terbuka(restoId),
        _repo.riwayat(restoId),
      ]);
      if (!mounted) return;
      setState(() {
        _terbuka = hasil[0] as CashierShift?;
        _riwayat = hasil[1] as List<CashierShift>;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat shift: $e', isError: true);
    }
  }

  Future<void> _buka() async {
    final restoId = _restoId;
    if (restoId == null) return;

    final jawab = await _tanyaRupiah(
      judul: 'Buka Shift',
      keterangan: 'Berapa uang yang sudah ada di laci sekarang? Biasanya '
          'uang kembalian yang ditinggal shift sebelumnya. Kosongkan '
          'kalau lacinya benar-benar kosong.',
      label: 'Modal Awal Laci',
      tombol: 'Buka Shift',
      bolehNol: true,
    );
    if (jawab == null || !mounted) return;

    setState(() => _sibuk = true);
    try {
      await _repo.buka(restoId: restoId, modalAwal: jawab.jumlah);
      if (!mounted) return;
      showAppToast(context, 'Shift dibuka.');
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, _pesan(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _tutup() async {
    final shift = _terbuka;
    if (shift == null) return;

    // Sengaja tidak menampilkan angka yang seharusnya.
    //
    // Kasir yang tahu lebih dulu "seharusnya Rp 1.240.000" akan
    // menghitung sampai ketemu angka itu, bukan menghitung apa adanya.
    // Selisih yang tidak pernah muncul bukan berarti tidak ada — ia cuma
    // pindah ke bulan depan, dan ke orang yang tidak melakukannya.
    // Ditanya, ditunjukkan selisihnya, lalu boleh diperbaiki — berulang
    // sampai kasirnya yakin.
    //
    // Salah ketik satu angka nol pada nominal yang dihitung akan
    // tercatat selamanya sebagai selisih jutaan rupiah atas nama orang
    // yang tidak melakukan apa-apa. Menutup shift tidak bisa dibatalkan,
    // jadi kesempatan memperbaikinya harus ada SEBELUM disimpan.
    ({int jumlah, String? catatan})? jawab;
    var awal = 0;

    while (true) {
      jawab = await _tanyaRupiah(
        judul: 'Tutup Shift',
        keterangan: 'Hitung semua uang di laci sekarang, lalu tulis '
            'jumlahnya apa adanya. Selisihnya ditunjukkan sesudah ini, '
            'dan masih bisa diperbaiki sebelum disimpan.',
        label: 'Uang di Laci',
        tombol: 'Lanjut',
        pakaiCatatan: true,
        nilaiAwal: awal,
      );
      if (jawab == null || !mounted) return;

      final int perkiraan;
      try {
        perkiraan = await _repo.perkiraan(shift.id);
      } catch (e) {
        if (!mounted) return;
        showAppToast(context, _pesan(e), isError: true);
        return;
      }
      if (!mounted) return;

      final lanjut = await _konfirmasiSelisih(
        dihitung: jawab.jumlah,
        seharusnya: perkiraan,
      );
      if (lanjut == null || !mounted) return;
      if (lanjut) break;

      // Diperbaiki — kolomnya dibuka lagi berisi angka tadi, bukan
      // kosong. Yang salah ketik satu digit tidak perlu mengetik ulang
      // seluruhnya.
      awal = jawab.jumlah;
    }

    setState(() => _sibuk = true);
    try {
      final hasil = await _repo.tutup(
        shiftId: shift.id,
        uangDihitung: jawab.jumlah,
        catatan: jawab.catatan,
      );
      if (!mounted) return;
      await _muat();
      if (!mounted) return;
      await _tampilkanHasil(hasil);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, _pesan(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  /// Menunjukkan selisihnya sebelum disimpan, dan menawarkan perbaikan.
  ///
  /// Mengembalikan true untuk lanjut menutup, false untuk memperbaiki
  /// nominalnya, dan null kalau dibatalkan sama sekali.
  Future<bool?> _konfirmasiSelisih({
    required int dihitung,
    required int seharusnya,
  }) async {
    final selisih = dihitung - seharusnya;
    final warna = selisih == 0
        ? const Color(0xFF10B981)
        : (selisih < 0 ? Colors.red : const Color(0xFFF59E0B));

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(selisih == 0 ? 'Uangnya pas' : 'Ada selisih'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BarisAngka(label: 'Seharusnya', nilai: seharusnya),
            _BarisAngka(label: 'Kamu hitung', nilai: dihitung),
            const Divider(height: 20),
            _BarisAngka(
              label: selisih < 0
                  ? 'Kurang'
                  : (selisih > 0 ? 'Lebih' : 'Selisih'),
              nilai: selisih.abs(),
              tebal: true,
              warna: warna,
            ),
            const SizedBox(height: 12),
            Text(
              selisih == 0
                  ? 'Setelah ditutup, shift ini tidak bisa dibuka lagi.'
                  : 'Periksa dulu nominalnya — salah ketik satu angka nol '
                      'akan tercatat selamanya sebagai selisih atas namamu. '
                      'Kalau memang segitu hitungannya, lanjutkan saja.',
              style: TextStyle(
                  fontSize: 12, color: KaataTheme.mutedOf(dialogContext)),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Ya, Tutup Shift',
            cancelLabel: 'Perbaiki Nominal',
            destructive: selisih != 0,
            onConfirm: () => Navigator.pop(dialogContext, true),
            onCancel: () => Navigator.pop(dialogContext, false),
          ),
        ],
      ),
    );
  }

  /// Pesan galat dari Postgres datang dengan bungkusnya. Yang dibaca
  /// kasir harus kalimatnya, bukan nama fungsi dan kode SQLSTATE.
  String _pesan(Object e) {
    final teks = e.toString();
    final i = teks.indexOf('message: ');
    if (i >= 0) {
      final sisa = teks.substring(i + 9);
      final akhir = sisa.indexOf(', code:');
      return akhir > 0 ? sisa.substring(0, akhir) : sisa;
    }
    return teks;
  }

  Future<void> _tampilkanHasil(CashierShift s) async {
    final selisih = s.difference ?? 0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.pas ? 'Uangnya pas' : 'Ada selisih'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BarisAngka(label: 'Seharusnya', nilai: s.expectedCash ?? 0),
            _BarisAngka(label: 'Dihitung', nilai: s.countedCash ?? 0),
            const Divider(height: 20),
            _BarisAngka(
              label: selisih < 0 ? 'Kurang' : (selisih > 0 ? 'Lebih' : 'Selisih'),
              nilai: selisih.abs(),
              tebal: true,
              warna: selisih == 0
                  ? const Color(0xFF10B981)
                  : (selisih < 0 ? Colors.red : const Color(0xFFF59E0B)),
            ),
            if (!s.pas) ...[
              const SizedBox(height: 12),
              Text(
                selisih < 0
                    ? 'Uangnya kurang dari yang tercatat. Laporkan ke '
                        'Finance hari ini juga, selagi masih ingat '
                        'transaksinya.'
                    : 'Uangnya lebih dari yang tercatat. Biasanya ada '
                        'penjualan yang belum diinput, atau kembalian '
                        'yang belum diberikan.',
                style: TextStyle(
                    fontSize: 12, color: KaataTheme.mutedOf(dialogContext)),
              ),
            ],
          ],
        ),
        // Tanpa tombol batal: hasilnya sudah tersimpan, dan tidak ada
        // yang bisa dibatalkan dari sini.
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Mengerti'),
            ),
          ),
        ],
      ),
    );
  }

  /// Satu kolom rupiah, dan — kalau [pakaiCatatan] — satu kolom catatan.
  ///
  /// Null berarti dibatalkan. Bertipe tegas, tidak `dynamic`: tombol
  /// Batal bawaan [DialogActions] menutup dialog dengan nilai `false`,
  /// dan pada tipe longgar nilai itu lolos sebagai jawaban — lalu jatuh
  /// jauh di dalam, sebagai "type 'bool' is not a subtype of type 'int'"
  /// yang tidak menyebut-nyebut tombol Batal sama sekali.
  Future<({int jumlah, String? catatan})?> _tanyaRupiah({
    required String judul,
    required String keterangan,
    required String label,
    required String tombol,
    bool bolehNol = false,
    bool pakaiCatatan = false,
    int nilaiAwal = 0,
  }) async {
    final ctrl = TextEditingController(
        text: nilaiAwal == 0 ? '' : formatRupiahInput(nilaiAwal));
    final catatan = TextEditingController();

    final hasil = await showDialog<({int jumlah, String? catatan})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(judul),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(keterangan,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: KaataTheme.mutedOf(dialogContext))),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: InputDecoration(
                  labelText: label,
                  prefixText: 'Rp ',
                ),
              ),
              if (pakaiCatatan) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: catatan,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    hintText: 'Misal: ada pengembalian ke pelanggan',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          DialogActions(
            confirmLabel: tombol,
            // Ditulis sendiri supaya membatalkan berarti null, bukan
            // `false` — lihat catatan di atas.
            onCancel: () => Navigator.pop(dialogContext),
            onConfirm: () {
              final n = parseRupiah(ctrl.text) ?? (bolehNol ? 0 : -1);
              if (n < 0) {
                showAppToast(dialogContext, 'Isi jumlahnya dulu.',
                    isError: true);
                return;
              }
              final tulisan = catatan.text.trim();
              Navigator.pop(dialogContext,
                  (jumlah: n, catatan: tulisan.isEmpty ? null : tulisan));
            },
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );

    ctrl.dispose();
    catatan.dispose();
    return hasil;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Shift Kasir')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _kartuShift(),
                    const SizedBox(height: 20),
                    const Text('Riwayat Shift',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    if (_riwayat.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('Belum ada shift yang ditutup.',
                              style:
                                  TextStyle(color: KaataTheme.mutedOf(context))),
                        ),
                      )
                    else
                      for (final s in _riwayat) _BarisRiwayat(shift: s),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _kartuShift() {
    final s = _terbuka;
    final muted = KaataTheme.mutedOf(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(
          color: s == null
              ? KaataTheme.borderOf(context)
              : const Color(0xFF10B981),
          width: s == null ? 1 : 1.5,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                s == null ? Icons.lock_outline : Icons.point_of_sale,
                size: 18,
                color: s == null ? muted : const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              Text(
                s == null ? 'Tidak ada shift terbuka' : 'Shift sedang berjalan',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s == null)
            Text(
              'Buka shift sebelum mulai melayani, supaya uang di laci '
              'punya titik awal yang jelas.',
              style: TextStyle(fontSize: 12.5, color: muted),
            )
          else ...[
            Text(s.namaTampil,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Dibuka ${_waktu.format(s.openedAt.toWib())}',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 2),
            Text('Modal awal ${_rp.format(s.openingCash)}',
                style: TextStyle(fontSize: 12, color: muted)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: s == null
                ? FilledButton.icon(
                    onPressed: _sibuk ? null : _buka,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Buka Shift'),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626)),
                    onPressed: _sibuk ? null : _tutup,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Tutup Shift'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BarisAngka extends StatelessWidget {
  final String label;
  final int nilai;
  final bool tebal;
  final Color? warna;

  const _BarisAngka({
    required this.label,
    required this.nilai,
    this.tebal = false,
    this.warna,
  });

  @override
  Widget build(BuildContext context) {
    final rp =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: tebal ? 14 : 13,
                  fontWeight: tebal ? FontWeight.bold : FontWeight.normal)),
          Text(
            rp.format(nilai),
            style: TextStyle(
              fontSize: tebal ? 15 : 13,
              fontWeight: FontWeight.bold,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarisRiwayat extends StatelessWidget {
  final CashierShift shift;

  const _BarisRiwayat({required this.shift});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final rp =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final tgl = DateFormat('d MMM, HH:mm', 'id_ID');
    final selisih = shift.difference ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(shift.namaTampil,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (selisih == 0
                          ? const Color(0xFF10B981)
                          : (selisih < 0
                              ? Colors.red
                              : const Color(0xFFF59E0B)))
                      .withOpacity(0.13),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  selisih == 0
                      ? 'Pas'
                      : '${selisih < 0 ? 'Kurang' : 'Lebih'} '
                          '${rp.format(selisih.abs())}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selisih == 0
                        ? const Color(0xFF047857)
                        : (selisih < 0
                            ? Colors.red.shade700
                            : const Color(0xFFB45309)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${tgl.format(shift.openedAt.toWib())} — '
            '${shift.closedAt == null ? '' : tgl.format(shift.closedAt!.toWib())}',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
          const SizedBox(height: 3),
          Text(
            'Seharusnya ${rp.format(shift.expectedCash ?? 0)} • '
            'Dihitung ${rp.format(shift.countedCash ?? 0)}',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
          if ((shift.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(shift.note!,
                style: const TextStyle(fontSize: 12, height: 1.3)),
          ],
        ],
      ),
    );
  }
}
