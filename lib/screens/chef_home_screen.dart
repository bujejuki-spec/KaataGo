import 'package:flutter/material.dart';

import '../widgets/language_theme_toggle.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../widgets/inbox_icon_button.dart';
import '../widgets/notification_test_tile.dart';
import '../widgets/kitchen_checklist_dialog.dart';
import '../utils/logout_confirm.dart';
import '../widgets/grouped_order_list.dart';
import '../widgets/app_toast.dart';

/// Chef's entire app: a live, tabbed feed of incoming orders — from both
/// Employee Kasir sales and customer self-orders — with full item detail.
/// Chef can advance an order from "Baru" → "Diproses" → "Selesai"; the
/// status updates live for the customer to see too. No product
/// management, no cashier access, no settings.
class ChefHomeScreen extends StatefulWidget {
  const ChefHomeScreen({super.key});

  @override
  State<ChefHomeScreen> createState() => _ChefHomeScreenState();
}

class _ChefHomeScreenState extends State<ChefHomeScreen> {
  final _repo = OrderRepository();

  /// Status null berarti tab "Menunggu Pembayaran": isinya dipilih dari
  /// status bayarnya, bukan status dapurnya.
  static const _tabs = <(KitchenStatus?, String)>[
    (null, 'Menunggu Bayar'),
    (KitchenStatus.waiting, 'Baru'),
    (KitchenStatus.onProgress, 'Diproses'),
    (KitchenStatus.done, 'Selesai'),
  ];

  /// Pesanan yang uangnya belum diterima ditarik keluar dari tiga tab
  /// kerja dan dikumpulkan di tab pertama.
  ///
  /// Dapur tetap boleh memasaknya — tombolnya ada di sana, dan banyak
  /// resto memang memilih begitu supaya pelanggan tidak menunggu dua
  /// kali. Yang dihindari cuma satu: pesanan belum dibayar duduk
  /// bercampur di antrean "Baru" tanpa penanda apa pun, lalu keluar
  /// dari dapur, lalu tidak ada yang ingat menagihnya.
  bool _awaitingPayment(CustomerOrder o) => o.isPendingCashPayment;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final restoId = auth.restoId!;
    final employeeName = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Chef';

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 60,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(employeeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                '${auth.roleLabel ?? 'Chef'} • ${auth.user?.email ?? ''}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          // Bisa digeser: empat tab dengan satu label dua kata tidak
          // muat dibagi rata di layar HP, dan yang terpotong justru tab
          // baru yang belum dikenali siapa pun.
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
          ),
          actions: [
            const AppearanceIconButton(),
            // Owner membukanya dari hub-nya sendiri, yang sudah punya
            // Kotak Masuk — sama alasannya dengan tombol Keluar di bawah.
            if (!auth.isOwner) const InboxIconButton(),
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined),
              tooltip: 'Tes Notifikasi',
              onPressed: () => showNotificationTest(context),
            ),
            // Owner membuka layar ini dari hub-nya, dan hub itu sudah
            // punya menu Keluar sendiri. Tombol logout di sini akan
            // mengeluarkannya dari aplikasi hanya karena dia mengintip
            // dapur — sesuatu yang tidak pernah dia maksud.
            if (!auth.isOwner)
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Keluar',
                onPressed: () async {
                  if (!await confirmLogout(context)) return;
                  if (!context.mounted) return;
                  await context.read<AuthProvider>().signOut();
                },
              ),
          ],
        ),
        body: StreamBuilder<List<CustomerOrder>>(
          stream: _repo.watchAll(restoId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Gagal memuat pesanan.\n${snapshot.error}',
                    textAlign: TextAlign.center),
              );
            }
            // Pesanan yang hangus karena tidak dibayar tidak muncul di
            // mana pun di dapur. Membiarkannya jatuh kembali ke "Baru"
            // hanya karena status bayarnya bukan lagi 'pending' adalah
            // cara paling pasti memasak pesanan yang sudah dibatalkan.
            final allOrders =
                (snapshot.data ?? []).where((o) => !o.isExpired).toList();

            return TabBarView(
              children: _tabs.map((tab) {
                final orders = tab.$1 == null
                    ? allOrders.where(_awaitingPayment).toList()
                    : allOrders
                        .where((o) =>
                            o.kitchenStatus == tab.$1 && !_awaitingPayment(o))
                        .toList();
                if (orders.isEmpty) {
                  return Center(
                    child: Text(tab.$1 == null
                        ? 'Tidak ada pesanan yang menunggu pembayaran.'
                        : 'Tidak ada pesanan "${tab.$2}".'),
                  );
                }
                // Tab Selesai menumpuk tanpa batas — pesanan kemarin,
                // minggu lalu, bulan lalu — dan yang dicari hampir selalu
                // satu hari tertentu. Dua tab lainnya adalah antrean
                // kerja yang harus terbaca sekaligus.
                final done = tab.$1 == KitchenStatus.done;
                return GroupedOrderList(
                  orders: orders,
                  actionsFor: _buildActions,
                  collapsibleDays: done,
                  expandItems: !done,
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  /// Menutup pesanan lewat daftar centang, bukan satu tombol.
  ///
  /// Centang separuh tetap disimpan dan pesanannya bertahan di "Sedang
  /// Dimasak" — dapur yang mengerjakan lima menu sekaligus jarang
  /// menyelesaikan semuanya dalam satu waktu, dan memaksanya sekali klik
  /// hanya akan membuat daftar centangnya diabaikan.
  Future<void> _openChecklist(CustomerOrder order) async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (_) => KitchenChecklistDialog(order: order),
    );
    if (result == null) return;

    final allDone = result.length >= order.items.length;
    try {
      await _repo.updateChecklist(
        order.id,
        itemsDone: result,
        status: allDone ? KitchenStatus.done : KitchenStatus.onProgress,
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  Widget? _buildActions(CustomerOrder order) {
    switch (order.kitchenStatus) {
      case KitchenStatus.waiting:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
            label: const Text('Mulai Masak'),
            onPressed: () =>
                _repo.updateKitchenStatus(order.id, KitchenStatus.onProgress),
          ),
        );
      case KitchenStatus.onProgress:
        final done = order.itemsDone.length;
        final total = order.items.length;
        final partial = done > 0 && done < total;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (partial) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions, size: 14, color: Color(0xFF92400E)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Sebagian selesai — $done dari $total menu',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              icon: const Icon(Icons.checklist_rtl, size: 18),
              label: Text(partial ? 'Lanjutkan Cek Menu' : 'Cek Menu & Selesai'),
              onPressed: () => _openChecklist(order),
            ),
          ],
        );
      case KitchenStatus.done:
        return null;
    }
  }
}
