import 'package:flutter/material.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../utils/kontak_merchant.dart';
import '../widgets/app_toast.dart';
import '../widgets/kotak_cari.dart';
import '../widgets/resto_logo_avatar.dart';
import 'restaurant_create_screen.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';

/// Super Admin's "List Resto" — every registered restaurant, tap one to
/// edit its name/address/category, and a switch to activate/deactivate
/// it. A deactivated resto disappears from the customer's "Pilih Resto"
/// list, and its employees are blocked from logging in (see
/// AuthProvider._checkEmployeeRole). Distinct from the customer-facing
/// [RestaurantListScreen] (browse-to-order, no edit capability).
class RestaurantManageListScreen extends StatefulWidget {
  const RestaurantManageListScreen({super.key});

  @override
  State<RestaurantManageListScreen> createState() => _RestaurantManageListScreenState();
}

class _RestaurantManageListScreenState extends State<RestaurantManageListScreen> {
  final _repo = RestaurantRepository();
  List<Restaurant> _restaurants = [];

  final _cariCtrl = TextEditingController();
  String _cari = '';

  /// Merchant yang cocok dengan yang dicari. Nama dan alamat sekaligus:
  /// yang mencari sebuah cabang lebih sering ingat jalannya daripada
  /// nama resminya.
  List<Restaurant> get _tersaring => [
        for (final r in _restaurants)
          if (cocokCari(_cari, [r.name, r.address, r.category])) r
      ];
  bool _loading = true;

