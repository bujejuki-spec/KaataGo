import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/absensi_repository.dart';
import '../db/employee_repository.dart';
import '../db/payroll_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/absensi.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/absensi_export.dart';
import '../utils/akses_menu.dart';
import '../utils/id_time.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';

/// Laporan absensi satu periode gaji — Admin, Owner, dan Finance.
///
/// Periodenya mengikuti tanggal gajian merchant, bukan bulan kalender.
/// Laporan absensi yang berhenti tanggal 31 sementara gajinya dihitung
/// sampai tanggal 25 adalah dua angka yang tidak akan pernah cocok, dan
/// yang menghabiskan waktu mencocokkannya adalah orang yang paling
/// sibuk di akhir bulan.
class AbsensiReportScreen extends StatefulWidget {
  const AbsensiReportScreen({super.key});

  @override
  State<AbsensiReportScreen> createState() => _AbsensiReportScreenState();
}

class _AbsensiReportScreenState extends State<AbsensiReportScreen> {
  final _absensi = AbsensiRepository();
  final _payroll = PayrollRepository();

  static final _bulan = DateFormat('MMMM yyyy', 'id_ID');
  static final _tgl = DateFormat('d MMM', 'id_ID');
  static final _jam = DateFormat('HH:mm', 'id_ID');

  late DateTime _periode;
  AturanGaji _aturan = const AturanGaji();
  List<BarisAbsensi> _baris = const [];
  var _nama = const <String, String>{};
  var _acuan = const <String, String>{};
  String _namaMerchant = '';

  bool _memuat = true;
  bool _mengekspor = false;
  String? _galat;

