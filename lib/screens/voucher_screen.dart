import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../db/voucher_repository.dart';
import '../models/restaurant.dart';
import '../models/voucher.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/promo_period.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/promo_period_fields.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Voucher KaataGo untuk pelanggan — hanya Super Admin.
///
/// Ini promo kami sendiri, bukan promo resto. Yang menanggung
/// potongannya juga kami: dananya keluar dari saldo KaataGo sebagai
/// biaya promosi, dan tercatat di Jurnal GL KaataGo tiap kali dipakai.
class VoucherScreen extends StatefulWidget {
  const VoucherScreen({super.key});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  final _repo = VoucherRepository();
  final _restoRepo = RestaurantRepository();

  List<Voucher> _items = const [];
  List<Restaurant> _resto = const [];
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
      final items = await _repo.all();
      final resto = await _restoRepo.getAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _resto = resto;
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

  Future<void> _ubah([Voucher? existing]) async {
    final hasil = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _FormVoucher(existing: existing, resto: _resto),
    ));
    if (hasil == true) _muat();
  }

  Future<void> _hapus(Voucher v) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus voucher?', style: TextStyle(fontSize: 17)),
        content: Text(
          v.used > 0
              ? 'Voucher ini sudah dipakai ${v.used} kali. Catatan '
                  'pemakaiannya ikut terhapus, dan hitungan yang harus '
                  'dibayarkan ke resto jadi tidak lengkap. Lebih aman '
                  'menonaktifkannya saja.'
              : 'Belum pernah dipakai, jadi tidak ada catatan yang hilang.',
          style: TextStyle(fontSize: 13, color: KaataTheme.mutedOf(context)),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (yakin != true) return;
    try {
      await _repo.delete(v.id);
      if (!mounted) return;
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Voucher Pelanggan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ubah(),
        icon: const Icon(Icons.add),
        label: const Text('Voucher Baru'),
      ),
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
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          'Belum ada voucher.\nPelanggan membayar harga penuh '
                          'di semua resto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: KaataTheme.mutedOf(context)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _muat,
                      child: ResponsiveCenter(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _Kartu(
                            voucher: _items[i],
                            resto: _resto,
                            onTap: () => _ubah(_items[i]),
                            onHapus: () => _hapus(_items[i]),
                          ),
                        ),
                      ),
                    ),
    );
  }
}

class _Kartu extends StatelessWidget {
  final Voucher voucher;
  final List<Restaurant> resto;
  final VoidCallback onTap;
  final VoidCallback onHapus;

  const _Kartu({
    required this.voucher,
    required this.resto,
    required this.onTap,
    required this.onHapus,
  });

  @override
  Widget build(BuildContext context) {
    final berjalan = voucher.isLive() && !voucher.kuotaHabis;
    final nama = {for (final r in resto) r.id: r.name};
    final periode = [
      if (voucher.startsOn != null) 'mulai ${_tanggal.format(voucher.startsOn!)}',
      if (voucher.endsOn != null) 'sampai ${_tanggal.format(voucher.endsOn!)}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KaataTheme.brandOf(context).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(voucher.code,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: KaataTheme.brandOf(context))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(voucher.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (berjalan ? Colors.green : Colors.grey)
                        .withOpacity(0.13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    voucher.kuotaHabis
                        ? 'Kuota habis'
                        : berjalan
                            ? 'Berjalan'
                            : 'Tidak berlaku',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: berjalan ? Colors.green : Colors.grey),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 19, color: Colors.red),
                  tooltip: 'Hapus',
                  onPressed: onHapus,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                voucher.kind == VoucherKind.percent
                    ? 'Potong ${voucher.value}%'
                    : 'Potong ${_rupiah.format(voucher.value)}',
                if (voucher.maxDiscount > 0)
                  'maks ${_rupiah.format(voucher.maxDiscount)}',
                if (voucher.minPurchase > 0)
                  'min belanja ${_rupiah.format(voucher.minPurchase)}',
              ].join(' · '),
              style:
                  TextStyle(fontSize: 12.5, color: KaataTheme.brandOf(context)),
            ),
            const SizedBox(height: 3),
            Text(
              [
                voucher.berlakuDiSemuaResto
                    ? 'Semua resto'
                    : '${voucher.restoIds.length} resto: '
                        '${voucher.restoIds.map((id) => nama[id] ?? id).join(', ')}',
                'dipakai ${voucher.used}'
                    '${voucher.quotaTotal > 0 ? '/${voucher.quotaTotal}' : ''}',
              ].join(' · '),
              style:
                  TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
            ),
            if (periode.isNotEmpty)
              Text(periode,
                  style: TextStyle(
                      fontSize: 11.5, color: KaataTheme.mutedOf(context))),
          ],
        ),
      ),
    );
  }
}

