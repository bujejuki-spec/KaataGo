import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Entry point for staff: signs in with Google, then checks the
/// `employees` Firestore collection to confirm the account is actually
/// registered as staff. Anyone else (or anyone who cancels) just falls
/// back to the customer self-order experience.
///
/// Pushed on top of [RootScreen] as a route. Once the role check confirms
/// the account is an employee, RootScreen (underneath) already swaps to
/// the POS app — this screen just needs to pop itself out of the way so
/// that swap becomes visible.
class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> {
  bool _popped = false;

  void _popIfEmployee(AuthProvider auth) {
    if (_popped || !auth.isEmployee) return;
    _popped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Masuk sebagai Karyawan')),
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          _popIfEmployee(auth);

          if (auth.isCheckingRole || auth.isEmployee) {
            return const Center(child: CircularProgressIndicator());
          }

          if (auth.isLoggedIn && !auth.isEmployee) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.block, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(
                    'Akun ${auth.user?.email} belum terdaftar sebagai karyawan.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Minta admin untuk menambahkan email ini ke daftar karyawan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  if (auth.lastError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      auth.lastError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () async {
                      await auth.signOut();
                    },
                    child: const Text('Coba akun lain'),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storefront, size: 64, color: Colors.indigo),
                const SizedBox(height: 16),
                const Text(
                  'Login khusus karyawan untuk akses kasir dan kelola produk.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (auth.lastError != null) ...[
                  Text(auth.lastError!,
                      style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: () => auth.signInWithGoogle(),
                  icon: const Icon(Icons.login),
                  label: const Text('Masuk dengan Google'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
