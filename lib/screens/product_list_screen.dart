import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/akses_menu.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/notification_service.dart';
import '../providers/category_provider.dart';
import '../providers/level_group_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import 'category_management_screen.dart';
import 'level_management_screen.dart';
import 'product_form_screen.dart';
import '../models/product.dart';
import '../models/product_badge.dart';
import '../utils/menu_meta.dart';
import '../utils/pesan_galat.dart';
import '../db/firestore_product_repository.dart';
import '../db/foto_menu_storage.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/product_badge_chips.dart';
import '../widgets/responsive.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoId = context.read<AuthProvider>().restoId;

      final categories = context.read<CategoryProvider>();
      categories.restoId = restoId;
      await categories.load();
      await categories.pullNewFromSupabase();
      await categories.syncAllToSupabase();

      if (!mounted) return;
      // Products used to be synced only by the cashier screen. Now that
      // Kelola Produk is its own menu entry on the Admin hub, it can be
      // opened without ever going there — which left this list showing
      // whatever happened to be in the local database, i.e. nothing at
      // all on a freshly installed device.
      final produk = context.read<ProductProvider>();
      // Diambil sebelum await: sesudahnya pembacaan provider tidak lagi
      // terjamin.
      final setelan = context.read<SettingsProvider>();
      await produk.syncWithResto(restoId);
      await setelan.syncWithResto(restoId);
      if (!mounted || restoId == null) return;
      await context.read<LevelGroupProvider>().load(restoId);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Di web, Kategori dan Level punya menunya sendiri di sidebar.
    //
    // Membiarkan tabnya tetap di sini berarti satu hal yang sama bisa
    // dicapai lewat dua jalan yang tampak berbeda — dan yang satu
    // bersarang di dalam menu yang namanya "Kelola Produk", tempat
    // orang tidak akan mencarinya karena sidebarnya sudah menyebut
    // keduanya di luar.
    if (kIsWeb) {
      return berdasarkanAkses(context, 'Kelola Produk', Scaffold(
        appBar: AppBar(title: const Text('Kelola Produk')),
        body: const _ProductTab(),
      ));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kelola Produk'),
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Pindahkan foto menu',
              onPressed: () => _pindahkanFoto(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Produk'),
              Tab(text: 'Kategori'),
              Tab(text: 'Level'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ProductTab(),
            CategoryManagementScreen(),
            LevelManagementScreen(),
          ],
        ),
      ),
    );
  }

  /// Memindahkan foto menu lama dari kolom tabel ke Supabase Storage.
  ///
  /// Dijalankan dari tombol, bukan diam-diam saat aplikasi dibuka.
  /// Pemindahan yang berjalan sendiri di latar akan mengunggah puluhan
  /// megabita lewat kuota data orangnya tanpa dia tahu, dan kalau gagal
  /// di tengah tidak ada yang bisa dia perbuat karena dia tidak tahu itu
  /// pernah terjadi.
  ///
  /// Aman diulang: yang sudah punya tautan dilewati.
  Future<void> _pindahkanFoto(BuildContext context) async {
    final provider = context.read<ProductProvider>();
    final restoId = provider.restoId;
    if (restoId == null) return;

    // Yang menentukan siapa perlu dipindah adalah SERVER, bukan salinan
    // lokal di HP ini.
    //
    // Pemindahan yang gagal sebelumnya sempat menulis tautannya ke basis
    // data lokal sementara kirimannya ke server hilang di jalan. Sesudah
    // itu salinan lokalnya mengaku semua produk sudah punya tautan, jadi
    // tombol ini menjawab "semua sudah ada di Storage" dan tidak pernah
    // mau mencoba lagi — padahal di server cuma satu yang punya.
    //
    // Salinan yang mengaku lebih maju daripada server adalah cara paling
    // rapi untuk membuat perbaikan berhenti bekerja tanpa ada yang tahu.
    final List<Product> diServer;
    try {
      diServer = await FirestoreProductRepository().getAllOnce(restoId);
    } catch (e) {
      if (!context.mounted) return;
      showAppToast(context, 'Gagal memeriksa foto di server: ${pesanGalat(e)}',
          isError: true);
      return;
    }
    if (!context.mounted) return;

    final perlu = diServer
        .where((p) =>
            (p.photoUrl == null || p.photoUrl!.isEmpty) &&
            p.photoBase64 != null &&
            p.photoBase64!.isNotEmpty)
        .toList();

    if (perlu.isEmpty) {
      if (!context.mounted) return;
      showAppToast(context, 'Semua foto menu sudah ada di Storage.');
      return;
    }

    final lanjut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pindahkan Foto Menu'),
        content: Text(
          '${perlu.length} foto akan dipindahkan ke penyimpanan berkas.\n\n'
          'Menu tetap tampil seperti biasa selama dan sesudahnya. Foto '
          'lamanya belum dihapus, jadi aplikasi versi lama yang masih '
          'terpasang tidak kehilangan gambarnya.',
        ),
        actions: [
          DialogActions(
            confirmLabel: 'Pindahkan',
            onCancel: () => Navigator.pop(dialogContext, false),
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
    if (lanjut != true || !context.mounted) return;

    // Kemajuannya diperlihatkan di dua tempat sekaligus, dan itu
    // disengaja. Dialognya untuk yang menunggui layarnya; notifikasinya
    // untuk yang menekan tombol lalu pergi mengerjakan hal lain —
    // pekerjaan yang lamanya bergantung jumlah menu dan kecepatan
    // jaringan tidak pantas menuntut orang menatapnya sampai selesai.
    final kemajuan = ValueNotifier<int>(0);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: kemajuan,
            builder: (_, n, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: perlu.isEmpty ? null : n / perlu.length,
                ),
                const SizedBox(height: 14),
                Text('Memindahkan foto menu… $n dari ${perlu.length}'),
                const SizedBox(height: 6),
                Text(
                  'Jangan tutup aplikasinya dulu.',
                  style: TextStyle(
                      fontSize: 12, color: KaataTheme.mutedOf(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    final storage = FotoMenuStorage();
    var berhasil = 0;
    var gagal = 0;
    // Alasan kegagalan pertama, apa adanya.
    //
    // Sebelumnya yang gagal cuma dihitung dan alasannya dibuang, jadi
    // yang menekan tombolnya cuma tahu "M gagal" tanpa satu pun petunjuk
    // apakah itu izin, jaringan, atau berkasnya. Angka tanpa sebab tidak
    // bisa ditindaklanjuti siapa pun.
    String? sebab;

    for (final produk in perlu) {
      try {
        final url = await storage.pindahkan(
          restoId: restoId,
          productId: produk.id,
          base64: produk.photoBase64,
        );
        if (url == null) continue;
        // Base64-nya sengaja dipertahankan. Yang mengosongkannya adalah
        // satu perintah SQL terpisah, dijalankan setelah versi barunya
        // tersebar — lihat supabase/foto_menu_storage.sql.
        //
        // Ditunggu sampai server menerimanya. updateProduct biasa
        // mengirimnya tanpa ditunggu, dan perulangan sepanjang ini
        // selesai jauh sebelum kirimannya sampai.
        await provider.simpanTautanFoto(produk, url);
        berhasil++;
      } catch (e) {
        // Satu foto yang gagal tidak menghentikan sisanya. Yang gagal
        // tetap punya base64-nya, jadi menunya tidak kehilangan apa pun
        // — dan tombolnya bisa ditekan lagi nanti.
        gagal++;
        sebab ??= pesanGalat(e);
      }
      kemajuan.value = berhasil + gagal;
      unawaited(NotificationService.instance
          .showPindahFotoProgress(kemajuan.value, perlu.length));
    }

    unawaited(
        NotificationService.instance.showPindahFotoSelesai(berhasil, gagal));

    // Dimuat ulang sekali di akhir, bukan tiap produk: memuat ulang
    // seluruh katalog dua puluh kali berturut-turut membuat layarnya
    // tersendat tanpa memberi tahu apa pun yang baru.
    await provider.load();
    kemajuan.dispose();

    if (!context.mounted) return;
    // Dialog kemajuannya ditutup sebelum hasilnya ditampilkan.
    Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;
    if (gagal == 0) {
      showAppToast(context, '$berhasil foto dipindahkan.');
      return;
    }

    // Dialog, bukan pesan singkat: alasannya datang dari server dan bisa
    // panjang, dan yang perlu membacanya justru sedang mencari tahu
    // kenapa — pesan yang hilang sendiri dalam empat detik tidak
    // menolong.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sebagian Foto Gagal Dipindahkan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$berhasil berhasil, $gagal gagal dari ${perlu.length}.'),
              const SizedBox(height: 10),
              Text('Kenapa gagal:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: KaataTheme.mutedOf(dialogContext))),
              const SizedBox(height: 4),
              Text(sebab ?? 'Tidak diketahui.'),
              const SizedBox(height: 12),
              Text(
                'Foto lamanya tidak hilang — yang gagal masih tersimpan '
                'seperti semula, dan tombolnya bisa ditekan lagi.',
                style: TextStyle(
                    fontSize: 12.5, color: KaataTheme.mutedOf(dialogContext)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}

class _ProductTab extends StatefulWidget {
  const _ProductTab();

  @override
  State<_ProductTab> createState() => _ProductTabState();
}

class _ProductTabState extends State<_ProductTab> {
  /// Bintang dan angka terjual tiap menu.
  ///
  /// Merchant melihat angka yang sama dengan yang dilihat pelanggannya.
  /// Angka penjualan yang hanya ada di laporan tidak pernah dibaca saat
  /// orangnya sedang memutuskan menu mana yang mau diganti.
  MenuMeta _meta = MenuMeta.kosong;

  final _cariCtrl = TextEditingController();
  String _cari = '';

  @override
  void dispose() {
    _cariCtrl.dispose();
    super.dispose();
  }

  /// Daftar yang sudah disaring dan dikelompokkan menurut kategori.
  ///
  /// Isinya campuran: String berarti judul kelompok, Product berarti
  /// barisnya. Satu daftar datar begini membuat ListView tetap membangun
  /// seperlunya — daftar bersarang memaksa seluruh kelompok dibangun
  /// sekaligus meskipun yang terlihat cuma dua baris teratas.
  List<Object> _susun(List<Product> semua) {
    final kata = _cari.trim().toLowerCase();
    final cocok = kata.isEmpty
        ? semua
        : [
            for (final p in semua)
              if (p.name.toLowerCase().contains(kata) ||
                  p.category.toLowerCase().contains(kata))
                p
          ];

    final perKategori = <String, List<Product>>{};
    for (final p in cocok) {
      perKategori.putIfAbsent(p.category, () => []).add(p);
    }
    final kategori = perKategori.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [
      for (final k in kategori) ...[k, ...perKategori[k]!],
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoId = context.read<AuthProvider>().restoId;
      if (restoId == null) return;
      final meta = await muatMenuMeta(restoId);
      if (mounted) setState(() => _meta = meta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      body: Consumer<ProductProvider>(
        builder: (context, provider, _) {
          final products = provider.products;
          if (products.isEmpty) {
            return const Center(child: Text('Belum ada produk. Tambah dulu yuk.'));
          }
          final isi = _susun(products);
          // Kartu, sama seperti Level. Lihat catatan di
          // category_management_screen.dart.
          return ResponsiveCenter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _cariCtrl,
                    onChanged: (v) => setState(() => _cari = v),
                    decoration: InputDecoration(
                      hintText: 'Cari nama produk atau kategori',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _cari.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _cariCtrl.clear();
                                setState(() => _cari = '');
                              },
                            ),
                    ),
                  ),
                ),
                if (isi.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'Tidak ada produk yang cocok dengan "$_cari".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: KaataTheme.mutedOf(context)),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, kFabSafeBottom),
            itemCount: isi.length,
            itemBuilder: (context, index) {
              final baris = isi[index];
              if (baris is String) {
                final jumlah = provider.products
                    .where((x) => x.category == baris)
                    .length;
                return Padding(
                  padding: EdgeInsets.only(
                      top: index == 0 ? 0 : 14, bottom: 6, left: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 15,
                        decoration: BoxDecoration(
                          color: KaataTheme.brand,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(baris,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 6),
                      Text('$jumlah',
                          style: TextStyle(
                              fontSize: 12,
                              color: KaataTheme.mutedOf(context))),
                    ],
                  ),
                );
              }
              final p = baris as Product;
              final stats = _meta.stats[p.id];
              final badges = [
                ...badgeDariKodeList(p.badges),
                if (_meta.diskonProductIds.contains(p.id))
                  ProductBadge.diskon,
              ];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                isThreeLine: badges.isNotEmpty || stats != null,
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.outOfStock ? KaataTheme.mutedOf(context) : null,
                        ),
                      ),
                    ),
                    if (p.outOfStock) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: KaataTheme.tintOf(context, Colors.red),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('HABIS',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: KaataTheme.onTintOf(context, Colors.red))),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.category}'
                      '${p.stock > 0 ? ' • Stok: ${p.stock}' : ''}'
                      ' • ${currency.format(p.price)}',
                    ),
                    if (badges.isNotEmpty || stats != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            for (final b in urutkanBadge(badges))
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: kBadgeWarna[b],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    kBadgeLabel[b]!,
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            Flexible(child: ProductStatsLine(stats: stats)),
                          ],
                        ),
                      ),
                  ],
                ),
                // Ditandai habis dari daftar ini, tanpa membuka
                // formulirnya. Yang menandai biasanya sedang berdiri di
                // dapur sambil melayani, dan formulir produk berisi
                // belasan kolom yang tidak ada hubungannya dengan
                // "ayamnya habis".
                trailing: Switch(
                  value: !p.outOfStock,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (tersedia) =>
                      provider.setOutOfStock(p, !tersedia),
                ),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProductFormScreen(existing: p),
                  ));
                },
                onLongPress: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Hapus produk?'),
                      content: Text('Hapus "${p.name}"?'),
                      actions: [
                        DialogActions(
                          confirmLabel: 'Hapus',
                          destructive: true,
                          onConfirm: () => Navigator.pop(context, true),
                        ),
                      ],
                      actionsAlignment: MainAxisAlignment.center,
                    ),
                  );
                  if (confirm == true) {
                    await provider.deleteProduct(p.id);
                  }
                },
              ),
              );
            },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: !bolehUbahDiSini(context)
          ? null
          : FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ProductFormScreen(),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
