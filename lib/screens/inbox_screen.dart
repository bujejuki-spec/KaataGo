import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/announcement_repository.dart';
import '../models/announcement.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';

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
      final items = await _repo.inboxFor(email);
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
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Unduh Versi Terbaru'),
                    onPressed: () => launchUrl(
                      Uri.parse(item.downloadUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menghapus: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((i) => !i.read).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '${_selected.length} dipilih' : 'Kotak Masuk'),
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('Gagal memuat kotak masuk.\n$_error',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600)),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mark_email_read_outlined,
                                size: 46, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'Belum ada pesan.\n'
                              'Pemberitahuan versi baru KaataGo akan muncul di sini.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ResponsiveCenter(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          children: [
                            if (unread > 0 && !_selecting)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text('$unread pesan belum dibaca',
                                    style: TextStyle(
                                        fontSize: 12.5, color: Colors.grey.shade600)),
                              ),
                            for (final item in _items) _tile(item),
                            if (_items.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              TextButton.icon(
                                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                                label: const Text('Hapus Semua'),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: () => _deleteSelected(all: true),
                              ),
                            ],
                          ],
                        ),
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
