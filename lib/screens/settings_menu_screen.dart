import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import 'restaurant_info_screen.dart';
import 'payment_info_screen.dart';
import 'table_qr_generator_screen.dart';
import 'promo_banner_screen.dart';

/// Admin's settings hub — groups the less-frequently-used screens
/// (restaurant info, table QR codes, payment info) instead of cluttering
/// the main app bar with a separate icon for each one. No Logout here:
/// [AdminHomeScreen] already has one in its own app bar, one screen
/// back.
///
/// Styled the same as the Super Admin/Finance hub screens (gradient hero
/// header + colorful icon-badge menu rows) for a consistent look across
/// every "menu" screen in the app.
class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AuthProvider>().user?.email;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundTint,
      // Fixed header like the role hubs. This one is a pushed route, so
      // the back arrow the SliverAppBar used to provide is layered onto
      // the header instead of disappearing with it.
      body: Column(
        children: [
          Stack(
            children: [
              HubHeader(
                logo: const KaataLogo(size: 64),
                title: 'Pengaturan',
                subtitle: email,
                colorA: KaataTheme.brand,
                colorB: KaataTheme.brandDark,
              ),
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Kembali',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Menu',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                const SizedBox(height: 10),
                HubMenuTile(
                  icon: Icons.storefront_outlined,
                  title: 'Info Resto',
                  subtitle: 'Nama & alamat yang dilihat customer',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RestaurantInfoScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.campaign_outlined,
                  title: 'Banner Promo',
                  subtitle: 'Pasang promo di halaman menu customer',
                  color: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PromoBannerScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.qr_code_2_outlined,
                  title: 'QR Meja',
                  subtitle: 'Generate & cetak QR code per nomor meja',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TableQrGeneratorScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.payments_outlined,
                  title: 'Info Pembayaran',
                  subtitle: 'QRIS & rekening bank (hanya lihat)',
                  color: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PaymentInfoScreen()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
