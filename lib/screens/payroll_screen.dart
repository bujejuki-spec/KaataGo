import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/absensi_repository.dart';
import '../db/payroll_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/absensi.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/absensi_export.dart';
import '../utils/akses_menu.dart';
import '../utils/daftar_bank.dart';
import '../utils/id_time.dart';
import '../utils/kode_bank.dart';
import '../utils/pesan_galat.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';

/// Payroll — Owner dan Finance.
///
/// Tiga hal di satu layar: aturannya (tanggal gajian, hari kerja, BPJS),
/// gaji tiap orang berikut rekeningnya, dan rekap satu periode yang
/// dihitung server dari absensi.
///
/// Rekapnya tidak dihitung ulang di sini. Dua tempat yang menjumlahkan
/// gaji sendiri akan suatu hari menyebut dua angka berbeda untuk orang
/// yang sama — dan angka gaji bukan tempat yang pantas untuk perbedaan
/// semacam itu.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final _repo = PayrollRepository();
  final _absensi = AbsensiRepository();

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _bulan = DateFormat('MMMM yyyy', 'id_ID');
  static final _tgl = DateFormat('d MMM', 'id_ID');

  late DateTime _periode;
  AturanGaji _aturan = const AturanGaji();
  List<BarisPayroll> _rekap = const [];
  String _namaMerchant = '';

  bool _memuat = true;
  bool _mengekspor = false;
  String? _galat;

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now().toWib();
    _periode = DateTime(kini.year, kini.month, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  ({DateTime mulai, DateTime akhir}) get _rentang =>
      _aturan.periodeUntuk(_periode);

  Future<void> _muat() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) {
      setState(() {
        _memuat = false;
        _galat = 'Pilih merchant dulu.';
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
      final hasil = await Future.wait([
        _repo.rekap(restoId, p.mulai, p.akhir),
        RestaurantRepository().getOnce(restoId),
      ]);
      if (!mounted) return;
      setState(() {
        _aturan = aturan;
        _rekap = hasil[0] as List<BarisPayroll>;
        _namaMerchant = (hasil[1] as dynamic)?.name ?? '';
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

  Future<void> _ubahAturan() async {
    final hasil = await showDialog<AturanGaji>(
      context: context,
      builder: (_) => _DialogAturan(awal: _aturan),
    );
    if (hasil == null || !mounted) return;
    final auth = context.read<AuthProvider>();
    try {
      await _repo.simpanAturan(
          auth.restoId!, hasil, auth.user?.email ?? '');
      await _muat();
      if (mounted) showAppToast(context, 'Aturan gaji tersimpan.');
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    }
  }

  Future<void> _ubahGaji(BarisPayroll baris) async {
    final hasil = await showDialog<GajiKaryawan>(
      context: context,
      builder: (_) => _DialogGaji(awal: baris),
    );
    if (hasil == null || !mounted) return;
    final auth = context.read<AuthProvider>();
    try {
      await _repo.simpanGaji(
        restoId: auth.restoId!,
        gaji: hasil,
        oleh: auth.user?.email ?? '',
      );
      await _muat();
      if (mounted) showAppToast(context, 'Gaji ${baris.nama} tersimpan.');
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    }
  }

  Future<void> _ekspor({required bool pdf}) async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    setState(() => _mengekspor = true);
    try {
      final p = _rentang;
      final absensi =
          await _absensi.rentang(restoId, mulai: p.mulai, akhir: p.akhir);
      final perOrang = <String, List<BarisAbsensi>>{};
      for (final a in absensi) {
        perOrang.putIfAbsent(a.email.toLowerCase(), () => []).add(a);
      }
      final data = [
        for (final r in _rekap)
          RekapKaryawan(
            payroll: r,
            absensi: perOrang[r.email.toLowerCase()] ?? const [],
          ),
      ];

      final nama = namaBerkasAbsensi(_namaMerchant, _periode);
      if (pdf) {
        final bytes = await pdfAbsensiPayroll(
          namaMerchant: _namaMerchant,
          mulai: p.mulai,
          akhir: p.akhir,
          data: data,
          aturan: _aturan,
        );
        await serahkanBerkas(bytes: bytes, nama: '$nama.pdf', tipe: mimePdf);
      } else {
        final bytes = xlsxAbsensiPayroll(
          namaMerchant: _namaMerchant,
          mulai: p.mulai,
          akhir: p.akhir,
          data: data,
          aturan: _aturan,
        );
        await serahkanBerkas(bytes: bytes, nama: '$nama.xlsx', tipe: mimeXlsx);
      }
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _mengekspor = false);
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
      initialDatePickerMode: DatePickerMode.year,
    );
    if (hasil == null || !mounted) return;
    setState(() => _periode = DateTime(hasil.year, hasil.month, 1));
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final p = _rentang;
    final total = _rekap.fold<int>(0, (a, b) => a + b.gajiBersih);
    final muted = KaataTheme.mutedOf(context);

    return berdasarkanAkses(
      context,
      'Payroll',
      Scaffold(
        backgroundColor: KaataTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Payroll'),
          actions: [
            if (_mengekspor)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Ekspor',
                onSelected: (v) => _ekspor(pdf: v == 'pdf'),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('Ekspor PDF')),
                  PopupMenuItem(value: 'xlsx', child: Text('Ekspor XLSX')),
                ],
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
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_outlined, size: 16),
                        label: Text('${_bulan.format(_periode)}  •  '
                            '${_tgl.format(p.mulai)} – ${_tgl.format(p.akhir)}'),
                        onPressed: _pilihPeriode,
                      ),
                      const SizedBox(height: 14),
                      _KartuTotal(
                        total: total,
                        orang: _rekap.length,
                        rp: _rp,
                      ),
                      const SizedBox(height: 12),
                      _KartuAturan(
                        aturan: _aturan,
                        onUbah:
                            bolehUbahDiSini(context) ? _ubahAturan : null,
                      ),
                      const SizedBox(height: 16),
                      if (_galat != null)
                        Text(_galat!, style: const TextStyle(color: Colors.red))
                      else ...[
                        Text('Gaji per karyawan',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: muted)),
                        const SizedBox(height: 8),
                        for (final r in _rekap)
                          _BarisKaryawan(
                            baris: r,
                            rp: _rp,
                            onUbah: bolehUbahDiSini(context)
                                ? () => _ubahGaji(r)
                                : null,
                          ),
                      ],
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
  final int orang;
  final NumberFormat rp;

  const _KartuTotal(
      {required this.total, required this.orang, required this.rp});

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
          colors: [KaataTheme.brand, KaataTheme.brandDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total gaji periode ini',
              style: TextStyle(
                  fontSize: 12.5, color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 4),
          Text(rp.format(total),
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 6),
          Text('$orang karyawan',
              style: TextStyle(
                  fontSize: 12.5, color: Colors.white.withOpacity(0.85))),
        ],
      ),
    );
  }
}

