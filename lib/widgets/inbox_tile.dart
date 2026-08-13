import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/announcement_repository.dart';
import '../providers/auth_provider.dart';
import '../screens/inbox_screen.dart';
import 'hub_menu_tile.dart';

/// Pintu masuk kotak pesan di setiap hub, lengkap dengan jumlah pesan
/// yang belum dibaca.
///
/// Angkanya dimuat sekali saat hub dibuka. Memantaunya terus-menerus
/// berarti satu koneksi realtime lagi hanya demi sebuah titik merah —
/// mahal untuk sesuatu yang isinya berubah beberapa kali sebulan.
class InboxTile extends StatefulWidget {
  const InboxTile({super.key});

  @override
  State<InboxTile> createState() => _InboxTileState();
}

class _InboxTileState extends State<InboxTile> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final email = context.read<AuthProvider>().user?.email;
    if (email == null) return;
    try {
      final items = await AnnouncementRepository().inboxFor(email);
      if (!mounted) return;
      setState(() => _unread = items.where((i) => !i.read).length);
    } catch (_) {
      // Offline — biarkan tanpa angka, jangan menampilkan galat untuk
      // sesuatu sesepele penanda jumlah.
    }
  }

  @override
  Widget build(BuildContext context) {
    return HubMenuTile(
      icon: Icons.inbox_outlined,
      title: 'Kotak Masuk',
      subtitle: _unread > 0
          ? '$_unread pesan belum dibaca'
          : 'Pengumuman & info versi terbaru KaataGo',
      color: const Color(0xFF0EA5E9),
      // Angkanya pindah dari judul ke penanda merah. Sebagai tulisan
      // "(3 baru)" ia terbaca sebagai bagian dari nama menunya dan ikut
      // luput bersama seluruh baris; sebagai bulatan merah ia satu-
      // satunya benda berwarna itu di layar.
      badgeCount: _unread,
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const InboxScreen()),
        );
        _loadUnread();
      },
    );
  }
}
