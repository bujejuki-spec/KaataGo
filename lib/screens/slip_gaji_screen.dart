import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/payroll_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/absensi.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/absensi_export.dart';
import '../utils/id_time.dart';
import '../utils/kode_bank.dart';
import '../utils/pesan_galat.dart';
import '../utils/slip_gaji_pdf.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';

/// Slip gaji karyawan sendiri, satu periode.
///
/// Ada karena angka gaji yang cuma disebut lisan adalah angka yang tidak
/// bisa dibantah maupun dibenarkan. Yang menerimanya berhak tahu
/// potongannya dari mana — berapa hari yang dihitung tidak masuk, dan
/// berapa yang dipotong BPJS.
class SlipGajiScreen extends StatefulWidget {
  const SlipGajiScreen({super.key});

  @override
  State<SlipGajiScreen> createState() => _SlipGajiScreenState();
}

class _SlipGajiScreenState extends State<SlipGajiScreen> {
  final _repo = PayrollRepository();

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _bulan = DateFormat('MMMM yyyy', 'id_ID');
  static final _tgl = DateFormat('d MMM yyyy', 'id_ID');

  AturanGaji _aturan = const AturanGaji();
  BarisPayroll? _slip;
  String _namaMerchant = '';
  late DateTime _periode;
  bool _memuat = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now().toWib();
    _periode = DateTime(kini.year, kini.month, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  Future<void> _muat() async {
    final auth = context.read<AuthProvider>();
    final restoId = auth.restoId;
    final email = auth.user?.email;
    if (restoId == null || email == null) {
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
      final aturan = await _repo.aturan(restoId);
      final p = aturan.periodeUntuk(_periode);
      final slip = await _repo.slipSaya(
        restoId: restoId,
        mulai: p.mulai,
        akhir: p.akhir,
        email: email,
        nama: auth.employeeName?.isNotEmpty == true
            ? auth.employeeName!
            : email,
      );
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted) return;
      setState(() {
        _aturan = aturan;
        _slip = slip;
        _namaMerchant = resto?.name ?? '';
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
    final kini = DateTime.now().toWib();
    final hasil = await showDatePicker(
      context: context,
      initialDate: _periode,
      firstDate: DateTime(kini.year - 2, 1),
      lastDate: DateTime(kini.year, kini.month, 1),
      helpText: 'Periode gaji',
      // Yang dipilih bulannya, bukan harinya — tanggal mana pun di bulan
      // itu menghasilkan periode yang sama.
      initialDatePickerMode: DatePickerMode.year,
    );
    if (hasil == null || !mounted) return;
    setState(() => _periode = DateTime(hasil.year, hasil.month, 1));
    await _muat();
  }

  Future<void> _unduh() async {
    final slip = _slip;
    if (slip == null) return;
    try {
      final p = _aturan.periodeUntuk(_periode);
      final bytes = await pdfSlipGaji(
        namaMerchant: _namaMerchant,
        slip: slip,
        mulai: p.mulai,
        akhir: p.akhir,
        aturan: _aturan,
      );
      await serahkanBerkas(
        bytes: bytes,
        nama: 'Slip Gaji ${slip.nama} ${_bulan.format(_periode)}.pdf',
        tipe: mimePdf,
      );
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _aturan.periodeUntuk(_periode);
    final slip = _slip;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Slip Gaji'),
        actions: [
          if (slip != null && !slip.belumDisetel)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Unduh PDF',
              onPressed: _unduh,
            ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text('Periode ${_bulan.format(_periode)}  •  '
                        '${_tgl.format(p.mulai)} – ${_tgl.format(p.akhir)}'),
                    onPressed: _pilihPeriode,
                  ),
                  const SizedBox(height: 16),
                  if (_galat != null)
                    Text(_galat!, style: const TextStyle(color: Colors.red))
                  else if (slip == null || slip.belumDisetel)
                    _BelumDisetel()
                  else
                    _Slip(slip: slip, rp: _rp),
                ],
              ),
            ),
    );
  }
}

class _BelumDisetel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 42, color: KaataTheme.mutedOf(context)),
          const SizedBox(height: 12),
          Text(
            'Gajimu belum disetel di sistem.\n'
            'Hubungi Owner atau bagian Finance merchant ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: KaataTheme.mutedOf(context)),
          ),
        ],
      ),
    );
  }
}

class _Slip extends StatelessWidget {
  final BarisPayroll slip;
  final NumberFormat rp;

  const _Slip({required this.slip, required this.rp});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [KaataTheme.brand, KaataTheme.brandDark],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gaji bersih',
                  style: TextStyle(
                      fontSize: 12.5, color: Colors.white.withOpacity(0.85))),
              const SizedBox(height: 4),
              Text(rp.format(slip.gajiBersih),
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                '${slip.hadir} hari hadir dari ${slip.hariKerja} hari kerja',
                style: TextStyle(
                    fontSize: 12.5, color: Colors.white.withOpacity(0.85)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Kartu(judul: 'Penerimaan', baris: <(String, String, bool)>[
          ('Gaji pokok', rp.format(slip.gajiPokok), false),
          if (slip.tunjangan > 0)
            ('Tunjangan', rp.format(slip.tunjangan), false),
        ]),
        const SizedBox(height: 12),
        _Kartu(judul: 'Potongan', baris: [
          (
            'Tidak masuk (${slip.hariPotong} hari)',
            '− ${rp.format(slip.potonganAbsen)}',
            true
          ),
          if (slip.potonganBpjsKesehatan > 0)
            ('BPJS Kesehatan', '− ${rp.format(slip.potonganBpjsKesehatan)}', true),
          if (slip.potonganBpjsTk > 0)
            (
              'BPJS Ketenagakerjaan',
              '− ${rp.format(slip.potonganBpjsTk)}',
              true
            ),
        ]),
        const SizedBox(height: 12),
        _Kartu(judul: 'Kehadiran', baris: [
          ('Hadir', '${slip.hadir} hari', false),
          if (slip.izin > 0) ('Izin', '${slip.izin} hari', false),
          if (slip.sakit > 0) ('Sakit', '${slip.sakit} hari', false),
          if (slip.cuti > 0) ('Cuti', '${slip.cuti} hari', false),
          if (slip.alpa > 0) ('Alpa', '${slip.alpa} hari', false),
        ]),
        if (slip.accountNumber?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          _Kartu(judul: 'Rekening', baris: [
            ('Bank', bankBerkode(slip.bankName), false),
            ('No. rekening', slip.accountNumber!, false),
            if (slip.accountHolder?.isNotEmpty == true)
              ('Atas nama', slip.accountHolder!, false),
          ]),
        ],
        const SizedBox(height: 14),
        Text(
          'Angka di slip ini dihitung server dari absensi yang tercatat. '
          'Kalau ada hari yang menurutmu keliru, tunjukkan ke Admin — dia '
          'yang bisa membetulkannya.',
          style: TextStyle(fontSize: 11.5, color: muted, height: 1.4),
        ),
      ],
    );
  }
}

class _Kartu extends StatelessWidget {
  final String judul;
  final List<(String, String, bool)> baris;

  const _Kartu({required this.judul, required this.baris});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    if (baris.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(judul,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: muted)),
          const SizedBox(height: 8),
          for (final (label, nilai, merah) in baris)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(fontSize: 13, color: muted)),
                  ),
                  Text(nilai,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: merah ? const Color(0xFFB91C1C) : null,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
