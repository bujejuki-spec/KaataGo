import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/billing_repository.dart';
import '../models/billing.dart';
import '../theme.dart';
import '../utils/photo_picker.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMMM yyyy', 'id_ID');

/// Tagihan langganan KaataGo untuk sebuah resto.
///
/// Dapat dibuka meski restonya sedang terkunci — inilah satu-satunya
/// jalan keluar dari penguncian, dan mengunci jalan keluarnya sendiri
/// akan meninggalkan resto yang sudah membayar tanpa cara memberi tahu
/// siapa pun.
class BillingScreen extends StatefulWidget {
  final String restoId;

  const BillingScreen({super.key, required this.restoId});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _repo = BillingRepository();

  RestoBilling? _setelan;
  List<BillingInvoice> _tagihan = const [];
  bool _memuat = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final setelan = await _repo.settingsOf(widget.restoId);
      final tagihan = await _repo.invoicesOf(widget.restoId);
      if (!mounted) return;
      setState(() {
        _setelan = setelan;
        _tagihan = tagihan;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _bayar(BillingInvoice inv) async {
    final hasil = await showDialog<_Bukti>(
      context: context,
      builder: (_) => _DialogBayar(invoice: inv),
    );
    if (hasil == null || !mounted) return;

    try {
      await _repo.submitPayment(
        inv.id,
        proofBase64: hasil.foto == null
            ? null
            : base64Encode(await hasil.foto!.readAsBytes()),
        note: hasil.catatan,
      );
      if (!mounted) return;
      showAppToast(context,
          'Bukti terkirim. Menunggu diverifikasi KaataGo.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal mengirim: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final terbuka = _tagihan.where((t) => t.open).toList();
    final lunas = _tagihan.where((t) => !t.open).toList();

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Tagihan Langganan')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Gagal memuat: $_galat',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: KaataTheme.mutedOf(context))),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _KartuPaket(setelan: _setelan),
                        const SizedBox(height: 18),
                        if (terbuka.isNotEmpty) ...[
                          const _Judul('Perlu Dibayar'),
                          for (final t in terbuka)
                            _KartuTagihan(
                              invoice: t,
                              onBayar: () => _bayar(t),
                            ),
                          const SizedBox(height: 18),
                        ],
                        const _Judul('Riwayat'),
                        if (lunas.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text('Belum ada tagihan yang selesai.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: KaataTheme.mutedOf(context))),
                          )
                        else
                          for (final t in lunas) _KartuTagihan(invoice: t),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _Judul extends StatelessWidget {
  final String teks;
  const _Judul(this.teks);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(teks,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );
}

class _KartuPaket extends StatelessWidget {
  final RestoBilling? setelan;
  const _KartuPaket({this.setelan});

  @override
  Widget build(BuildContext context) {
    final s = setelan;
    final gratis = s == null || s.gratis || !s.active;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gratis
              ? [const Color(0xFF10B981), const Color(0xFF047857)]
              : [KaataTheme.brand, KaataTheme.brandDark],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(gratis ? 'Langganan' : 'Langganan Bulanan',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            gratis ? 'Gratis' : _rupiah.format(s.monthlyPrice),
            style: const TextStyle(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            gratis
                ? 'Resto ini belum dikenai biaya langganan.'
                : 'Jatuh tempo tiap tanggal ${s.billingDay}. '
                    'Tenggang ${s.graceDays} hari sesudahnya.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _KartuTagihan extends StatelessWidget {
  final BillingInvoice invoice;
  final VoidCallback? onBayar;

  const _KartuTagihan({required this.invoice, this.onBayar});

  @override
  Widget build(BuildContext context) {
    final (warna, ikon) = switch (invoice.status) {
      InvoiceStatus.paid => (Colors.green, Icons.check_circle_outline),
      InvoiceStatus.waived => (Colors.blueGrey, Icons.card_giftcard_outlined),
      InvoiceStatus.review => (Colors.orange, Icons.hourglass_top_outlined),
      InvoiceStatus.unpaid => (Colors.red, Icons.error_outline),
    };
    final sisa = invoice.dueDate.difference(DateTime.now()).inDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 17, color: warna),
              const SizedBox(width: 7),
              Text(kInvoiceStatusLabels[invoice.status]!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: warna)),
              const Spacer(),
              Text(invoice.id,
                  style: TextStyle(
                      fontSize: 11, color: KaataTheme.mutedOf(context))),
            ],
          ),
          const SizedBox(height: 8),
          Text(_rupiah.format(invoice.amount),
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(
            'Periode ${_tanggal.format(invoice.periodStart)} – '
            '${_tanggal.format(invoice.periodEnd)}',
            style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
          ),
          Text(
            'Jatuh tempo ${_tanggal.format(invoice.dueDate)}'
            '${invoice.open && sisa < 0 ? ' — lewat ${-sisa} hari' : ''}',
            style: TextStyle(
              fontSize: 11.5,
              color: invoice.open && sisa < 0
                  ? Colors.red
                  : KaataTheme.mutedOf(context),
              fontWeight: invoice.open && sisa < 0
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          if (invoice.rejectReason != null &&
              invoice.rejectReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text('Bukti ditolak: ${invoice.rejectReason}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.red)),
            ),
          ],
          if (invoice.status == InvoiceStatus.review) ...[
            const SizedBox(height: 8),
            Text(
              'Bukti sudah diterima dan sedang diperiksa. Resto tetap bisa '
              'dipakai selama pemeriksaan.',
              style:
                  TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
            ),
          ],
          if (onBayar != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBayar,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(invoice.status == InvoiceStatus.review
                    ? 'Ganti Bukti Bayar'
                    : 'Kirim Bukti Bayar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bukti {
  final File? foto;
  final String? catatan;
  const _Bukti(this.foto, this.catatan);
}

class _DialogBayar extends StatefulWidget {
  final BillingInvoice invoice;
  const _DialogBayar({required this.invoice});

  @override
  State<_DialogBayar> createState() => _DialogBayarState();
}

class _DialogBayarState extends State<_DialogBayar> {
  final _catatan = TextEditingController();
  File? _foto;

  @override
  void dispose() {
    _catatan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Kirim Bukti Bayar', style: TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.invoice.id} · ${_rupiah.format(widget.invoice.amount)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Lampirkan bukti transfer. KaataGo memeriksanya lebih dulu '
              'sebelum tagihan dinyatakan lunas.',
              style:
                  TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context)),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await pickProofPhoto(context);
                if (f != null) setState(() => _foto = f);
              },
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(_foto == null ? 'Pilih Bukti' : 'Ganti Bukti'),
            ),
            if (_foto != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_foto!, height: 150, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _catatan,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'Contoh: transfer dari BCA a.n. …',
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          // Bukti yang tidak dilampirkan membuat pemeriksanya harus
          // menebak — dan yang menanggung tebakan itu adalah resto yang
          // menunggu kuncinya dibuka.
          onPressed: _foto == null
              ? null
              : () => Navigator.pop(
                  context, _Bukti(_foto, _catatan.text.trim())),
          child: const Text('Kirim'),
        ),
      ],
    );
  }
}
