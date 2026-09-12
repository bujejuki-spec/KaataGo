import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/menu_access_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/menu_access.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/katalog_menu.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/kotak_cari.dart';
import '../widgets/responsive.dart';

/// Parameter akses menu, per merchant dan per peran.
///
/// Yang diatur di sini adalah apa yang MUNCUL dan apa yang boleh
/// DIUBAH — bukan hak akses di server. RLS tetap lantai keamanannya dan
/// tidak disentuh sama sekali, jadi parameter ini hanya bisa
/// mempersempit apa yang sudah boleh dilakukan sebuah peran. Memberi
/// kasir sebuah menu di sini tidak membuat servernya mengizinkan apa
/// pun — yang terjadi cuma layar yang terbuka lalu ditolak.
///
/// Karena itu layarnya tidak menawarkan "beri akses": tiap menu sudah
/// berada di tingkat penuh, dan yang dilakukan orang di sini adalah
/// menurunkannya.
class SuperAdminUamScreen extends StatefulWidget {
  const SuperAdminUamScreen({super.key});

  @override
  State<SuperAdminUamScreen> createState() => _SuperAdminUamScreenState();
}

class _SuperAdminUamScreenState extends State<SuperAdminUamScreen> {
  final _restoRepo = RestaurantRepository();
  final _repo = MenuAccessRepository();

  List<Restaurant> _resto = const [];
  Restaurant? _dipilih;

  /// '<peran>|<menu>' → tingkatnya. Yang tidak ada berarti penuh.
  Map<String, TingkatAkses> _akses = {};

  final _cariCtrl = TextEditingController();
  String _cari = '';
  bool _memuat = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _muatResto();
  }

  @override
  void dispose() {
    _cariCtrl.dispose();
    super.dispose();
  }

  Future<void> _muatResto() async {
    try {
      final semua = await _restoRepo.getAll();
      if (!mounted) return;
      setState(() {
        _resto = semua;
        _memuat = false;
      });
      if (semua.isNotEmpty) _pilih(semua.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = pesanGalat(e);
        _memuat = false;
      });
    }
  }

  Future<void> _pilih(Restaurant r) async {
    setState(() {
      _dipilih = r;
      _memuat = true;
      _galat = null;
    });
    try {
      final rows = await _repo.untukResto(r.id);
      if (!mounted) return;
      setState(() {
        _akses = {
          for (final a in rows) '${a.role}|${a.menuKey}': a.tingkat,
        };
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

  TingkatAkses _tingkat(String peran, String menu) =>
      _akses['$peran|$menu'] ?? TingkatAkses.ubah;

  Future<void> _ubah(String peran, String menu, TingkatAkses tingkat) async {
    final resto = _dipilih;
    if (resto == null) return;
    final sebelum = _tingkat(peran, menu);
    setState(() => _akses['$peran|$menu'] = tingkat);
    try {
      await _repo.simpan(
        MenuAccess(
          restoId: resto.id,
          role: peran,
          menuKey: menu,
          tingkat: tingkat,
        ),
        oleh: context.read<AuthProvider>().user?.email,
      );
    } catch (e) {
      if (!mounted) return;
      // Dikembalikan ke keadaan sebelumnya. Tampilan yang menunjukkan
      // pembatasan yang sebenarnya gagal tersimpan adalah kebohongan
      // yang baru ketahuan saat ada orang mengeluh menunya hilang —
      // atau tidak hilang.
      setState(() => _akses['$peran|$menu'] = sebelum);
      showAppToast(context, 'Gagal menyimpan: ${pesanGalat(e)}',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peran = katalogMenu.keys.toList();

    return DefaultTabController(
      length: peran.length,
      child: Scaffold(
        backgroundColor: KaataTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Akses Menu (UAM)'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final p in peran) Tab(text: labelPeran[p] ?? p),
            ],
          ),
        ),
        body: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Gagal memuat: $_galat',
                          textAlign: TextAlign.center),
                    ),
                  )
                : Column(
                    children: [
                      _pemilihResto(),
                      Expanded(
                        child: TabBarView(
                          children: [
                            for (final p in peran) _daftarMenu(p),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _pemilihResto() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: ResponsiveCenter(
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _dipilih?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Merchant',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final r in _resto)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (id) {
                final r = _resto.where((x) => x.id == id).firstOrNull;
                if (r != null) _pilih(r);
              },
            ),
            const SizedBox(height: 10),
            KotakCari(
              controller: _cariCtrl,
              padding: EdgeInsets.zero,
              petunjuk: 'Cari menu…',
              onUbah: (v) => setState(() => _cari = v.toLowerCase()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _daftarMenu(String peran) {
    final menu = [
      for (final m in katalogMenu[peran] ?? const <String>[])
        if (_cari.isEmpty || m.toLowerCase().contains(_cari)) m,
    ];
    final dibatasi = (katalogMenu[peran] ?? const <String>[])
        .where((m) => _tingkat(peran, m) != TingkatAkses.ubah)
        .length;

    return ResponsiveCenter(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              dibatasi == 0
                  ? 'Belum ada pembatasan — semua menu terbuka penuh.'
                  : '$dibatasi menu dibatasi.',
              style: TextStyle(
                  fontSize: 12.5, color: KaataTheme.mutedOf(context)),
            ),
          ),
          if (menu.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Tidak ada menu yang cocok.',
                    style: TextStyle(color: KaataTheme.mutedOf(context))),
              ),
            )
          else
            for (final m in menu)
              _BarisMenu(
                judul: m,
                tingkat: _tingkat(peran, m),
                onUbah: (t) => _ubah(peran, m, t),
              ),
        ],
      ),
    );
  }
}

class _BarisMenu extends StatelessWidget {
  final String judul;
  final TingkatAkses tingkat;
  final ValueChanged<TingkatAkses> onUbah;

  const _BarisMenu({
    required this.judul,
    required this.tingkat,
    required this.onUbah,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(judul,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<TingkatAkses>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle:
                    WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
              segments: [
                for (final t in TingkatAkses.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {tingkat},
              onSelectionChanged: (pilihan) => onUbah(pilihan.first),
            ),
          ],
        ),
      ),
    );
  }
}
