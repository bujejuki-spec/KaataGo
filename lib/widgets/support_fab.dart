import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/support_repository.dart';
import '../models/support_ticket.dart';
import '../providers/auth_provider.dart';
import '../screens/support_chat_screen.dart';
import '../screens/support_new_ticket_screen.dart';
import '../theme.dart';
import '../utils/id_time.dart';

/// Tombol mengambang KaataGo Support.
///
/// Satu widget untuk pelanggan maupun pegawai merchant. Keduanya
/// mengadu ke tempat yang sama, dan memisahkannya jadi dua tombol
/// berarti dua alur yang harus sama-sama diingat setiap kali salah
/// satunya berubah.
///
/// Tidak tampil untuk yang belum masuk. Pengaduan tanpa akun tidak punya
/// tempat untuk dibalas — dan pengadu yang tidak pernah menerima
/// jawabannya akan mengira KaataGo mendiamkannya.
class SupportFab extends StatefulWidget {
  const SupportFab({super.key});

  @override
  State<SupportFab> createState() => _SupportFabState();
}

class _SupportFabState extends State<SupportFab> {
  final _repo = SupportRepository();
  List<SupportTicket> _tiket = const [];
  Timer? _pewaktu;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
    // Diperiksa berkala, bukan dialirkan terus-menerus.
    //
    // Aliran realtime untuk penanda di sebuah tombol berarti langganan
    // yang hidup sepanjang aplikasi terbuka, di layar mana pun. Yang
    // dijanjikan penanda ini cuma "ada balasan" — dan satu menit
    // terlambat mengetahuinya tidak merugikan siapa pun.
    _pewaktu = Timer.periodic(const Duration(minutes: 1), (_) => _muat());
  }

  @override
  void dispose() {
    _pewaktu?.cancel();
    super.dispose();
  }

  Future<void> _muat() async {
    if (!context.read<AuthProvider>().isLoggedIn) return;
    try {
      final t = await _repo.milikSaya();
      if (!mounted) return;
      setState(() => _tiket = t);
    } catch (_) {
      // Penanda yang gagal dimuat cuma berarti tidak ada penandanya.
      // Tombolnya tetap bisa ditekan, dan itu yang penting.
    }
  }

  int get _belumDibaca =>
      SupportRepository.belumDibaca(_tiket, sebagaiAdmin: false);

  Future<void> _buka() async {
    final auth = context.read<AuthProvider>();
    final adaRiwayat = _tiket.isNotEmpty;

    final pilihan = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('KaataGo Support',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Ada kendala? Ceritakan ke kami, nanti dibalas di sini juga.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: KaataTheme.mutedOf(sheetContext)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, color: KaataTheme.brand),
              title: const Text('Buat Pengaduan Baru'),
              subtitle: const Text('Tulis keluhannya, boleh pakai foto',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () => Navigator.pop(sheetContext, 'baru'),
            ),
            ListTile(
              leading: Icon(Icons.receipt_long_outlined,
                  color: adaRiwayat
                      ? KaataTheme.brand
                      : KaataTheme.mutedOf(sheetContext)),
              title: const Text('Lihat Status Pengaduan'),
              subtitle: Text(
                adaRiwayat
                    ? '${_tiket.length} pengaduan'
                        '${_belumDibaca > 0 ? ' • $_belumDibaca belum dibaca' : ''}'
                    : 'Belum ada pengaduan',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: adaRiwayat
                  ? () => Navigator.pop(sheetContext, 'daftar')
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (pilihan == null || !mounted) return;

    if (pilihan == 'baru') {
      final dibuat = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => SupportNewTicketScreen(
            dariMerchant: auth.isEmployee,
            restoId: auth.restoId,
          ),
        ),
      );
      await _muat();
      if (dibuat != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportChatScreen(ticketId: dibuat),
        ));
        await _muat();
      }
      return;
    }

    // Percakapan yang ditutup tidak hilang. Yang membukanya lagi
    // langsung menemukan pesan terakhirnya — bukan daftar kosong yang
    // membuatnya mengira pengaduannya tidak pernah ada.
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SupportTicketListScreen(),
    ));
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().isLoggedIn) {
      return const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton.extended(
          heroTag: 'kaatago-support',
          onPressed: _buka,
          icon: const Icon(Icons.support_agent),
          label: const Text('KaataGo Support'),
        ),
        if (_belumDibaca > 0)
          Positioned(
            right: -2,
            top: -4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: KaataTheme.backgroundOf(context), width: 2),
              ),
              child: Text(
                '$_belumDibaca',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

/// Daftar pengaduan milik orang yang sedang masuk.
class SupportTicketListScreen extends StatefulWidget {
  const SupportTicketListScreen({super.key});

  @override
  State<SupportTicketListScreen> createState() =>
      _SupportTicketListScreenState();
}

class _SupportTicketListScreenState extends State<SupportTicketListScreen> {
  final _repo = SupportRepository();
  List<SupportTicket> _tiket = const [];
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final t = await _repo.milikSaya();
      if (!mounted) return;
      setState(() {
        _tiket = t;
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tgl = DateFormat('d MMM yyyy, HH:mm', 'id_ID');
    final muted = KaataTheme.mutedOf(context);

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Pengaduan Saya')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: _tiket.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Center(
                            child: Text('Belum ada pengaduan.',
                                style: TextStyle(color: muted)),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                      itemCount: _tiket.length,
                      itemBuilder: (context, i) {
                        final t = _tiket[i];
                        final baru = t.belumDibaca(sebagaiAdmin: false);
                        return _KartuTiket(
                          tiket: t,
                          belumDibaca: baru,
                          waktu: t.lastMessageAt == null
                              ? tgl.format(t.createdAt.toWib())
                              : tgl.format(t.lastMessageAt!.toWib()),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    SupportChatScreen(ticketId: t.id),
                              ),
                            );
                            await _muat();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

class _KartuTiket extends StatelessWidget {
  final SupportTicket tiket;
  final bool belumDibaca;
  final String waktu;
  final VoidCallback onTap;

  const _KartuTiket({
    required this.tiket,
    required this.belumDibaca,
    required this.waktu,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final warna = kSupportStatusWarna[tiket.status]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tiket.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13.5)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: warna.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        kSupportStatusLabel[tiket.status]!,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: warna),
                      ),
                    ),
                  ],
                ),
                if ((tiket.lastMessageBody ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tiket.lastMessageBody!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: belumDibaca
                                ? KaataTheme.textOf(context)
                                : muted,
                            fontWeight: belumDibaca
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (belumDibaca)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(waktu, style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