class _FormVoucher extends StatefulWidget {
  final Voucher? existing;
  final List<Restaurant> resto;

  const _FormVoucher({this.existing, required this.resto});

  @override
  State<_FormVoucher> createState() => _FormVoucherState();
}

class _FormVoucherState extends State<_FormVoucher> {
  final _formKey = GlobalKey<FormState>();
  final _repo = VoucherRepository();

  late final _kode = TextEditingController(text: widget.existing?.code ?? '');
  late final _nama = TextEditingController(text: widget.existing?.name ?? '');
  late final _nilai = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.kind == VoucherKind.percent
            ? '${widget.existing!.value}'
            : formatRupiahInput(widget.existing!.value),
  );
  late final _maks = TextEditingController(
    text: (widget.existing?.maxDiscount ?? 0) == 0
        ? ''
        : formatRupiahInput(widget.existing!.maxDiscount),
  );
  late final _minBelanja = TextEditingController(
    text: (widget.existing?.minPurchase ?? 0) == 0
        ? ''
        : formatRupiahInput(widget.existing!.minPurchase),
  );
  late final _kuota = TextEditingController(
    text: (widget.existing?.quotaTotal ?? 0) == 0
        ? ''
        : '${widget.existing!.quotaTotal}',
  );
  late final _kuotaOrang =
      TextEditingController(text: '${widget.existing?.quotaPerCustomer ?? 1}');

  late VoucherKind _jenis = widget.existing?.kind ?? VoucherKind.percent;
  late final Set<String> _sasaran = {...?widget.existing?.restoIds};
  late DateTime? _mulai = widget.existing?.startsOn;
  late DateTime? _akhir = widget.existing?.endsOn;
  late bool _aktif = widget.existing?.active ?? true;
  bool _menyimpan = false;

  @override
  void dispose() {
    for (final c in [
      _kode,
      _nama,
      _nilai,
      _maks,
      _minBelanja,
      _kuota,
      _kuotaOrang
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    final galatPeriode = validatePeriod(startsOn: _mulai, endsOn: _akhir);
    if (galatPeriode != null) {
      showAppToast(context, galatPeriode, isError: true);
      return;
    }

    final nilai = _jenis == VoucherKind.percent
        ? int.tryParse(_nilai.text.trim()) ?? 0
        : parseRupiah(_nilai.text) ?? 0;

    setState(() => _menyimpan = true);
    try {
      await _repo.save(Voucher(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        code: _kode.text.trim().toUpperCase(),
        name: _nama.text.trim(),
        kind: _jenis,
        value: nilai,
        maxDiscount: parseRupiah(_maks.text) ?? 0,
        minPurchase: parseRupiah(_minBelanja.text) ?? 0,
        restoIds: _sasaran.toList(),
        quotaTotal: int.tryParse(_kuota.text.trim()) ?? 0,
        quotaPerCustomer: int.tryParse(_kuotaOrang.text.trim()) ?? 1,
        startsOn: _mulai,
        endsOn: _akhir,
        active: _aktif,
        createdBy: context.read<AuthProvider>().user?.email,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      final pesan = '$e'.contains('vouchers_code_key')
          ? 'Kode ini sudah dipakai voucher lain.'
          : 'Gagal menyimpan: $e';
      showAppToast(context, pesan, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final persen = _jenis == VoucherKind.percent;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(
        title: Text(
            widget.existing == null ? 'Voucher Baru' : 'Ubah Voucher'),
      ),
      body: Form(
        key: _formKey,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              TextFormField(
                controller: _kode,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  // Selalu huruf besar. "hemat10" dan "HEMAT10" harus
                  // voucher yang sama — yang mengetiknya sedang lapar dan
                  // berdiri di depan kasir, bukan sedang teliti.
                  TextInputFormatter.withFunction((lama, baru) =>
                      baru.copyWith(text: baru.text.toUpperCase())),
                ],
                decoration: InputDecoration(
                  label: requiredLabel('Kode Voucher'),
                  hintText: 'HEMAT10',
                  helperText: 'Huruf dan angka saja, tanpa spasi',
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Minimal 3 karakter'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nama,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  label: requiredLabel('Nama Voucher'),
                  hintText: 'Promo Pengguna Baru',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 18),
              const Text('Potongan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<VoucherKind>(
                segments: const [
                  ButtonSegment(
                      value: VoucherKind.percent, label: Text('Persen')),
                  ButtonSegment(
                      value: VoucherKind.amount, label: Text('Rupiah')),
                ],
                selected: {_jenis},
                onSelectionChanged: (v) => setState(() {
                  _jenis = v.first;
                  _nilai.clear();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nilai,
                keyboardType: TextInputType.number,
                inputFormatters: persen
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : [ThousandsInputFormatter()],
                decoration: InputDecoration(
                  label: requiredLabel('Nilai'),
                  prefixText: persen ? null : 'Rp ',
                  suffixText: persen ? '%' : null,
                ),
                validator: (v) {
                  final n = persen
                      ? int.tryParse((v ?? '').trim()) ?? 0
                      : parseRupiah(v ?? '') ?? 0;
                  if (n <= 0) return 'Harus lebih dari 0';
                  if (persen && n > 100) return 'Maksimal 100%';
                  return null;
                },
              ),
              if (persen) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maks,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Potongan maksimal',
                    prefixText: 'Rp ',
                    // Tanpa batas ini, "diskon 20%" pada tagihan sejuta
                    // rupiah adalah dua ratus ribu yang keluar dari saldo
                    // KaataGo untuk satu transaksi.
                    helperText: 'Kosong = tanpa batas. Isi supaya satu '
                        'transaksi besar tidak menghabiskan anggaran promo.',
                    helperMaxLines: 3,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _minBelanja,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Minimal belanja',
                  prefixText: 'Rp ',
                  helperText: 'Kosong = tanpa minimum',
                ),
              ),
              const SizedBox(height: 18),
              const Text('Kuota',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _kuota,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Total pemakaian',
                        helperText: 'Kosong = tanpa batas',
                        helperMaxLines: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _kuotaOrang,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Per pelanggan',
                        helperText: '0 = tanpa batas',
                        helperMaxLines: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('Berlaku di Resto',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Text(
                    _sasaran.isEmpty
                        ? 'Semua resto'
                        : '${_sasaran.length} dipilih',
                    style: TextStyle(
                        fontSize: 11.5, color: KaataTheme.mutedOf(context)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Kosongkan semuanya kalau voucher ini berlaku di seluruh resto.',
                style:
                    TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  border: Border.all(color: KaataTheme.borderOf(context)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in widget.resto)
                      CheckboxListTile(
                        dense: true,
                        value: _sasaran.contains(r.id),
                        title:
                            Text(r.name, style: const TextStyle(fontSize: 13.5)),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _sasaran.add(r.id);
                          } else {
                            _sasaran.remove(r.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PromoPeriodFields(
                startsOn: _mulai,
                endsOn: _akhir,
                onChanged: (mulai, akhir) => setState(() {
                  _mulai = mulai;
                  _akhir = akhir;
                }),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _aktif,
                title: const Text('Aktif', style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  _aktif
                      ? 'Bisa dipakai pelanggan'
                      : 'Disimpan, tapi ditolak saat dicoba',
                  style: TextStyle(
                      fontSize: 11.5, color: KaataTheme.mutedOf(context)),
                ),
                onChanged: (v) => setState(() => _aktif = v),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _menyimpan ? null : _simpan,
                  child: _menyimpan
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simpan'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Potongan voucher ditanggung KaataGo — dananya keluar dari '
                'saldo KaataGo sebagai biaya promosi, dan tercatat di Jurnal '
                'GL KaataGo tiap kali dipakai.',
                style:
                    TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