  /// Menampilkan yang sudah dihapus.
  ///
  /// Tertutup secara bawaan: daftar ini dipakai tiap hari untuk resto
  /// yang berjalan, dan yang sudah dihapus cuma dicari saat ada yang
  /// perlu dikembalikan.
  bool _tampilkanTerhapus = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _repo.getAll(includeDeleted: _tampilkanTerhapus);
    if (!mounted) return;
    setState(() {
      _restaurants = all;
      _loading = false;
    });
  }

  Future<void> _hapus(Restaurant resto) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus merchant?', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(resto.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              'Datanya tidak dibuang — pesanan, jurnal, dan tagihannya tetap '
              'tersimpan dan bisa dikembalikan lagi.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Yang berhenti: pelanggan tidak bisa memesan, katalognya '
              'terkunci, dan tagihan langganan bulan depan tidak terbit.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (yakin != true) return;
    try {
      await _repo.setDeleted(resto.id, true);
      if (!mounted) return;
      showAppToast(context, '${resto.name} dihapus dari daftar.');
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  Future<void> _kembalikan(Restaurant resto) async {
    try {
      await _repo.setDeleted(resto.id, false);
      if (!mounted) return;
      // Sengaja tidak ikut menyalakan kembali `active`: resto yang
      // dikembalikan belum tentu siap langsung melayani pesanan, dan
      // menyalakannya diam-diam berarti pelanggan bisa memesan sebelum
      // ada yang memeriksa menunya.
      showAppToast(context,
          '${resto.name} dikembalikan. Aktifkan lagi kalau sudah siap melayani.');
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal mengembalikan: $e', isError: true);
    }
  }

  Future<void> _edit(Restaurant resto) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RestaurantCreateScreen(existing: resto)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('List Merchant'),
        actions: [
          IconButton(
            tooltip: _tampilkanTerhapus
                ? 'Sembunyikan yang dihapus'
                : 'Tampilkan yang dihapus',
            icon: Icon(_tampilkanTerhapus
                ? Icons.visibility_off_outlined
                : Icons.delete_sweep_outlined),
            onPressed: () {
              setState(() => _tampilkanTerhapus = !_tampilkanTerhapus);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RestaurantCreateScreen()),
          );
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Merchant Baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Text('Belum ada merchant terdaftar.'))
              : Column(
                children: [
                  KotakCari(
                    controller: _cariCtrl,
                    petunjuk: 'Cari nama, alamat, atau kategori merchant',
                    onUbah: (v) => setState(() => _cari = v),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  ),
                  if (_tersaring.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text('Tidak ada merchant yang cocok dengan '
                            '"$_cari".'),
                      ),
                    )
                  else
                  Expanded(
                  child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, kFabSafeBottom),
                    itemCount: _tersaring.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final resto = _tersaring[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: RestoLogoAvatar(
                            logoBase64: resto.logoBase64,
                            active: resto.active,
                          ),
                          title: Text(resto.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          // Kontaknya tidak ditulis di sini.
                          //
                          // Yang dicari orang di daftar ini adalah
                          // merchantnya, bukan nomornya — dan dua baris
                          // tambahan berisi "belum diisi" membuat
                          // daftarnya dua kali lebih panjang tanpa satu
                          // pun keputusan yang jadi lebih mudah. Yang
                          // benar-benar berguna cuma bisa-tidaknya
                          // dihubungi, dan itu sudah dijawab ada
                          // tidaknya ikon WhatsApp di sebelah kanan.
                          subtitle: Text(
                            [
                              if (resto.category != null) resto.category!,
                              resto.address.isEmpty
                                  ? 'Alamat belum diisi'
                                  : resto.address,
                              if (resto.isDeleted)
                                'Dihapus'
                              else if (!resto.active)
                                'Nonaktif',
                            ].join(' • '),
                            style: resto.active && !resto.isDeleted
                                ? null
                                : TextStyle(color: Colors.red.shade400),
                          ),
                          // Semua tindakan berkumpul di satu tombol.
                          //
                          // Sebelumnya ada empat kontrol berjejer di tiap
                          // baris — chat, saklar aktif, ubah, hapus — dan
                          // pada nama merchant yang panjang keempatnya
                          // berdesakan sampai teksnya terpotong. Yang
                          // lebih berbahaya: saklar aktif dan tombol
                          // hapus bersebelahan, dua tindakan yang
                          // akibatnya jauh berbeda dalam jarak satu ibu
                          // jari.
                          trailing: resto.isDeleted
                              ? TextButton.icon(
                                  onPressed: () => _kembalikan(resto),
                                  icon: const Icon(Icons.restore, size: 18),
                                  label: const Text('Kembalikan'),
                                )
                              : PopupMenuButton<String>(
                                  tooltip: 'Tindakan',
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (pilihan) {
                                    switch (pilihan) {
                                      case 'wa':
                                        bukaWhatsApp(
                                          context,
                                          resto.phone,
                                          pesan: 'Halo ${resto.name}, '
                                              'saya dari KaataGo.',
                                        );
                                      case 'ubah':
                                        _edit(resto);
                                      case 'hapus':
                                        _hapus(resto);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    // Hanya muncul kalau nomornya benar-
                                    // benar bisa dihubungi. Tombol yang
                                    // membuka WhatsApp lalu berhenti di
                                    // "nomor tidak valid" terlihat
                                    // seperti WhatsApp-nya yang rusak,
                                    // bukan datanya yang kosong.
                                    if (punyaWhatsApp(resto.phone))
                                      const PopupMenuItem(
                                        value: 'wa',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          leading: Icon(Icons.chat_outlined,
                                              color: Color(0xFF25D366)),
                                          title: Text('Chat WhatsApp'),
                                        ),
                                      ),
                                    // Aktif/nonaktif ada di dalam sini:
                                    // mematikan merchant membuat
                                    // karyawannya tidak bisa masuk dan
                                    // pelanggannya tidak bisa memesan,
                                    // dan itu bukan tindakan sekali
                                    // sentuh dari daftar.
                                    const PopupMenuItem(
                                      value: 'ubah',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('Ubah'),
                                        subtitle: Text('Termasuk aktif/nonaktif',
                                            style: TextStyle(fontSize: 11)),
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'hapus',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: Icon(Icons.delete_outline,
                                            color: Colors.red),
                                        title: Text('Hapus',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
                  ),
                  ),
                ],
              ),
    );
  }

  @override
  void dispose() {
    _cariCtrl.dispose();
    super.dispose();
  }
}
