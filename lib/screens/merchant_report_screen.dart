import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/merchant_report_repository.dart';
import '../models/merchant_report.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/grafik_laporan.dart';
import '../widgets/responsive.dart';

/// Laporan Penjualan — Owner dan Admin.
///
/// Angka penjualan selama ini hanya bisa dibaca sebagai daftar transaksi
/// satu per satu. Itu cukup untuk mencocokkan uang, tapi tidak menjawab
/// pertanyaan yang benar-benar menentukan: menu mana yang sebaiknya
/// ditambah porsinya, menu mana yang sebaiknya dibuang dari daftar, dan
/// jam berapa orang harus disiapkan lebih banyak.
class MerchantReportScreen extends StatefulWidget {
  const MerchantReportScreen({super.key});

  @override
  State<MerchantReportScreen> createState() => _MerchantReportScreenState();
}

class _MerchantReportScreenState extends State<MerchantReportScreen> {
  final _repo = MerchantReportRepository();

  late DateTime _dari;
  late DateTime _sampai;

  RingkasanPenjualan _ringkasan = const RingkasanPenjualan();
  List<PenjualanMenu> _terlaris = const [];
  List<MenuTidakLaku> _tidakLaku = const [];
  List<JamRamai> _jamRamai = const [];
  List<TitikPenjualan> _deret = const [];
  List<PotongPenjualan> _potong = const [];
  bool _memuat = true;

  /// Yang digambar garis trennya.
  ///
  /// Bisa dipilih karena ketiganya menjawab pertanyaan yang berbeda:
  /// omzet menjawab berapa uangnya, jumlah pesanan menjawab berapa orang
  /// yang datang, dan porsi menjawab berapa banyak yang keluar dari
  /// dapur. Hari raya yang ramai tapi belanjanya kecil hanya terlihat
  /// kalau dua di antaranya bisa dibandingkan.
  _Metrik _metrik = _Metrik.omzet;

  /// 'day' | 'week' | 'month'
  String _satuan = 'day';

  /// Sudut pandang pembagian omzetnya.
  _Dimensi _dimensi = _Dimensi.caraBayar;

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _ringkas = NumberFormat.decimalPattern('id_ID');
  static final _tgl = DateFormat('d MMM yyyy', 'id_ID');

  @override
  void initState() {
    super.initState();
    // Tiga puluh hari terakhir, bukan bulan berjalan. Tanggal 2 bulan
    // depan, "bulan ini" berisi dua hari — dan laporan yang isinya dua
    // hari tidak memberi tahu apa pun tentang menu mana yang laku.
    final kini = DateTime.now();
    _sampai = DateTime(kini.year, kini.month, kini.day);
    _dari = _sampai.subtract(const Duration(days: 29));
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  Future<void> _muat() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    setState(() => _memuat = true);
    try {
      final hasil = await Future.wait([
        _repo.ringkasan(restoId, _dari, _sampai),
        _repo.terlaris(restoId, _dari, _sampai),
        _repo.tidakLaku(restoId, _dari, _sampai),
        _repo.jamRamai(restoId, _dari, _sampai),
        _repo.deret(restoId, _dari, _sampai, satuan: _satuan),
        _muatPotong(restoId),
      ]);
      if (!mounted) return;
      setState(() {
        _ringkasan = hasil[0] as RingkasanPenjualan;
        _terlaris = hasil[1] as List<PenjualanMenu>;
        _tidakLaku = hasil[2] as List<MenuTidakLaku>;
        _jamRamai = hasil[3] as List<JamRamai>;
        _deret = hasil[4] as List<TitikPenjualan>;
        _potong = hasil[5] as List<PotongPenjualan>;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat laporan: $e', isError: true);
    }
  }

  Future<List<PotongPenjualan>> _muatPotong(String restoId) =>
      _dimensi == _Dimensi.kategori
          ? _repo.perKategori(restoId, _dari, _sampai)
          : _repo.pembagian(restoId, _dari, _sampai, dimensi: _dimensi.kode);

  /// Mengganti satuan waktu hanya menarik ulang deretnya.
  ///
  /// Empat panggilan lain tidak ikut berubah oleh pilihan ini, dan
  /// memuat ulang semuanya berarti seluruh layar berkedip kosong hanya
  /// karena orang menekan "Mingguan".
  Future<void> _gantiSatuan(String satuan) async {
    if (satuan == _satuan) return;
    setState(() => _satuan = satuan);
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final deret = await _repo.deret(restoId, _dari, _sampai, satuan: satuan);
      if (mounted) setState(() => _deret = deret);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal memuat grafik: $e', isError: true);
    }
  }

  Future<void> _gantiDimensi(_Dimensi dimensi) async {
    if (dimensi == _dimensi) return;
    setState(() => _dimensi = dimensi);
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final potong = await _muatPotong(restoId);
      if (mounted) setState(() => _potong = potong);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal memuat pembagian: $e', isError: true);
    }
  }

