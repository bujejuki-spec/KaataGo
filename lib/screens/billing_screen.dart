import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Id tagihan yang VA-nya sedang diterbitkan.
  String? _menerbitkanVa;

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

  Future<void> _mintaVa(BillingInvoice inv) async {
    final bank = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogPilihBank(),
    );
    if (bank == null || !mounted) return;

    setState(() => _menerbitkanVa = inv.id);
    try {
      await _repo.requestVa(inv.id, bank: bank);
      if (!mounted) return;
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal membuat VA: $e', isError: true);
    } finally {
      if (mounted) setState(() => _menerbitkanVa = null);
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
                        _KartuPaket(
                          setelan: _setelan,
                          potongan: terbuka.isEmpty
                              ? 0
                              : terbuka.first.discountAmount,
                        ),
                        const SizedBox(height: 18),
                        if (terbuka.isNotEmpty) ...[
                          const _Judul('Perlu Dibayar'),
                          for (final t in terbuka)
                            _KartuTagihan(
                              invoice: t,
                              menerbitkanVa: _menerbitkanVa == t.id,
                              onMintaVa: () => _mintaVa(t),
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

  /// Potongan pada tagihan yang sedang berjalan, kalau ada.
  final int potongan;

  const _KartuPaket({this.setelan, this.potongan = 0});

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
                    'Tenggang ${s.graceDays} hari sesudahnya.'
                    '${potongan > 0 ? '\nSudah termasuk potongan '
                        '${_rupiah.format(potongan)} pada tagihan berjalan.' : ''}',
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
  final VoidCallback? onMintaVa;
  final bool menerbitkanVa;

  const _KartuTagihan({
    required this.invoice,
    this.onBayar,
    this.onMintaVa,
    this.menerbitkanVa = false,
  });

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
          // Rincian ditampilkan hanya kalau memang ada potongannya.
          // Nominal akhir tanpa penjelasan terbaca sebagai salah hitung,
          // dan yang menjelaskannya nanti adalah orang yang menerima
          // telepon.
          if (invoice.discountAmount > 0) ...[
            _Rincian(
              label: 'Harga langganan',
              nilai: invoice.grossAmount ?? invoice.amount,
            ),
            _Rincian(
              label: invoice.discountName ?? 'Diskon',
              nilai: -invoice.discountAmount,
              warna: Colors.green,
            ),
            const Divider(height: 14),
          ],
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
          if (invoice.vaHidup) ...[
            const SizedBox(height: 12),
            _KartuVa(invoice: invoice),
          ],
          if (onMintaVa != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: menerbitkanVa ? null : onMintaVa,
                icon: menerbitkanVa
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.account_balance_outlined, size: 18),
                label: Text(invoice.vaHidup
                    ? 'Ganti Bank'
                    : 'Buat Virtual Account'),
              ),
            ),
          ],
          if (onBayar != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              // Jalur cadangan. Transfer manual masih terjadi — resto
              // yang terlanjur mengirim ke rekening lain, atau VA yang
              // ditolak banknya — dan menutup jalur ini berarti uang
              // yang sudah masuk tidak punya cara diakui.
              child: TextButton.icon(
                onPressed: onBayar,
                icon: const Icon(Icons.upload_file_outlined, size: 17),
                label: Text(invoice.status == InvoiceStatus.review
                    ? 'Ganti Bukti Transfer Manual'
                    : 'Sudah transfer manual? Kirim bukti'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nomor Virtual Account, bagian yang paling sering disalin di seluruh
/// layar ini.
///
/// Nomornya dibuat besar dan bertombol salin karena itulah satu-satunya
/// hal yang harus berpindah tanpa salah satu digit pun — dan angka
/// panjang yang harus dibaca bolak-balik dari layar ke aplikasi bank
/// adalah tempat kesalahan ketik paling sering terjadi.
class _KartuVa extends StatelessWidget {
  final BillingInvoice invoice;
  const _KartuVa({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.brandOf(context).withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KaataTheme.brandOf(context).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_outlined,
                  size: 16, color: KaataTheme.brandOf(context)),
              const SizedBox(width: 7),
              Text('Virtual Account ${invoice.vaBank}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: KaataTheme.brandOf(context))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  invoice.vaNumber!,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2),
                ),
              ),
              IconButton(
                tooltip: 'Salin nomor',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invoice.vaNumber!));
                  showAppToast(context, 'Nomor VA disalin.');
                },
              ),
            ],
          ),
          Text(
            'Transfer tepat ${_rupiah.format(invoice.amount)}. Nominal yang '
            'kurang tidak melunasi tagihan.',
            style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
          ),
          if (invoice.vaExpiresAt != null) ...[
            const SizedBox(height: 3),
            Text('Berlaku sampai ${_tanggal.format(invoice.vaExpiresAt!)}',
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context))),
          ],
          const SizedBox(height: 6),
          Text(
            'Begitu transfernya masuk, tagihan lunas sendiri — tidak perlu '
            'mengirim bukti apa pun.',
            style: TextStyle(
                fontSize: 11.5,
                color: KaataTheme.brandOf(context),
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DialogPilihBank extends StatelessWidget {
  const _DialogPilihBank();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Pilih Bank', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nomor Virtual Account dibuat khusus untuk tagihan ini.',
              style:
                  TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context)),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in kBankVA)
                    ListTile(
                      dense: true,
                      title: Text(b),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => Navigator.pop(context, b),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}

/// Satu baris rincian tagihan.
class _Rincian extends StatelessWidget {
  final String label;
  final int nilai;
  final Color? warna;

  const _Rincian({required this.label, required this.nilai, this.warna});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, color: KaataTheme.mutedOf(context)),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              '${nilai < 0 ? '−' : ''}${_rupiah.format(nilai.abs())}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: warna ?? KaataTheme.mutedOf(context)),
            ),
          ],
        ),
      );
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
