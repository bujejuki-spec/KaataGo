import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/kaata_logo.dart';
import 'finance_balance_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_income_screen.dart';

/// Home screen for the 'finance' role: view resto-wide income (grouped
/// per day, broken down by payment method), view balance + record
/// expenses, and configure the GL account mapping used to book each
/// payment method's income.
class FinanceHomeScreen extends StatelessWidget {
  const FinanceHomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KaataGo (Finance)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Keluar',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: KaataLogo(size: 72)),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.trending_up, size: 32),
              title: const Text('Pemasukan'),
              subtitle: const Text('Rekap harian, breakdown Tunai/QRIS/Transfer'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FinanceIncomeScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined, size: 32),
              title: const Text('Saldo & Pengeluaran'),
              subtitle: const Text('Lihat saldo total, catat pengeluaran'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FinanceBalanceScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.numbers, size: 32),
              title: const Text('Mapping GL Account'),
              subtitle: const Text('Nomor akun untuk tiap metode pembayaran'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FinanceGlMappingScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