class _KartuAturan extends StatelessWidget {
  final AturanGaji aturan;
  final VoidCallback? onUbah;

  const _KartuAturan({required this.aturan, this.onUbah});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                child: Text('Aturan Gaji',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: muted)),
              ),
              if (onUbah != null)
                TextButton(onPressed: onUbah, child: const Text('Ubah')),
            ],
          ),
          _baris('Gajian tiap tanggal', '${aturan.tanggalGajian}', muted),
          _baris('Hari kerja per periode', '${aturan.hariKerjaPeriode} hari',
              muted),
          _baris(
              'BPJS Kesehatan',
              aturan.bpjsKesehatanPersen == 0
                  ? 'tidak dipotong'
                  : '${aturan.bpjsKesehatanPersen}%',
              muted),
          _baris(
              'BPJS Ketenagakerjaan',
              aturan.bpjsTkPersen == 0
                  ? 'tidak dipotong'
                  : '${aturan.bpjsTkPersen}%',
              muted),
          _baris('Radius absen', '${aturan.radiusAbsenM} m', muted),
        ],
      ),
    );
  }

  Widget _baris(String label, String nilai, Color muted) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 12.5, color: muted)),
            ),
            Text(nilai,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _BarisKaryawan extends StatelessWidget {
  final BarisPayroll baris;
  final NumberFormat rp;
  final VoidCallback? onUbah;

  const _BarisKaryawan({required this.baris, required this.rp, this.onUbah});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baris.nama,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  baris.belumDisetel
                      ? 'Gaji belum disetel'
                      : '${baris.hadir}/${baris.hariKerja} hari hadir'
                          '${baris.hariPotong > 0 ? '  •  potong ${baris.hariPotong} hari' : ''}',
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
                if (!baris.belumDisetel && baris.accountNumber?.isNotEmpty == true)
                  Text(
                    '${bankBerkode(baris.bankName)} · ${baris.accountNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                baris.belumDisetel ? '—' : rp.format(baris.gajiBersih),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (!baris.belumDisetel && baris.totalPotongan > 0)
                Text('− ${rp.format(baris.totalPotongan)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFB91C1C))),
            ],
          ),
          if (onUbah != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Setel gaji',
              onPressed: onUbah,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Dialog
// ─────────────────────────────────────────────────────────────────────

class _DialogAturan extends StatefulWidget {
  final AturanGaji awal;

  const _DialogAturan({required this.awal});

  @override
  State<_DialogAturan> createState() => _DialogAturanState();
}

class _DialogAturanState extends State<_DialogAturan> {
  late final _gajian =
      TextEditingController(text: '${widget.awal.tanggalGajian}');
  late final _hariKerja =
      TextEditingController(text: '${widget.awal.hariKerjaPeriode}');
  late final _bpjsKes =
      TextEditingController(text: '${widget.awal.bpjsKesehatanPersen}');
  late final _bpjsTk =
      TextEditingController(text: '${widget.awal.bpjsTkPersen}');
  late final _radius =
      TextEditingController(text: '${widget.awal.radiusAbsenM}');

  @override
  void dispose() {
    for (final c in [_gajian, _hariKerja, _bpjsKes, _bpjsTk, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aturan Gaji'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _angka(_gajian, 'Gajian tiap tanggal', '1–28'),
            _angka(_hariKerja, 'Hari kerja per periode',
                'Pembagi gaji sebulan — bukan jumlah hari kalender'),
            _angka(_bpjsKes, 'BPJS Kesehatan (%)', 'Kosongkan kalau tidak ada'),
            _angka(_bpjsTk, 'BPJS Ketenagakerjaan (%)',
                'Kosongkan kalau tidak ada'),
            _angka(_radius, 'Radius absen (meter)',
                'GPS di dalam ruko meleset puluhan meter — 150 aman'),
          ],
        ),
      ),
      actions: [
        DialogActions(
          confirmLabel: 'Simpan',
          onConfirm: () {
            final hariKerja = int.tryParse(_hariKerja.text) ?? 25;
            if (hariKerja < 1) {
              showAppToast(context, 'Hari kerja minimal 1.', isError: true);
              return;
            }
            Navigator.pop(
              context,
              AturanGaji(
                tanggalGajian:
                    (int.tryParse(_gajian.text) ?? 25).clamp(1, 28),
                hariKerjaPeriode: hariKerja.clamp(1, 31),
                bpjsKesehatanPersen:
                    (double.tryParse(_bpjsKes.text) ?? 0).clamp(0, 100),
                bpjsTkPersen:
                    (double.tryParse(_bpjsTk.text) ?? 0).clamp(0, 100),
                radiusAbsenM:
                    (int.tryParse(_radius.text) ?? 150).clamp(20, 5000),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _angka(TextEditingController c, String label, String bantuan) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            helperText: bantuan,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}

class _DialogGaji extends StatefulWidget {
  final BarisPayroll awal;

  const _DialogGaji({required this.awal});

  @override
  State<_DialogGaji> createState() => _DialogGajiState();
}

class _DialogGajiState extends State<_DialogGaji> {
  late final _pokok =
      TextEditingController(text: formatRupiahInput(widget.awal.gajiPokok));
  late final _tunjangan =
      TextEditingController(text: formatRupiahInput(widget.awal.tunjangan));
  late final _rekening =
      TextEditingController(text: widget.awal.accountNumber ?? '');
  late final _atasNama = TextEditingController(
      text: widget.awal.accountHolder ?? widget.awal.nama);
  late String? _bank = bankTerpilih(
      widget.awal.bankName, daftarBankUntuk(widget.awal.bankName));

  @override
  void dispose() {
    for (final c in [_pokok, _tunjangan, _rekening, _atasNama]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pilihan = daftarBankUntuk(widget.awal.bankName);
    final kode = kodeBank(_bank);

    return AlertDialog(
      title: Text(widget.awal.nama, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _pokok,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Gaji pokok per periode',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tunjangan,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Tunjangan tetap',
                helperText: 'Tidak ikut dipotong kehadiran',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _bank,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Bank',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final b in pilihan)
                  DropdownMenuItem(value: b, child: Text(b)),
              ],
              onChanged: (v) => setState(() => _bank = v),
            ),
            if (kode != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Kode bank $kode',
                    style: TextStyle(
                        fontSize: 11.5, color: KaataTheme.mutedOf(context))),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _rekening,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nomor rekening',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _atasNama,
              decoration: const InputDecoration(
                labelText: 'Atas nama',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        DialogActions(
          confirmLabel: 'Simpan',
          onConfirm: () => Navigator.pop(
            context,
            GajiKaryawan(
              email: widget.awal.email,
              gajiPokok: parseRupiah(_pokok.text) ?? 0,
              tunjangan: parseRupiah(_tunjangan.text) ?? 0,
              bankName: _bank,
              accountNumber: _rekening.text.trim(),
              accountHolder: _atasNama.text.trim(),
            ),
          ),
        ),
      ],
    );
  }
}
