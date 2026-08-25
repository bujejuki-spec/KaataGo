import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/kaata_logo.dart';
import '../widgets/language_theme_toggle.dart';
import '../widgets/resto_switcher.dart';
import '../widgets/support_fab.dart';
import 'web_menu.dart';

/// Kerangka versi web: menu di sidebar, isinya di sebelah kanan.
///
/// Bentuk beranda ponsel tidak dipindahkan apa adanya ke layar lebar.
/// Di ponsel, menu ditumpuk di balik kelompok karena layarnya sempit dan
/// tiap ketukan mahal. Di layar 1400 piksel, tumpukan yang sama justru
/// menyembunyikan hal yang sebenarnya muat ditampilkan seluruhnya — dan
/// memaksa orang mengetuk dua kali untuk sampai ke tempat yang bisa
/// terlihat sejak awal.
///
/// Isinya tetap layar yang sama persis dengan versi ponselnya. Tidak ada
/// satu pun layar yang ditulis ulang untuk web: dua salinan dari layar
/// yang sama akan berpisah pada perbaikan berikutnya, dan yang tertinggal
/// adalah yang lebih jarang dibuka.
class WebShellScreen extends StatefulWidget {
  const WebShellScreen({super.key});

  @override
  State<WebShellScreen> createState() => _WebShellScreenState();
}

class _WebShellScreenState extends State<WebShellScreen> {
  int _terpilih = 0;

  /// Lebar minimal supaya sidebar dan isinya sama-sama layak.
  ///
  /// Di bawah ini — jendela yang disempitkan, atau tablet yang diputar —
  /// sidebarnya berubah jadi laci yang ditarik dari tepi. Sidebar tetap
  /// selebar 260 piksel pada jendela 800 piksel menyisakan ruang isi
  /// yang lebih sempit daripada ponsel.
  static const _lebarMinimal = 1000.0;
  static const _lebarSidebar = 260.0;

  /// Tombol mengambang KaataGo Support — hanya untuk sisi merchant.
  ///
  /// Di versi HP tombol ini menempel di beranda tiap peran merchant,
  /// dan beranda itu tidak dipakai sama sekali di web. Tanpa dipasang
  /// di kerangkanya, pegawai merchant yang bekerja dari konsol tidak
  /// punya satu pun jalan untuk mengadu atau bertanya.
  ///
  /// KaataGo Admin tidak mendapatkannya. Dia berada di sisi seberang
  /// percakapan yang sama — yang dibukanya lewat menu Customer Service
  /// — dan tombol mengadu di layarnya sendiri hanya membuat dia bisa
  /// membuat tiket yang ujungnya dia jawab sendiri.
  ///
  /// Digeser ke atas karena layar di sebelahnya membawa tombol
  /// mengambangnya sendiri, dan keduanya berebut sudut yang sama:
  /// tanpa jarak ini yang satu menutupi yang lain, dan yang tertutup
  /// tampak seperti hilang.
  Widget? _support(AuthProvider auth) {
    if (auth.isSuperAdmin) return null;
    return const Padding(
      padding: EdgeInsets.only(bottom: 72),
      child: SupportFab(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final menu = menuWebUntuk(auth);

    if (menu.isEmpty) {
      // Tidak seharusnya sampai ke sini — RootScreen sudah menyaringnya.
      return const Scaffold(
        body: Center(child: Text('Peran ini belum punya versi web.')),
      );
    }

    final terpilih = _terpilih.clamp(0, menu.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final lebar = constraints.maxWidth >= _lebarMinimal;
        final isi = KeyedSubtree(
          // Kunci per tujuan DAN per merchant.
          //
          // Tanpa kunci, berpindah menu memakai ulang State layar
          // sebelumnya kalau jenis widgetnya kebetulan sama. Tanpa
          // restoId di dalamnya, berpindah cabang meninggalkan data
          // cabang lama di layar yang sudah terlanjur memuatnya.
          key: ValueKey('${menu[terpilih].judul}|${auth.restoId}'),
          child: menu[terpilih].layar(),
        );

        if (!lebar) {
          return Scaffold(
            floatingActionButton: _support(auth),
            appBar: AppBar(title: Text(menu[terpilih].judul)),
            drawer: Drawer(
              child: _Sidebar(
                menu: menu,
                terpilih: terpilih,
                onPilih: (i) {
                  setState(() => _terpilih = i);
                  Navigator.pop(context);
                },
              ),
            ),
            body: isi,
          );
        }

        return Scaffold(
          floatingActionButton: _support(auth),
          body: Row(
            children: [
              SizedBox(
                width: _lebarSidebar,
                child: Material(
                  color: KaataTheme.surfaceOf(context),
                  child: _Sidebar(
                    menu: menu,
                    terpilih: terpilih,
                    onPilih: (i) => setState(() => _terpilih = i),
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: KaataTheme.borderOf(context)),
              // Layar yang dipilih membawa AppBar-nya sendiri. Itu
              // disengaja: judul, tombol, dan tab yang sudah ada di
              // versi ponselnya tetap berada di tempat yang sama.
              Expanded(child: isi),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<MenuWeb> menu;
  final int terpilih;
  final ValueChanged<int> onPilih;

  const _Sidebar({
    required this.menu,
    required this.terpilih,
    required this.onPilih,
  });

  /// Menanyakan dulu, lalu benar-benar keluar.
  ///
  /// [confirmLogout] hanya memunculkan dialognya dan mengembalikan
  /// jawabannya — ia tidak mengeluarkan siapa pun. Memanggilnya saja,
  /// tanpa membaca jawabannya, menghasilkan tombol yang terlihat
  /// bekerja: dialognya muncul, "Keluar" bisa ditekan, dialognya
  /// menutup, dan sesinya utuh seperti semula.
  Future<void> _keluar(BuildContext context) async {
    if (!await confirmLogout(context)) return;
    if (!context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final muted = KaataTheme.mutedOf(context);
    final nama = auth.employeeName?.trim();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [KaataTheme.brand, KaataTheme.brandDark],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KaataLogo(size: 34),
              const SizedBox(height: 10),
              Text(
                (nama == null || nama.isEmpty) ? 'KaataGo' : nama,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${auth.roleLabel ?? ''} • ${auth.user?.email ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const RestoSwitcher(),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: menu.length,
            itemBuilder: (context, i) {
              final m = menu[i];
              final aktif = i == terpilih;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.kelompok != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(18, i == 0 ? 10 : 18, 18, 6),
                      child: Text(
                        m.kelompok!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: muted,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 1),
                    child: Material(
                      color: aktif
                          ? KaataTheme.brand.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => onPilih(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                m.ikon,
                                size: 18,
                                color: aktif
                                    ? KaataTheme.brandOf(context)
                                    : muted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  m.judul,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: aktif
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: aktif
                                        ? KaataTheme.brandOf(context)
                                        : KaataTheme.textOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: KaataTheme.borderOf(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
          child: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                const AppearanceIconButton(),
                const SizedBox(width: 6),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _keluar(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Keluar'),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
