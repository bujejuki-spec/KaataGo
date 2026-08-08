import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/customer_login_flow.dart';
import '../widgets/kaata_logo.dart';
import 'customer_home_screen.dart';
import 'employee_login_screen.dart';

/// First screen shown to anyone who isn't already a recognized employee
/// and hasn't scanned a table before. Picks the experience: browse/order
/// as a customer (which first offers an optional Gmail login), or sign
/// in as staff.
class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({super.key});

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen> {
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _versionLabel = 'v${info.version} (${info.buildNumber})');
    });
  }

  Future<void> _chooseCustomer() async {
    final loginFirst = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.mail_outline, size: 40, color: KaataTheme.brand),
        title: const Text('Login dengan Gmail?'),
        content: const Text(
          'Login supaya riwayat pesanan kamu tersimpan dan bisa dilihat lagi '
          'dari resto mana pun. Nggak login juga tetap bisa pesan seperti biasa — '
          'riwayatnya cuma tersimpan di HP ini.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Login dengan Gmail'),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Lewati, Pesan Tanpa Login'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (loginFirst == null || !mounted) return; // dialog dismissed without a choice

    if (loginFirst) {
      final auth = context.read<AuthProvider>();
      await auth.signInWithGoogle();
      if (!mounted) return;

      if (!auth.isLoggedIn || auth.isEmployee) {
        // Either they backed out of Google's account picker (still not
        // logged in), or the email turned out to be a registered
        // employee — in both cases stay right here on the choice screen.
        // RootScreen watches AuthProvider itself, so an employee login
        // switches to the staff screens automatically without us pushing
        // anything.
        return;
      }

      await ensureCustomerProfile(context, auth.user!.email!);
      if (!mounted) return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const KaataLogo(size: 96),
              const SizedBox(height: 20),
              const Text(
                'KaataGo',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: KaataTheme.brandDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Order Cepat, Resto Hebat',
                style: TextStyle(
                  color: KaataTheme.brand,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Kamu masuk sebagai apa?',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Customer'),
                  onPressed: _chooseCustomer,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Resto'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmployeeLoginScreen()),
                  ),
                ),
              ),
              const Spacer(),
              if (_versionLabel.isNotEmpty)
                Text(
                  _versionLabel,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
