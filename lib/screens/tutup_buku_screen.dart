import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/settlement_repository.dart';
import '../models/settlement.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';

/// Tutup buku harian.
///
/// Satu momen yang berbunyi "hari ini selesai, angkanya segini".
/// Sebelumnya tidak ada momen itu sama sekali — yang ada cuma aliran,
/// dan pertanyaan "kemarin sudah cocok belum?" hanya bisa dijawab
/// dengan menghitung ulang semuanya.
class TutupBukuScreen extends StatefulWidget {
  const TutupBukuScreen({super.key});

  @override
  State<TutupBukuScreen> createState() => _TutupBukuScreenState();
}

class _TutupBukuScreenState extends State<TutupBukuScreen> {
  final _repo = SettlementRepository();

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _tgl = DateFormat('EEEE, d MMM yyyy', 'id_ID');

  List<DailySettlement> _riwayat = const [];

  /// Kemarin, dihitung ulang tiap layar dibuka.
  ///
  /// Bukan hari ini: hari yang belum selesai masih akan bertambah sampai
  /// malam, dan membekukan angkanya pukul dua siang menghasilkan selisih
  /// besok yang terlihat seperti uang hilang. Servernya menolak juga.
  DailySettlement? _kemarin;

  bool _memuat = true;
  bool _sibuk = false;

  String? get _restoId => context.read<AuthProvider>().restoId;