  /// Disaring ke satu orang, atau null untuk semuanya.
  String? _fokus;

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
      final aturan = await _payroll.aturan(restoId);
      final p = aturan.periodeUntuk(_periode);
      final hasil = await Future.wait([
        _absensi.rentang(restoId, mulai: p.mulai, akhir: p.akhir),
        RestaurantRepository().getOnce(restoId),
        EmployeeRepository().getByResto(restoId),
        _absensi.fotoAcuan(restoId),
      ]);
      if (!mounted) return;
      setState(() {
        _aturan = aturan;
        _baris = hasil[0] as List<BarisAbsensi>;
        _namaMerchant = (hasil[1] as dynamic)?.name ?? '';
        // Nama orangnya dari daftar karyawan, bukan dari emailnya.
        // Laporan yang menyebut "budi.s99" alih-alih "Budi Santoso"
        // memaksa yang membacanya menerjemahkan sendiri tiap baris.
        _nama = {
          for (final e in hasil[2] as List<Employee>)
            e.email.toLowerCase(): e.name.isEmpty ? e.email : e.name,
        };
        _acuan = hasil[3] as Map<String, String>;
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

  /// Nama tampilan satu email — dari daftar karyawan kalau ada, kalau
  /// tidak dari emailnya sendiri.
  String _namaOrang(String email) =>
      _nama[email.toLowerCase()] ?? email.split('@').first;

  Map<String, List<BarisAbsensi>> get _perOrang {
    final map = <String, List<BarisAbsensi>>{};
    for (final b in _baris) {
      map.putIfAbsent(b.email.toLowerCase(), () => []).add(b);
    }
    for (final v in map.values) {
      v.sort((a, b) => b.tanggal.compareTo(a.tanggal));
    }
    return map;
  }

  Future<void> _ubahPotong(BarisAbsensi baris, bool potong) async {
    final email = context.read<AuthProvider>().user?.email ?? '';
    try {
      await _absensi.putuskan(id: baris.id, potongGaji: potong, oleh: email);
      await _muat();
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
      // Rekap gajinya ditarik ulang di sini, bukan dihitung dari baris
      // yang sudah ada di layar: yang di layar cuma absensinya, dan
      // menjumlahkan gaji sendiri di aplikasi adalah cara paling pasti
      // menghasilkan angka yang berbeda dari yang dibayarkan.
      final rekap = await _payroll.rekap(restoId, p.mulai, p.akhir);
      final perOrang = _perOrang;
      final data = [
        for (final r in rekap)
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
    final perOrang = _perOrang;
    final muted = KaataTheme.mutedOf(context);

    return berdasarkanAkses(
      context,
      'Absensi Karyawan',
      Scaffold(
        backgroundColor: KaataTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Absensi Karyawan'),
          actions: [
            if (_mengekspor)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
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
                      if (_galat != null)
                        Text(_galat!, style: const TextStyle(color: Colors.red))
                      else if (perOrang.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(Icons.event_note_outlined,
                                  size: 40, color: muted),
                              const SizedBox(height: 10),
                              Text('Belum ada absensi di periode ini.',
                                  style: TextStyle(color: muted)),
                            ],
                          ),
                        )
                      else
                        for (final e in perOrang.entries)
                          _KartuOrang(
                            nama: _namaOrang(e.key),
                            email: e.key,
                            acuanUrl: _acuan[e.key],
                            baris: e.value,
                            terbuka: _fokus == e.key,
                            jam: _jam,
                            onToggle: () => setState(
                                () => _fokus = _fokus == e.key ? null : e.key),
                            onPotong: _ubahPotong,
                          ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _KartuOrang extends StatelessWidget {
  final String nama;
  final String email;
  final String? acuanUrl;
  final List<BarisAbsensi> baris;
  final bool terbuka;
  final DateFormat jam;
  final VoidCallback onToggle;
  final Future<void> Function(BarisAbsensi, bool) onPotong;

  static final _tgl = DateFormat('EEE, d MMM', 'id_ID');

  const _KartuOrang({
    required this.nama,
    required this.email,
    this.acuanUrl,
    required this.baris,
    required this.terbuka,
    required this.jam,
    required this.onToggle,
    required this.onPotong,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final hadir = baris.where((b) => b.status == StatusAbsen.hadir).length;
    final potong = baris.where((b) => b.potongGaji).length;
    final ragu = baris.where((b) => b.ragu).length;
    final totalJam = baris.fold<double>(0, (a, b) => a + b.lamaJam);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(nama,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: Text(
              '$hadir hari hadir'
              '${totalJam > 0 ? '  •  ${totalJam.toStringAsFixed(1)} jam kerja' : ''}'
              '${potong > 0 ? '  •  $potong hari potong gaji' : ''}'
              '${ragu > 0 ? '  •  $ragu hari perlu dilihat' : ''}',
              style: TextStyle(
                  fontSize: 12,
                  color: ragu > 0 ? const Color(0xFFB45309) : muted),
            ),
            trailing: Icon(terbuka ? Icons.expand_less : Icons.expand_more),
            onTap: onToggle,
          ),
          if (terbuka)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 8, 10),
              child: Column(
                children: [
                  for (final b in baris)
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(_tgl.format(b.tanggal),
                              style: TextStyle(fontSize: 12, color: muted)),
                        ),
                        Expanded(
                          child: Text(
                            b.status == StatusAbsen.hadir
                                ? '${b.masukAt == null ? '—' : jam.format(b.masukAt!.toWib())}'
                                    ' → ${b.pulangAt == null ? '—' : jam.format(b.pulangAt!.toWib())}'
                                    '${b.lamaTeks == null ? '' : '  ·  ${b.lamaTeks}'}'
                                    '${b.masukJarakM == null ? '' : '  (${b.masukJarakM} m)'}'
                                : '${b.status.label}${b.alasan == null ? '' : ' — ${b.alasan}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        // Foto absennya disandingkan dengan foto acuan.
                        //
                        // Inilah yang benar-benar menangkap absen yang
                        // dititipkan. Pencocokan otomatisnya cuma
                        // membandingkan bentuk wajah, dan bentuk wajah
                        // dua orang bisa mirip — yang tidak mirip
                        // wajahnya sendiri, dan itu terlihat dalam dua
                        // detik kalau kedua fotonya bersebelahan.
                        if (b.masukFotoUrl != null)
                          _TombolFoto(
                            acuanUrl: acuanUrl,
                            absenUrl: b.masukFotoUrl!,
                            nama: nama,
                            ragu: b.masukRagu,
                          ),
                        // Keputusan potong gaji ada di baris harinya,
                        // bukan di layar payroll. Yang memutuskannya
                        // butuh melihat alasan dan buktinya — dan
                        // keduanya ada di sini, bukan di sana.
                        Tooltip(
                          message: b.potongGaji
                              ? 'Hari ini memotong gaji'
                              : 'Hari ini tidak memotong gaji',
                          child: Switch(
                            value: b.potongGaji,
                            onChanged: bolehUbahDiSini(context)
                                ? (v) => onPotong(b, v)
                                : null,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Membuka foto acuan dan foto absen bersebelahan.
///
/// Inilah pemeriksaan yang benar-benar menangkap absen yang dititipkan.
/// Pencocokan otomatis di server cuma membandingkan BENTUK wajah, dan
/// bentuk wajah dua orang bisa mirip — yang tidak mirip wajahnya
/// sendiri, dan itu terlihat seketika oleh mata orang.
///
/// Diletakkan di baris harinya, tepat di sebelah sakelar potong gaji:
/// keduanya dipakai pada saat yang sama, yaitu saat memutuskan seseorang
/// dibayar untuk hari itu atau tidak.
class _TombolFoto extends StatelessWidget {
  final String? acuanUrl;
  final String absenUrl;
  final String nama;
  final bool ragu;

  const _TombolFoto({
    required this.acuanUrl,
    required this.absenUrl,
    required this.nama,
    required this.ragu,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        ragu ? Icons.report_gmailerrorred_outlined : Icons.face_outlined,
        size: 19,
        color: ragu ? const Color(0xFFB45309) : null,
      ),
      tooltip: ragu
          ? 'Wajahnya kurang meyakinkan — periksa fotonya'
          : 'Bandingkan dengan foto acuan',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _DialogBandingFoto(
          acuanUrl: acuanUrl,
          absenUrl: absenUrl,
          nama: nama,
          ragu: ragu,
        ),
      ),
    );
  }
}

class _DialogBandingFoto extends StatelessWidget {
  final String? acuanUrl;
  final String absenUrl;
  final String nama;
  final bool ragu;

  const _DialogBandingFoto({
    required this.acuanUrl,
    required this.absenUrl,
    required this.nama,
    required this.ragu,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(nama,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ragu) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFB45309).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Kemiripan wajahnya di bawah yang meyakinkan. Absennya '
                  'tetap tercatat — periksa sendiri kedua fotonya.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Foto(
                      judul: 'Acuan', url: acuanUrl, kosong: 'Belum ada'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Foto(judul: 'Absen hari itu', url: absenUrl),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Foto acuan diambil sekali saat mendaftarkan wajah. Kalau '
              'kedua wajah ini jelas bukan orang yang sama, reset wajahnya '
              'lewat Kelola Karyawan lalu tandai harinya memotong gaji.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}

class _Foto extends StatelessWidget {
  final String judul;
  final String? url;
  final String kosong;

  const _Foto({required this.judul, this.url, this.kosong = 'Tidak ada'});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(judul,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.bold, color: muted)),
        const SizedBox(height: 5),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: url == null
                ? Container(
                    color: KaataTheme.softFillOf(context),
                    alignment: Alignment.center,
                    child: Text(kosong,
                        style: TextStyle(fontSize: 11.5, color: muted)),
                  )
                : Image.network(
                    url!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: KaataTheme.softFillOf(context),
                      alignment: Alignment.center,
                      child: Text('Gagal dimuat',
                          style: TextStyle(fontSize: 11.5, color: muted)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
