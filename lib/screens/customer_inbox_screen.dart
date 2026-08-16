import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/announcement_repository.dart';
import '../db/guest_order_store.dart';
import '../models/announcement.dart';
import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../widgets/responsive.dart';
import '../widgets/update_download_button.dart';

/// Resto yang kabarnya pantas sampai ke seorang pelanggan.
///
/// Yang pernah dia pesan, ditambah yang sedang dia buka. Tamu dikenali
/// lewat daftar pesanan yang tersimpan di HP-nya sendiri — satu-satunya
/// jejak yang dia punya.
///
/// Fungsi bersama, bukan milik satu layar: kartu Kotak Masuk di hub
/// menghitung yang belum dibaca, dan angkanya harus lahir dari aturan
/// yang sama persis dengan isi layarnya. Dua perhitungan terpisah akan
/// berpisah, dan yang terlihat adalah penanda merah yang menunjuk kotak
/// masuk kosong.
Future<Set<String>> customerRestoIds(BuildContext context) async {
  final ids = <String>{};
  final session = context.read<TableSessionProvider>();
  if (session.restoId != null) ids.add(session.restoId!);

  final client = Supabase.instance.client;
  final email = context.read<AuthProvider>().user?.email;
  try {
    if (email != null) {
      final rows = await client
          .from('orders')
          .select('resto_id')
          .eq('customer_label', email)
          .limit(200);
      for (final r in rows) {
        if (r['resto_id'] != null) ids.add(r['resto_id'] as String);
      }
    } else {
      final guestIds = await GuestOrderStore().ids();
      if (guestIds.isNotEmpty) {
        final rows = await client
            .from('orders')
            .select('resto_id')
            .inFilter('id', guestIds.take(50).toList());
        for (final r in rows) {
          if (r['resto_id'] != null) ids.add(r['resto_id'] as String);
        }
      }
    }
  } catch (_) {
    // Luring — cukup pakai resto yang sedang dibuka.
  }
  return ids;
}

/// Kotak masuk pelanggan.
///
/// Sebelumnya promo resto ditempelkan sebagai pita di atas daftar menu.
/// Itu berarti kabarnya cuma sampai ke orang yang kebetulan sedang
/// membuka menu resto itu — orang yang paling tidak membutuhkannya,
/// karena dia sudah ada di sana dan sedang memesan.
///
/// Di sini kabarnya menunggu di tempat yang bisa dibuka kapan saja,
/// berikut nama restonya. "Diskon 20% hari ini" tanpa nama pengirim
/// adalah kabar yang tidak bisa dipakai: dia tidak tahu harus datang ke
/// mana.
class CustomerInboxScreen extends StatefulWidget {
  const CustomerInboxScreen({super.key});

  @override
  State<CustomerInboxScreen> createState() => _CustomerInboxScreenState();
}

class _CustomerInboxScreenState extends State<CustomerInboxScreen> {
  final _repo = AnnouncementRepository();

  List<Announcement> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = context.read<AuthProvider>().user?.email;
      final items = await _repo.customerInbox(
        email: email,
        restoIds: await customerRestoIds(context),
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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
    final email = context.read<AuthProvider>().user?.email;
    if (email != null && !item.read) {
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.restoName != null)
              Text(item.restoName!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: KaataTheme.brandOf(context))),
            Text(item.title, style: const TextStyle(fontSize: 17)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('d MMMM yyyy, HH:mm', 'id_ID')
                    .format(item.createdAt.toWib()),
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              ),
              if (item.hasImage) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(item.imageBase64!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(item.body,
                  style: const TextStyle(fontSize: 14, height: 1.45)),
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

  List<Announcement> _itemsIn(AnnouncementCategory c) =>
      _items.where((i) => i.category == c).toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: AnnouncementCategory.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kotak Masuk'),
          bottom: TabBar(
            tabs: [
              for (final c in AnnouncementCategory.values)
                Tab(text: kAnnouncementCategoryLabels[c]),
            ],
          ),
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
                          Text('Gagal memuat: $_error',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: _load, child: const Text('Coba Lagi')),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      for (final c in AnnouncementCategory.values) _list(c),
                    ],
                  ),
      ),
    );
  }

  Widget _list(AnnouncementCategory category) {
    final items = _itemsIn(category);

    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                Icon(Icons.mark_email_read_outlined,
                    size: 46, color: KaataTheme.borderOf(context)),
                const SizedBox(height: 12),
                Text(
                  category == AnnouncementCategory.update
                      ? 'Belum ada pemberitahuan versi baru.'
                      : 'Belum ada promo dari resto yang pernah kamu pesan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: KaataTheme.mutedOf(context)),
                ),
              ],
            )
          : ResponsiveCenter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [for (final item in items) _tile(item)],
              ),
            ),
    );
  }

  Widget _tile(Announcement item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _open(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!item.read)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5, right: 8),
                  decoration: BoxDecoration(
                    color: KaataTheme.brandOf(context),
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nama resto di atas judulnya, bukan di bawah.
                    // Yang pertama ingin diketahui pembacanya adalah
                    // "ini dari siapa" — promo dari warung sebelah dan
                    // dari langganannya dibaca dengan cara yang berbeda.
                    if (item.restoName != null)
                      Text(
                        item.restoName!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: KaataTheme.brandOf(context),
                        ),
                      ),
                    Text(
                      item.title,
                      style: TextStyle(
                        fontWeight:
                            item.read ? FontWeight.w600 : FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: KaataTheme.mutedOf(context)),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('d MMM yyyy, HH:mm', 'id_ID')
                          .format(item.createdAt.toWib()),
                      style: TextStyle(
                          fontSize: 11, color: KaataTheme.mutedOf(context)),
                    ),
                  ],
                ),
              ),
              if (item.hasImage) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(item.imageBase64!),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
