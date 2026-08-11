import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../db/restaurant_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';

/// Builds the QR sticker a customer scans at their table. The Resto ID is
/// taken from the logged-in employee's own account and shown read-only —
/// an Admin can only ever generate codes for their own restaurant — so
/// the only thing to fill in is the table number.
///
/// The encoded payload is `RESTO:<restoId>|TABLE:<n>`, which is exactly
/// what [ScanTableScreen]'s parser expects; changing the format here
/// would silently break scanning.
class TableQrGeneratorScreen extends StatefulWidget {
  const TableQrGeneratorScreen({super.key});

  @override
  State<TableQrGeneratorScreen> createState() => _TableQrGeneratorScreenState();
}

class _TableQrGeneratorScreenState extends State<TableQrGeneratorScreen> {
  final _tableCtrl = TextEditingController();
  final _restoRepo = RestaurantRepository();
  String _restoName = '';

  @override
  void initState() {
    super.initState();
    _loadRestoName();
  }

  Future<void> _loadRestoName() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await _restoRepo.getOnce(restoId);
      if (!mounted) return;
      setState(() => _restoName = resto?.name ?? restoId);
    } catch (_) {
      // Offline — the ID alone is enough to render a working QR.
      if (mounted) setState(() => _restoName = restoId);
    }
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    super.dispose();
  }

  /// Null until a table label has actually been typed — drives both the
  /// preview and whether printing is offered. Free-form on purpose:
  /// "A01" and "VIP-2" are as common as "7".
  String? get _tableNumber {
    final raw = _tableCtrl.text.trim();
    return raw.isEmpty ? null : raw;
  }

  String _payloadFor(String table, String restoId) => 'RESTO:$restoId|TABLE:$table';

  Future<void> _printQr(String restoId, String table) async {
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (context) => pw.Center(
          child: pw.Container(
            width: 380,
            padding: const pw.EdgeInsets.all(28),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
              borderRadius: pw.BorderRadius.circular(16),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(_restoName.isEmpty ? restoId : _restoName,
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 4),
                pw.Text('Scan untuk pesan dari meja ini',
                    style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                pw.SizedBox(height: 18),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _payloadFor(table, restoId),
                  width: 240,
                  height: 240,
                ),
                pw.SizedBox(height: 18),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(20),
                  ),
                  child: pw.Text('MEJA $table',
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 14),
                pw.Text('KaataGo', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final restoId = context.watch<AuthProvider>().restoId;

    if (restoId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generator QR Meja')),
        body: const Center(child: Text('Akun ini belum punya Resto ID.')),
      );
    }

    final table = _tableNumber;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundTint,
      appBar: AppBar(title: const Text('Generator QR Meja')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: table == null ? null : () => _printQr(restoId, table),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Cetak / Bagikan QR'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        children: [
          _Card(
            icon: Icons.storefront_outlined,
            color: KaataTheme.brand,
            title: 'Data Resto',
            subtitle: 'Otomatis dari akun yang sedang login',
            children: [
              TextFormField(
                initialValue: restoId,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Resto ID',
                  filled: true,
                  fillColor: Color(0xFFEEEEEE),
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_restoName.isNotEmpty) ...[
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey(_restoName),
                  initialValue: _restoName,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Nama Resto',
                    filled: true,
                    fillColor: Color(0xFFEEEEEE),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _Card(
            icon: Icons.table_restaurant_outlined,
            color: const Color(0xFFF59E0B),
            title: 'Nomor Meja',
            subtitle: 'QR akan langsung berubah saat diketik',
            children: [
              TextFormField(
                controller: _tableCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nomor Meja',
                  hintText: 'Contoh: 7, A01, VIP-2',
                  prefixIcon: Icon(Icons.tag),
                ),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (table == null)
            _EmptyPreview()
          else
            _QrPreview(
              restoName: _restoName.isEmpty ? restoId : _restoName,
              table: table,
              payload: _payloadFor(table, restoId),
            ),
        ],
      ),
    );
  }
}

class _QrPreview extends StatelessWidget {
  final String restoName;
  final String table;
  final String payload;

  const _QrPreview({required this.restoName, required this.table, required this.payload});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(restoName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text('Scan untuk pesan dari meja ini',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 200,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            decoration: BoxDecoration(
              color: KaataTheme.brand,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text('MEJA $table',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          const SizedBox(height: 14),
          SelectableText(
            payload,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_2, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Isi nomor meja untuk membuat QR',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _Card({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 1),
                      Text(subtitle,
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}
