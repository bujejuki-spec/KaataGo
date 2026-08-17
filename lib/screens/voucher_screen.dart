import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/restaurant_repository.dart';
import '../db/voucher_repository.dart';
import '../models/restaurant.dart';
import '../models/voucher.dart';
import '../theme.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Voucher KaataGo — hanya Super Admin.
///
/// Menerbitkan voucher bukan sekadar membuat aturan potongan: dananya
/// benar-benar berpindah dari saldo bebas KaataGo ke kantong voucher,
/// dan baru kembali kalau vouchernya hangus. Karena itu layar ini
/// menampilkan nominalnya, bukan cuma nama dan kodenya.
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

  Future<void> _tutupBuka(Voucher v) async {
    try {
      await _repo.setActive(v.id, !v.active);
      if (!mounted) return;
      _muat();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal: $e', isError: true);
    }
  }

  Future<void> _terbitkan() async {
    final hasil = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _FormBatch(resto: _resto),
    ));
    if (hasil == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    final menggantung =
        _items.fold<int>(0, (s, v) => s + v.nilaiTertebus);

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Voucher Pelanggan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _terbitkan,
        icon: const Icon(Icons.add),
        label: const Text('Terbitkan Voucher'),
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
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
                      children: [
                        if (_items.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFF59E0B),
                                Color(0xFFB45309),
                              ]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Menggantung di tangan pelanggan',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(_rupiah.format(menggantung),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Text(
                                  'Sudah ditebus, belum dipakai. Kembali ke '
                                  'saldo kalau sampai hangus.',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(30),
                            child: Text(
                              'Belum ada voucher diterbitkan.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: KaataTheme.mutedOf(context)),
                            ),
                          ),
                        for (final v in _items)
                          _Kartu(
                            voucher: v,
                            resto: _resto,
                            onToggle: () => _tutupBuka(v),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _Kartu extends StatelessWidget {
  final Voucher voucher;
  final List<Restaurant> resto;
  final VoidCallback onToggle;

  const _Kartu({
    required this.voucher,
    required this.resto,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final nama = {for (final r in resto) r.id: r.name};
    final (label, warna) = voucher.kedaluwarsa
        ? ('Kedaluwarsa', Colors.grey)
        : !voucher.active
            ? ('Ditutup', Colors.grey)
            : voucher.habis
                ? ('Habis ditebus', Colors.orange)
                : ('Berjalan', Colors.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: warna.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: warna)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_rupiah.format(voucher.amount)} × ${voucher.quantity} = '
            '${_rupiah.format(voucher.totalAmount)}',
            style:
                TextStyle(fontSize: 13, color: KaataTheme.brandOf(context)),
          ),
          const SizedBox(height: 3),
          Text(
            'Ditebus ${voucher.claimed}/${voucher.quantity} · '
            'berlaku sampai ${_tanggal.format(voucher.expiresOn)}',
            style:
                TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
          ),
          Text(
            [
              voucher.berlakuDiSemuaResto
                  ? 'Semua resto'
                  : voucher.restoIds.map((id) => nama[id] ?? id).join(', '),
              if (voucher.minPurchase > 0)
                'min belanja ${_rupiah.format(voucher.minPurchase)}',
            ].join(' · '),
            style:
                TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
          ),
          if (voucher.settledAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sisa yang tidak ditebus sudah kembali ke saldo.',
                style: TextStyle(
                    fontSize: 11, color: KaataTheme.mutedOf(context)),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: voucher.kedaluwarsa ? null : onToggle,
              child: Text(voucher.active ? 'Tutup' : 'Buka lagi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormBatch extends StatefulWidget {
  final List<Restaurant> resto;

  const _FormBatch({required this.resto});

  @override
  State<_FormBatch> createState() => _FormBatchState();
}

class _FormBatchState extends State<_FormBatch> {
  final _formKey = GlobalKey<FormState>();
  final _repo = VoucherRepository();

  final _kode = TextEditingController();
  final _nama = TextEditingController();
  final _total = TextEditingController();
  final _jumlah = TextEditingController(text: '10');
  final _minBelanja = TextEditingController();
  final Set<String> _sasaran = {};
  DateTime? _kedaluwarsa;
  bool _menyimpan = false;

  @override
  void dispose() {
    for (final c in [_kode, _nama, _total, _jumlah, _minBelanja]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _nilaiPer {
    final total = parseRupiah(_total.text) ?? 0;
    final n = int.tryParse(_jumlah.text.trim()) ?? 0;
    if (total <= 0 || n <= 0) return 0;
    return total ~/ n;
  }

  /// Sisa pembagian yang tidak pernah jadi voucher.
  ///
  /// Ditampilkan, bukan dibulatkan diam-diam: yang mengetik Rp 1.000.000
  /// untuk 3 voucher berhak tahu bahwa Rp 1 tidak ikut keluar.
  int get _sisa {
    final total = parseRupiah(_total.text) ?? 0;
    final n = int.tryParse(_jumlah.text.trim()) ?? 0;
    if (total <= 0 || n <= 0) return 0;
    return total - (_nilaiPer * n);
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kedaluwarsa == null) {
      AppToast.show(context, 'Pilih tanggal kedaluwarsanya.', isError: true);
      return;
    }

    setState(() => _menyimpan = true);
    try {
      await _repo.generate(
        code: _kode.text.trim().toUpperCase(),
        name: _nama.text.trim(),
        totalAmount: parseRupiah(_total.text) ?? 0,
        quantity: int.tryParse(_jumlah.text.trim()) ?? 0,
        expiresOn: _kedaluwarsa!,
        minPurchase: parseRupiah(_minBelanja.text) ?? 0,
        restoIds: _sasaran.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      final pesan = '$e'.contains('vouchers_code_key')
          ? 'Kode ini sudah dipakai voucher lain.'
          : 'Gagal menerbitkan: $e';
      AppToast.show(context, pesan, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Terbitkan Voucher')),
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
                  TextInputFormatter.withFunction((lama, baru) =>
                      baru.copyWith(text: baru.text.toUpperCase())),
                ],
                decoration: InputDecoration(
                  label: requiredLabel('Kode Voucher'),
                  hintText: 'HEMAT100',
                  helperText: 'Satu kode untuk seluruh batch — ini yang '
                      'diumumkan ke pelanggan',
                  helperMaxLines: 2,
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
              const Text('Alokasi Dana',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Dananya keluar dari saldo KaataGo saat diterbitkan, dan '
                'kembali lagi kalau tidak ditebus sampai kedaluwarsa.',
                style:
                    TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _total,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: InputDecoration(
                        label: requiredLabel('Total Dana'),
                        prefixText: 'Rp ',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => (parseRupiah(v ?? '') ?? 0) <= 0
                          ? 'Harus lebih dari 0'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _jumlah,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        label: requiredLabel('Jadi berapa'),
                        suffixText: 'voucher',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          (int.tryParse((v ?? '').trim()) ?? 0) <= 0
                              ? 'Minimal 1'
                              : null,
                    ),
                  ),
                ],
              ),
              if (_nilaiPer > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KaataTheme.brandOf(context).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiap voucher bernilai ${_rupiah.format(_nilaiPer)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: KaataTheme.brandOf(context)),
                      ),
                      if (_sisa > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'Sisa ${_rupiah.format(_sisa)} tidak ikut '
                            'diterbitkan dan tetap di saldo.',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: KaataTheme.mutedOf(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final besok = DateTime.now().add(const Duration(days: 1));
                  final pilih = await showDatePicker(
                    context: context,
                    initialDate: _kedaluwarsa ?? besok,
                    firstDate: besok,
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (pilih != null) setState(() => _kedaluwarsa = pilih);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    label: requiredLabel('Kedaluwarsa'),
                    helperText: 'Minimal besok. Voucher yang belum dipakai '
                        'hangus dan dananya kembali ke saldo.',
                    helperMaxLines: 2,
                  ),
                  child: Text(
                    _kedaluwarsa == null
                        ? 'Pilih tanggal'
                        : _tanggal.format(_kedaluwarsa!),
                    style: TextStyle(
                      color: _kedaluwarsa == null
                          ? KaataTheme.mutedOf(context)
                          : null,
                    ),
                  ),
                ),
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
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
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
                      : Text(_nilaiPer > 0
                          ? 'Terbitkan ${_rupiah.format(_nilaiPer * (int.tryParse(_jumlah.text.trim()) ?? 0))}'
                          : 'Terbitkan'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Setelah terbit, umumkan kodenya ke pelanggan lewat Kirim '
                'Pengumuman supaya mereka bisa menebusnya.',
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