  Future<void> _pilihRentang() async {
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dari, end: _sampai),
      helpText: 'Rentang laporan',
      saveText: 'Terapkan',
    );
    if (hasil == null || !mounted) return;
    setState(() {
      _dari = hasil.start;
      _sampai = hasil.end;
    });
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Laporan Penjualan')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    _pemilihRentang(),
                    const SizedBox(height: 10),
                    _pintasanRentang(),
                    const SizedBox(height: 14),
                    if (_ringkasan.kosong)
                      _Kosong(dari: _dari, sampai: _sampai)
                    else ...[
                      _kartuRingkasan(),
                      const SizedBox(height: 14),
                      _bagianTren(),
                      const SizedBox(height: 14),
                      _bagianPembagian(),
                      const SizedBox(height: 14),
                      _bagianTerlaris(),
                      const SizedBox(height: 14),
                      _bagianJamRamai(),
                    ],
                    const SizedBox(height: 14),
                    _bagianTidakLaku(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _pemilihRentang() {
    return Material(
      color: KaataTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pilihRentang,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(Icons.event_outlined,
                  size: 18, color: KaataTheme.brandOf(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_tgl.format(_dari)} — ${_tgl.format(_sampai)}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: KaataTheme.mutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kartuRingkasan() {
    return _Kartu(
      ikon: Icons.insights_outlined,
      judul: 'Ringkasan',
      anak: [
        Row(
          children: [
            Expanded(
              child: _Angka(
                  label: 'Omzet', nilai: _rp.format(_ringkasan.omzet)),
            ),
            Expanded(
              child: _Angka(
                  label: 'Pesanan',
                  nilai: _ringkas.format(_ringkasan.jumlahPesanan)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Angka(
                  label: 'Rata-rata transaksi',
                  nilai: _rp.format(_ringkasan.rataTransaksi)),
            ),
            Expanded(
              child: _Angka(
                  label: 'Porsi terjual',
                  nilai: _ringkas.format(_ringkasan.menuTerjual)),
            ),
          ],
        ),
      ],
    );
  }

  /// Rentang yang paling sering dipakai, sekali ketuk.
  ///
  /// Pemilih rentang penuh tetap ada di atasnya. Yang diganti bukan
  /// keleluasaannya melainkan ongkos pertanyaan yang paling sering
  /// diajukan: "minggu ini bagaimana" seharusnya tidak menuntut memilih
  /// dua tanggal di dalam kalender.
  Widget _pintasanRentang() {
    final kini = DateTime.now();
    final hariIni = DateTime(kini.year, kini.month, kini.day);
    final pilihan = <(String, DateTime, DateTime)>[
      ('7 hari', hariIni.subtract(const Duration(days: 6)), hariIni),
      ('30 hari', hariIni.subtract(const Duration(days: 29)), hariIni),
      ('Bulan ini', DateTime(kini.year, kini.month, 1), hariIni),
      (
        'Bulan lalu',
        DateTime(kini.year, kini.month - 1, 1),
        DateTime(kini.year, kini.month, 0),
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (nama, dari, sampai) in pilihan)
          _Pil(
            label: nama,
            aktif: _samaHari(dari, _dari) && _samaHari(sampai, _sampai),
            onTap: () {
              setState(() {
                _dari = dari;
                _sampai = sampai;
              });
              _muat();
            },
          ),
      ],
    );
  }

  static bool _samaHari(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _bagianTren() {
    final muted = KaataTheme.mutedOf(context);
    final nilai = [
      for (final t in _deret)
        switch (_metrik) {
          _Metrik.omzet => t.omzet.toDouble(),
          _Metrik.pesanan => t.jumlahPesanan.toDouble(),
          _Metrik.porsi => t.porsi.toDouble(),
        }
    ];
    final label = [for (final t in _deret) _labelPeriode(t.periode)];

    return _Kartu(
      ikon: Icons.show_chart,
      judul: 'Tren Penjualan',
      anak: [
        // Dua baris pilihan: apa yang digambar, dan sekasar apa.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _Metrik.values)
              _Pil(
                label: m.label,
                aktif: _metrik == m,
                onTap: () => setState(() => _metrik = m),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (kode, nama) in const [
              ('day', 'Harian'),
              ('week', 'Mingguan'),
              ('month', 'Bulanan'),
            ])
              _Pil(
                label: nama,
                aktif: _satuan == kode,
                onTap: () => _gantiSatuan(kode),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (nilai.isEmpty)
          Text('Belum ada penjualan di rentang ini.',
              style: TextStyle(fontSize: 12.5, color: muted))
        else
          SizedBox(
            height: 190,
            child: GrafikTren(
              nilai: nilai,
              label: label,
              format: (v) => _metrik == _Metrik.omzet
                  ? _rp.format(v.round())
                  : '${_ringkas.format(v.round())} ${_metrik.satuan}',
              warna: _metrik.warna,
            ),
          ),
        if (nilai.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_ringkasTren(nilai),
              style: TextStyle(fontSize: 11.5, color: muted)),
        ],
      ],
    );
  }

  /// Perbandingan separuh awal rentang dengan separuh akhirnya.
  ///
  /// Grafik memperlihatkan bentuknya, tapi arah keseluruhan tetap
  /// ditafsirkan orang dengan mata — dan mata membesarkan satu hari
  /// ramai di ujung kanan jadi "sedang naik". Kalimat ini menyebut
  /// arahnya dengan angka.
  String _ringkasTren(List<double> nilai) {
    if (nilai.length < 4) return 'Rentangnya terlalu pendek untuk dibandingkan.';
    final tengah = nilai.length ~/ 2;
    final awal = nilai.take(tengah).fold<double>(0, (a, b) => a + b);
    final akhir = nilai.skip(tengah).fold<double>(0, (a, b) => a + b);
    if (awal <= 0) {
      return akhir > 0 ? 'Naik dari nol di separuh awal rentang.' : '';
    }
    final beda = (akhir - awal) / awal * 100;
    final arah = beda >= 0 ? 'naik' : 'turun';
    return 'Separuh akhir rentang $arah ${beda.abs().toStringAsFixed(1)}% '
        'dibanding separuh awalnya.';
  }

  String _labelPeriode(DateTime d) => switch (_satuan) {
        'month' => DateFormat('MMM yy', 'id_ID').format(d),
        'week' => DateFormat('d MMM', 'id_ID').format(d),
        _ => DateFormat('d/M', 'id_ID').format(d),
      };

  Widget _bagianPembagian() {
    final muted = KaataTheme.mutedOf(context);
    final total = _potong.fold<int>(0, (a, b) => a + b.omzet);

    return _Kartu(
      ikon: Icons.pie_chart_outline,
      judul: 'Dari Mana Omzetnya',
      keterangan: _dimensi == _Dimensi.kategori
          // Service per tagihan dan potongan tidak menempel di baris menu
          // mana pun, jadi jumlahnya memang tidak sama dengan omzet.
          ? 'Dihitung dari harga baris menunya — belum termasuk service '
              'dan potongan per tagihan.'
          : null,
      anak: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in _Dimensi.values)
              _Pil(
                label: d.label,
                aktif: _dimensi == d,
                onTap: () => _gantiDimensi(d),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_potong.isEmpty)
          Text('Belum ada penjualan di rentang ini.',
              style: TextStyle(fontSize: 12.5, color: muted))
        else ...[
          SizedBox(
            height: 170,
            child: GrafikPotong(
              nilai: [for (final p in _potong) p.omzet.toDouble()],
              tengahAtas: 'Total',
              tengahBawah: _rp.format(total),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _potong.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: warnaPotong(i),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(_dimensi.namakan(_potong[i].kunci),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    total <= 0
                        ? '—'
                        : '${(_potong[i].omzet / total * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                  const SizedBox(width: 10),
                  Text(_rp.format(_potong[i].omzet),
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _bagianTerlaris() {
    final muted = KaataTheme.mutedOf(context);
    // Batang dibandingkan dengan yang teratas, bukan dengan omzet total.
    // Batang yang semuanya pendek karena dibagi total tidak membedakan
    // apa pun — dan membedakan justru satu-satunya gunanya.
    final tertinggi = _terlaris.isEmpty ? 1 : _terlaris.first.qty;

    return _Kartu(
      ikon: Icons.local_fire_department_outlined,
      judul: 'Menu Terlaris',
      anak: [
        if (_terlaris.isEmpty)
          Text('Belum ada penjualan di rentang ini.',
              style: TextStyle(fontSize: 12.5, color: muted))
        else
          for (var i = 0; i < _terlaris.length; i++)
            _BarisMenu(
              nomor: i + 1,
              nama: _terlaris[i].nama,
              kanan: '${_ringkas.format(_terlaris[i].qty)} porsi',
              bawah: _rp.format(_terlaris[i].omzet),
              rasio: tertinggi == 0 ? 0 : _terlaris[i].qty / tertinggi,
            ),
      ],
    );
  }

  Widget _bagianJamRamai() {
    final muted = KaataTheme.mutedOf(context);
    if (_jamRamai.isEmpty) {
      return _Kartu(
        ikon: Icons.schedule_outlined,
        judul: 'Jam Ramai',
        anak: [
          Text('Belum ada pesanan di rentang ini.',
              style: TextStyle(fontSize: 12.5, color: muted)),
        ],
      );
    }

    final teramai = _jamRamai
        .reduce((a, b) => a.jumlahPesanan >= b.jumlahPesanan ? a : b);

    // Dua puluh empat kotak, lalu diisi jam yang ada barisnya. Jam sepi
    // tidak punya barisnya sendiri di server, dan melompatinya membuat
    // sumbu waktunya tidak lagi seragam.
    final perJam = List<double>.filled(24, 0);
    for (final j in _jamRamai) {
      if (j.jam >= 0 && j.jam < 24) perJam[j.jam] = j.jumlahPesanan.toDouble();
    }

    return _Kartu(
      ikon: Icons.schedule_outlined,
      judul: 'Jam Ramai',
      anak: [
        Text(
          'Paling ramai pukul ${teramai.label} — '
          '${_ringkas.format(teramai.jumlahPesanan)} pesanan.',
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 160,
          child: GrafikJam(
            perJam: perJam,
            tooltip: (jam, nilai) =>
                '${jam.toString().padLeft(2, '0')}:00\n'
                '${_ringkas.format(nilai.round())} pesanan',
          ),
        ),
        const SizedBox(height: 6),
        Text('Jam WIB', style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }

  Widget _bagianTidakLaku() {
    final muted = KaataTheme.mutedOf(context);
    return _Kartu(
      ikon: Icons.remove_shopping_cart_outlined,
      judul: 'Menu Tidak Laku',
      keterangan: 'Tidak terjual satu porsi pun sepanjang rentang ini.',
      anak: [
        if (_tidakLaku.isEmpty)
          Text('Semua menu terjual. Bagus.',
              style: TextStyle(fontSize: 12.5, color: muted))
        else
          for (final m in _tidakLaku)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.nama,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text(m.kategori,
                            style: TextStyle(fontSize: 11.5, color: muted)),
                      ],
                    ),
                  ),
                  Text(_rp.format(m.harga),
                      style: TextStyle(fontSize: 12.5, color: muted)),
                ],
              ),
            ),
      ],
    );
  }
}

class _Kosong extends StatelessWidget {
  final DateTime dari;
  final DateTime sampai;

  const _Kosong({required this.dari, required this.sampai});

  @override
  Widget build(BuildContext context) {
    final tgl = DateFormat('d MMM yyyy', 'id_ID');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined,
              size: 40, color: KaataTheme.mutedOf(context)),
          const SizedBox(height: 10),
          Text(
            'Belum ada pesanan lunas antara\n'
            '${tgl.format(dari)} dan ${tgl.format(sampai)}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: KaataTheme.mutedOf(context)),
          ),
        ],
      ),
    );
  }
}

class _Kartu extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String? keterangan;
  final List<Widget> anak;

  const _Kartu({
    required this.ikon,
    required this.judul,
    this.keterangan,
    required this.anak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
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
              Icon(ikon, size: 17, color: KaataTheme.brandOf(context)),
              const SizedBox(width: 8),
              Text(judul,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5)),
            ],
          ),
          if (keterangan != null) ...[
            const SizedBox(height: 3),
            Text(keterangan!,
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context))),
          ],
          const SizedBox(height: 12),
          ...anak,
        ],
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  final String label;
  final String nilai;

  const _Angka({required this.label, required this.nilai});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context))),
        const SizedBox(height: 2),
        Text(nilai,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _BarisMenu extends StatelessWidget {
  final int nomor;
  final String nama;
  final String kanan;
  final String bawah;
  final double rasio;

  const _BarisMenu({
    required this.nomor,
    required this.nama,
    required this.kanan,
    required this.bawah,
    required this.rasio,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('$nomor.',
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
              Expanded(
                child: Text(nama,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text(kanan,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rasio.clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: KaataTheme.softFillOf(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(bawah, style: TextStyle(fontSize: 11.5, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yang digambar garis trennya.
enum _Metrik {
  omzet('Omzet', '', Color(0xFF6366F1)),
  pesanan('Pesanan', 'pesanan', Color(0xFF10B981)),
  porsi('Porsi Terjual', 'porsi', Color(0xFFF59E0B));

  final String label;
  final String satuan;
  final Color warna;

  const _Metrik(this.label, this.satuan, this.warna);
}

/// Sudut pandang pembagian omzetnya.
enum _Dimensi {
  caraBayar('Cara Bayar', 'payment_method'),
  jenisPesanan('Jenis Pesanan', 'order_type'),
  asalPesanan('Asal Pesanan', 'source'),
  kategori('Kategori Menu', 'category');

  final String label;
  final String kode;

  const _Dimensi(this.label, this.kode);

  /// Nilai apa adanya dari basis data ditulis untuk dibaca orang.
  ///
  /// "qris_static" dan "dine_in" adalah nama kolom, bukan bahasa. Yang
  /// membaca laporan ini pemilik warung, dan istilah basis data yang
  /// bocor ke layarnya membuat laporan terbaca seperti hasil ekspor
  /// mentah — persis kesan yang tidak boleh ditinggalkan laporan.
  String namakan(String kunci) => switch (kunci) {
        'cash' => 'Tunai',
        'qris' => 'QRIS Dinamis',
        'qris_static' => 'QRIS Statis',
        'transfer' => 'Transfer',
        'dine_in' => 'Makan di Tempat',
        'take_away' => 'Bawa Pulang',
        'kasir' => 'Input Kasir',
        'customer' => 'Pesan Sendiri',
        'lainnya' => 'Lainnya',
        _ => kunci,
      };
}

/// Tombol pilihan kecil yang dipakai pemilih rentang, metrik, satuan
/// waktu, dan dimensi.
///
/// Satu bentuk untuk empat barisan pilihan. Empat gaya tombol berbeda di
/// satu layar membuat orang mengira keempatnya bekerja dengan cara yang
/// berbeda pula.
class _Pil extends StatelessWidget {
  final String label;
  final bool aktif;
  final VoidCallback onTap;

  const _Pil({required this.label, required this.aktif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = KaataTheme.brandOf(context);
    return Material(
      color: aktif ? brand : KaataTheme.softFillOf(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: aktif ? FontWeight.bold : FontWeight.w500,
              color: aktif ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }
}