  DateTime get _tanggalKemarin {
    final kini = DateTime.now().toWib();
    return DateTime(kini.year, kini.month, kini.day)
        .subtract(const Duration(days: 1));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  Future<void> _muat() async {
    final restoId = _restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    try {
      final hasil = await Future.wait([
        _repo.riwayat(restoId),
        _repo.hitung(restoId, _tanggalKemarin),
      ]);
      if (!mounted) return;
      setState(() {
        _riwayat = hasil[0] as List<DailySettlement>;
        _kemarin = hasil[1] as DailySettlement;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat: ${pesanGalat(e)}', isError: true);
    }
  }

  bool get _kemarinSudahDitutup =>
      _riwayat.any((s) =>
          s.ditutup &&
          s.settledOn.year == _tanggalKemarin.year &&
          s.settledOn.month == _tanggalKemarin.month &&
          s.settledOn.day == _tanggalKemarin.day);

  Future<void> _tutup() async {
    final hitungan = _kemarin;
    if (hitungan == null) return;

    final catatan = TextEditingController();
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Tutup Buku Kemarin?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tgl.format(_tanggalKemarin)),
              const SizedBox(height: 10),
              Text(
                'Angkanya dibekukan apa adanya saat ini. Koreksi pesanan '
                'sesudah ini tidak mengubah angka bekunya — ia akan '
                'terlihat sebagai selisih, dan itu memang yang diinginkan.',
                style: TextStyle(
                    fontSize: 12.5, color: KaataTheme.mutedOf(d)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: catatan,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  hintText: 'Misal: selisih QRIS menunggu pencairan',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          DialogActions(
            confirmLabel: 'Tutup Buku',
            onCancel: () => Navigator.pop(d, false),
            onConfirm: () => Navigator.pop(d, true),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
    final isiCatatan = catatan.text.trim();
    catatan.dispose();
    if (lanjut != true || !mounted) return;

    final restoId = _restoId;
    if (restoId == null) return;
    setState(() => _sibuk = true);
    try {
      await _repo.tutup(restoId, _tanggalKemarin,
          catatan: isiCatatan.isEmpty ? null : isiCatatan);
      await _muat();
      if (!mounted) return;
      showAppToast(context, 'Buku kemarin ditutup.');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _bukaLagi(DailySettlement s) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Buka Kembali?'),
        content: const Text(
          'Angka bekunya tetap tersimpan — yang berubah cuma statusnya, '
          'supaya hari itu bisa ditutup ulang setelah datanya lengkap.\n\n'
          'Biasanya dipakai kalau bukunya ditutup sebelum pencairan '
          'gateway-nya masuk.',
        ),
        actions: [
          DialogActions(
            confirmLabel: 'Buka Kembali',
            onCancel: () => Navigator.pop(d, false),
            onConfirm: () => Navigator.pop(d, true),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
    if (yakin != true || !mounted) return;

    final restoId = _restoId;
    if (restoId == null) return;
    setState(() => _sibuk = true);
    try {
      await _repo.buka(restoId, s.settledOn);
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutup Buku')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    if (_kemarin != null && !_kemarinSudahDitutup)
                      _kartuKemarin(_kemarin!),
                    if (_kemarinSudahDitutup)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: KaataTheme.tintOf(context, Colors.green),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: Color(0xFF10B981)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Buku ${_tgl.format(_tanggalKemarin)} sudah '
                                'ditutup.',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 22),
                    const Text('Riwayat Tutup Buku',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    if (_riwayat.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('Belum ada hari yang ditutup.',
                              style: TextStyle(
                                  color: KaataTheme.mutedOf(context))),
                        ),
                      ),
                    for (final s in _riwayat) _kartuRiwayat(s),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _kartuKemarin(DailySettlement s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KaataTheme.brand, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Belum Ditutup',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: KaataTheme.brand)),
          const SizedBox(height: 2),
          Text(_tgl.format(s.settledOn),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15.5)),
          const SizedBox(height: 12),
          _baris('Tunai', s.cashExpected, s.cashCounted),
          _baris('QRIS Dinamis', s.qrisExpected, s.qrisSettled + s.gatewayFee),
          _baris('QRIS Statis', s.qrisStaticExpected, s.qrisStaticSettled),
          _baris('Transfer', s.transferExpected, s.transferSettled),
          const Divider(height: 20),
          _baris('Total', s.totalSeharusnya, s.totalTerbukti, tebal: true),
          if (s.gatewayFee > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Termasuk biaya gateway ${_rp.format(s.gatewayFee)} — '
              'terpotong di jalan, bukan hilang.',
              style: TextStyle(
                  fontSize: 11.5, color: KaataTheme.mutedOf(context)),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sibuk ? null : _tutup,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Tutup Buku'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baris(String label, int seharusnya, int terbukti,
      {bool tebal = false}) {
    final selisih = terbukti - seharusnya;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: tebal ? FontWeight.bold : FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(_rp.format(seharusnya),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: tebal ? FontWeight.bold : null)),
          ),
          Expanded(
            flex: 3,
            child: Text(_rp.format(terbukti),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: tebal ? FontWeight.bold : null,
                    // Yang belum dicocokkan nol, dan nol di sini berarti
                    // "belum diperiksa", bukan "tidak ada". Dibedakan
                    // warnanya supaya tidak terbaca sebagai uang hilang.
                    color: terbukti == 0 && seharusnya > 0
                        ? KaataTheme.mutedOf(context)
                        : null)),
          ),
          SizedBox(
            width: 26,
            child: selisih == 0
                ? const Icon(Icons.check, size: 15, color: Color(0xFF10B981))
                : Icon(Icons.priority_high,
                    size: 15,
                    color: terbukti == 0
                        ? KaataTheme.mutedOf(context)
                        : Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _kartuRiwayat(DailySettlement s) {
    final cocok = s.selisih == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_tgl.format(s.settledOn),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
              Text(
                cocok ? 'Cocok' : 'Selisih ${_rp.format(s.selisih.abs())}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cocok ? const Color(0xFF10B981) : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Seharusnya ${_rp.format(s.totalSeharusnya)} · '
            'Terbukti ${_rp.format(s.totalTerbukti)}',
            style:
                TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context)),
          ),
          if (s.note != null && s.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Catatan: ${s.note}',
                  style: TextStyle(
                      fontSize: 11.5, color: KaataTheme.mutedOf(context))),
            ),
          if (s.settledBy != null)
            Text('Ditutup ${s.settledBy}',
                style: TextStyle(
                    fontSize: 11, color: KaataTheme.mutedOf(context))),
          if (s.ditutup) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _sibuk ? null : () => _bukaLagi(s),
                icon: const Icon(Icons.lock_open_outlined, size: 16),
                label: const Text('Buka Kembali'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
