import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/auth_provider.dart';

/// Generates dummy table QR codes (Table 1, 2, 3, ...) for this Admin's
/// restaurant. Each QR encodes "RESTO:<restoId>|TABLE:<n>", so scanning
/// it both identifies which restaurant's menu to load and which table
/// the order is for. In a real deployment these would be printed and
/// stuck on each table; here, an Admin can pull this screen up and point
/// another phone's camera at it to test the scan flow.
class TableQrGeneratorScreen extends StatelessWidget {
  const TableQrGeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const tableCount = 12;
    final restoId = context.watch<AuthProvider>().restoId;

    if (restoId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Meja (Dummy)')),
        body: const Center(
          child: Text('Akun ini belum punya Resto ID.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('QR Meja (Dummy)')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: tableCount,
        itemBuilder: (context, index) {
          final table = index + 1;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: QrImageView(
                      data: 'RESTO:$restoId|TABLE:$table',
                      version: QrVersions.auto,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Meja $table',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
