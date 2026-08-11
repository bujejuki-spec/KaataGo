import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import '../services/notification_service.dart';
import '../services/order_notifier.dart';

/// Menyalakan notifikasi pesanan sesuai siapa yang sedang memakai
/// aplikasi, dan mematikannya begitu perannya berubah.
///
/// Ditaruh membungkus seluruh isi aplikasi, bukan di layar tertentu,
/// karena kabar pesanan harus tetap sampai walaupun orangnya sedang
/// membuka layar lain — kasir yang sedang mengetik pesanan berikutnya
/// tetap perlu tahu pesanan sebelumnya sudah siap.
class OrderNotificationBinder extends StatefulWidget {
  final Widget child;

  const OrderNotificationBinder({super.key, required this.child});

  @override
  State<OrderNotificationBinder> createState() => _OrderNotificationBinderState();
}

class _OrderNotificationBinderState extends State<OrderNotificationBinder> {
  OrderNotifier? _notifier;

  /// Penanda konfigurasi yang sedang berjalan. Dibandingkan setiap
  /// rebuild supaya stream-nya tidak dibangun ulang terus-menerus —
  /// hanya saat yang menonton benar-benar berganti.
  String? _activeKey;

  bool _askedPermission = false;

  @override
  void dispose() {
    _notifier?.stop();
    super.dispose();
  }

  /// Menerjemahkan keadaan login dan sesi meja jadi "siapa yang
  /// mendengarkan apa", atau null kalau memang tidak ada yang perlu
  /// diberitahu (belum login dan belum memilih resto).
  OrderNotifier? _buildNotifier(AuthProvider auth, TableSessionProvider session) {
    if (auth.isChef && auth.restoId != null) {
      return OrderNotifier(role: OrderWatchRole.chef, restoId: auth.restoId!);
    }
    if ((auth.isKasir || auth.isAdmin) && auth.restoId != null) {
      return OrderNotifier(
        role: OrderWatchRole.cashier,
        restoId: auth.restoId!,
        cashierEmail: auth.user?.email,
      );
    }
    // Customer — baik yang login maupun tamu — dikenali dari resto yang
    // sedang dia buka. Tanpa sesi resto tidak ada yang bisa diikuti.
    if (!auth.isEmployee && session.hasActiveResto && session.restoId != null) {
      return OrderNotifier(
        role: OrderWatchRole.customer,
        restoId: session.restoId!,
        customerEmail: auth.isLoggedIn ? auth.user?.email : null,
        sessionId: session.sessionId,
      );
    }
    return null;
  }

  String? _keyFor(OrderNotifier? n) => n == null
      ? null
      : '${n.role}|${n.restoId}|${n.customerEmail}|${n.sessionId}|${n.cashierEmail}';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = context.watch<TableSessionProvider>();

    final next = _buildNotifier(auth, session);
    final nextKey = _keyFor(next);

    if (nextKey != _activeKey) {
      _activeKey = nextKey;
      _notifier?.stop();
      _notifier = next;

      if (next != null) {
        // Izinnya diminta sekali, saat pertama kali benar-benar ada yang
        // perlu diberitahu — bukan saat aplikasi dibuka, di mana orang
        // belum punya alasan untuk mengizinkannya.
        if (!_askedPermission) {
          _askedPermission = true;
          NotificationService.instance.requestPermission();
        }
        next.start();
      }
    }

    return widget.child;
  }
}
