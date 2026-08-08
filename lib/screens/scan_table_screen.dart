import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/table_session_provider.dart';

/// Required before a customer can order: scan the QR code printed/shown
/// at their table. The dummy QR codes encode "RESTO:<restoId>|TABLE:<n>"
/// — see [TableQrGeneratorScreen] for generating them.
class ScanTableScreen extends StatefulWidget {
  const ScanTableScreen({super.key});

  @override
  State<ScanTableScreen> createState() => _ScanTableScreenState();
}

class _ScanTableScreenState extends State<ScanTableScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    final match = RegExp(r'^RESTO:([^|]+)\|TABLE:(\d+)$').firstMatch(raw.trim());
    if (match == null) {
      setState(() => _error = 'QR tidak dikenali: "$raw"');
      return;
    }

    _handled = true;
    final restoId = match.group(1)!;
    final table = int.parse(match.group(2)!);
    await context.read<TableSessionProvider>().setTable(restoId, table);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _enterManually() async {
    final restoCtrl = TextEditingController();
    final tableCtrl = TextEditingController();
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Input Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: restoCtrl,
              decoration: const InputDecoration(labelText: 'Resto ID'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tableCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nomor Meja'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final resto = restoCtrl.text.trim();
              final n = int.tryParse(tableCtrl.text.trim());
              if (resto.isEmpty || n == null) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context, (resto, n));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await context.read<TableSessionProvider>().setTable(result.$1, result.$2);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Meja'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Input manual',
            onPressed: _enterManually,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Arahkan kamera ke QR code di meja kamu.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
