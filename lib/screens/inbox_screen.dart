import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/announcement_repository.dart';
import '../models/announcement.dart';
import '../providers/auth_provider.dart';
import '../widgets/update_download_button.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';
import '../widgets/app_toast.dart';
import '../widgets/count_badge.dart';

/// Kotak masuk pengumuman KaataGo, untuk semua peran yang login.
///
/// Isinya sama untuk semua orang; yang per orang hanyalah sudah dibaca
/// atau sudah dihapus. Menghapus di sini menyembunyikannya dari inbox
/// orang itu saja — pengumumannya sendiri tetap ada untuk yang lain.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _repo = AnnouncementRepository();
  List<Announcement> _items = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _selecting = false;
  String? _error;

  String? get _email => context.read<AuthProvider>().user?.email;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final email = _email;
    if (email == null) {
      setState(() {
        _loading = false;
        _items = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.inboxFor(
        email,
        restoId: context.read<AuthProvider>().restoId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected.removeWhere((id) => !items.any((i) => i.id == id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _open(Announcement item) async {
    final email = _email;
    if (email != null && !item.read) {
      // Ditandai dibaca secara optimistis: kalau penulisannya gagal,
      // paling buruk penanda birunya muncul lagi nanti — jauh lebih baik
      // daripada menahan pembukaan pesannya karena jaringan lambat.
      setState(() {
        _items = [
          for (final i in _items) i.id == item.id ? i.copyWith(read: true) : i,
        ];
      });
      _repo.markRead(email, item.id).catchError((_) {});
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(item.title, style: const TextStyle(fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('d MMMM yyyy, HH:mm', 'id_ID').format(item.createdAt.toWib()),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              if (item.hasImage) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  // Gambar promo ditampilkan utuh, bukan dipotong pas
                  // kotak: yang dipotong biasanya justru nominal diskon
                  // atau tanggal berlakunya, yang ditaruh perancangnya
                  // di tepi gambar.
                  child: Image.memory(
                    base64Decode(item.imageBase64!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(item.body, style: const TextStyle(fontSize: 14, height: 1.45)),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.downloadUrl != null && item.downloadUrl!.isNotEmpty)
                UpdateDownloadButton(url: item.downloadUrl!),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected({bool all = false}) async {
    final email = _email;
    if (email == null) return;
    final ids = all ? _items.map((i) => i.id).toList() : _selected.toList();
    if (ids.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_outline, size: 38, color: Colors.red),
        title: Text(all ? 'Hapus semua pesan?' : 'Hapus ${ids.length} pesan?'),
        content: const Text(
          'Pesan hanya hilang dari kotak masuk kamu. Pengguna lain tetap '
          'menerimanya seperti biasa.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _repo.deleteForUser(email, ids);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selecting = false;
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  List<Announcement> _itemsIn(AnnouncementCategory category) =>
      _items.where((i) => i.category == category).toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: AnnouncementCategory.values.length,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '${_selected.length} dipilih' : 'Kotak Masuk'),
        // Tabnya tetap ada saat sedang memilih pesan: pilihan yang
        // dibuat di satu tab tidak hilang saat berpindah, dan
        // menyembunyikan tabnya justru membuat orang mengira pilihannya
        // batal.
        bottom: TabBar(
          tabs: [
            for (final c in AnnouncementCategory.values)
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(kAnnouncementCategoryLabels[c]!),
                    if (_itemsIn(c).where((i) => !i.read).isNotEmpty) ...[
                      const SizedBox(width: 6),
                      CountBadge(
                        count: _itemsIn(c).where((i) => !i.read).length,
                        fontSize: 9,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (_items.isNotEmpty && !_selecting)
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: 'Pilih pesan',
              onPressed: () => setState(() => _selecting = true),
            ),
          if (_selecting) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Pilih semua',
              onPressed: () => setState(() {
                _selected
                  ..clear()
                  ..addAll(_items.map((i) => i.id));
              }),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus terpilih',
              onPressed: _selected.isEmpty ? null : () => _deleteSelected(),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Batal',
              onPressed: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : TabBarView(
                  children: [
                    for (final c in AnnouncementCategory.values) _categoryList(c),
                  ],
                ),
    );
  }

  Widget _categoryList(AnnouncementCategory category) {
    final items = _itemsIn(category);
    final unread = items.where((i) => !i.read).length;

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        // Daftar kosong tetap harus bisa ditarik untuk memuat ulang —
        // tanpa fisik yang bisa digulir, gerakannya tidak pernah
        // terbaca. Itulah gunanya AlwaysScrollable di sini.
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
            Icon(Icons.mark_email_read_outlined, size: 46, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              category == AnnouncementCategory.update
                  ? 'Belum ada pemberitahuan versi baru.'
                  : 'Belum ada pengumuman.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (unread > 0 && !_selecting)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('$unread pesan belum dibaca',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
              ),
            for (final item in items) _tile(item),
            const SizedBox(height: 14),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Hapus Semua'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => _deleteSelected(all: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Announcement item) {
    final selected = _selected.contains(item.id);
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: item.read ? Colors.white : KaataTheme.brand.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? KaataTheme.brand : Colors.grey.shade300,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        leading: _selecting
            ? Checkbox(
                value: selected,
                onChanged: (_) => setState(() {
                  selected ? _selected.remove(item.id) : _selected.add(item.id);
                }),
              )
            : Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: KaataTheme.brand.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  item.version != null ? Icons.system_update : Icons.campaign_outlined,
                  size: 19,
                  color: KaataTheme.brand,
                ),
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontWeight: item.read ? FontWeight.w600 : FontWeight.bold,
                  fontSize: 14.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!item.read)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: KaataTheme.brand,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(item.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            const SizedBox(height: 3),
            Text(dateFmt.format(item.createdAt.toWib()),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
        onTap: _selecting
            ? () => setState(() {
                  selected ? _selected.remove(item.id) : _selected.add(item.id);
                })
            : () => _open(item),
        onLongPress: () => setState(() {
          _selecting = true;
          _selected.add(item.id);
        }),
      ),
    );
  }
}

/// Kegagalan memuat kotak masuk.
///
/// Dipisah jadi widget sendiri sejak daftarnya dibagi dua tab: galat
/// jaringan berlaku untuk keduanya sekaligus, jadi ditampilkan
/// menggantikan seluruh isi layar, bukan diulang di tiap tab.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Gagal memuat kotak masuk.\n$message',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
