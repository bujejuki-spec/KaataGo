import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/discount_repository.dart';
import '../models/discount.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../theme.dart';
import '../utils/promo_period.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/promo_period_fields.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

/// Menu Diskon — kasir, admin, dan owner.
///
/// Dua bentuk yang benar-benar berbeda, sengaja dalam satu daftar:
/// diskon yang menempel pada menu tertentu (satu menu, atau beberapa
/// sekaligus untuk bundling), dan diskon yang menempel pada nilai
/// tagihan.
class DiscountScreen extends StatefulWidget {
  const DiscountScreen({super.key});

  @override
  State<DiscountScreen> createState() => _DiscountScreenState();
}

class _DiscountScreenState extends State<DiscountScreen> {
  final _repo = DiscountRepository();
  final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<Discount> _discounts = [];
  bool _loading = true;
  String? _error;

  String? get _restoId => context.read<AuthProvider>().restoId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final restoId = _restoId;
    if (restoId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.getForResto(restoId);
      if (!mounted) return;
      setState(() {
        _discounts = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _edit({Discount? existing}) async {
    final restoId = _restoId;
    if (restoId == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _DiscountFormScreen(existing: existing, restoId: restoId),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Discount d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_outline, size: 38, color: Colors.red),
        title: Text('Hapus "${d.name}"?'),
        content: const Text(
          'Transaksi yang sudah memakai diskon ini tidak berubah — '
          'potongannya sudah tercatat di strukmya masing-masing.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.delete(d.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diskon')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Gagal memuat: $_error',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: _load, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : _discounts.isEmpty
                  ? const _EmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ResponsiveCenter(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              16, 14, 16, kFabSafeBottom),
                          itemCount: _discounts.length,
                          itemBuilder: (context, i) => _DiscountCard(
                            discount: _discounts[i],
                            currency: _currency,
                            onEdit: () => _edit(existing: _discounts[i]),
                            onDelete: () => _delete(_discounts[i]),
                            onToggle: (v) async {
                              await _repo.setActive(_discounts[i].id, v);
                              _load();
                            },
                          ),
                        ),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Diskon Baru'),
      ),
    );
  }
}

class _DiscountCard extends StatelessWidget {
  final Discount discount;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _DiscountCard({
    required this.discount,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'id_ID');
    final periode = [
      if (discount.startsOn != null) 'mulai ${fmt.format(discount.startsOn!)}',
      if (discount.endsOn != null) 'sampai ${fmt.format(discount.endsOn!)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(discount.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  PeriodBadge(
                      period: discount.period, active: discount.active),
                  Switch(
                    value: discount.active,
                    onChanged: onToggle,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: KaataTheme.brandOf(context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      discount.kind == DiscountKind.percent
                          ? '${discount.value}%'
                          : currency.format(discount.value),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: KaataTheme.brandOf(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      discount.basis == DiscountBasis.minPurchase
                          ? 'Belanja ${discount.compare == MinCompare.atLeast ? '≥' : '>'} '
                              '${currency.format(discount.minPurchase)}'
                          : discount.minQty > 1
                              ? '${discount.productIds.length} menu · min ${discount.minQty} pcs'
                              : '${discount.productIds.length} menu',
                      style: TextStyle(
                          fontSize: 12.5, color: KaataTheme.mutedOf(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 19, color: Colors.red),
                    tooltip: 'Hapus',
                    onPressed: onDelete,
                  ),
                ],
              ),
              if (periode.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(periode,
                    style: TextStyle(
                        fontSize: 11.5, color: KaataTheme.mutedOf(context))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined,
                size: 60, color: KaataTheme.mutedOf(context).withOpacity(0.4)),
            const SizedBox(height: 14),
            Text('Belum ada diskon',
                style: TextStyle(
                    fontSize: 15, color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 6),
            Text(
              'Bisa untuk menu tertentu — satu atau beberapa sekaligus untuk '
              'bundling — atau untuk seluruh tagihan yang mencapai nilai '
              'minimum.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: KaataTheme.mutedOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulir satu aturan diskon.
class _DiscountFormScreen extends StatefulWidget {
  final Discount? existing;
  final String restoId;

  const _DiscountFormScreen({this.existing, required this.restoId});

  @override
  State<_DiscountFormScreen> createState() => _DiscountFormScreenState();
}

class _DiscountFormScreenState extends State<_DiscountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = DiscountRepository();

  @override
  void initState() {
    super.initState();
    // Daftar produknya dimuat sendiri kalau belum ada isinya.
    //
    // Sebelumnya layar ini menumpang daftar yang diisi layar lain —
    // Input Pesanan atau Kelola Produk. Dari hub Admin itu kebetulan
    // selalu benar, karena Kelola Produk hampir selalu dibuka lebih
    // dulu. Dari hub Kasir tidak: yang membuka Diskon langsung
    // disambut "Belum ada produk di resto ini", lalu menyimpulkan
    // restonya memang belum punya menu.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final products = context.read<ProductProvider>();
      if (products.products.isNotEmpty) return;
      setState(() => _memuatProduk = true);
      try {
        await products.syncWithResto(widget.restoId);
      } finally {
        if (mounted) setState(() => _memuatProduk = false);
      }
    });
  }

  /// Sedang menarik daftar produknya.
  ///
  /// Dibedakan dari "kosong" dengan sengaja: keduanya terlihat sama di
  /// layar, tapi yang satu berarti tunggu sebentar dan yang satu lagi
  /// berarti buat produknya dulu. Menyamakannya membuat orang menyerah
  /// pada layar yang sebenarnya sedang bekerja.
  bool _memuatProduk = false;

  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _valueCtrl = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.kind == DiscountKind.percent
            ? '${widget.existing!.value}'
            : formatRupiahInput(widget.existing!.value),
  );
  late final _minCtrl = TextEditingController(
    text: widget.existing == null || widget.existing!.minPurchase == 0
        ? ''
        : formatRupiahInput(widget.existing!.minPurchase),
  );

  late final _qtyCtrl =
      TextEditingController(text: '${widget.existing?.minQty ?? 1}');

  late DiscountBasis _basis = widget.existing?.basis ?? DiscountBasis.products;
  late DiscountKind _kind = widget.existing?.kind ?? DiscountKind.percent;
  late MinCompare _compare = widget.existing?.compare ?? MinCompare.atLeast;
  late Set<String> _productIds = {...?widget.existing?.productIds};
  late DateTime? _startsOn = widget.existing?.startsOn;
  late DateTime? _endsOn = widget.existing?.endsOn;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    _minCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_basis == DiscountBasis.products && _productIds.isEmpty) {
      showAppToast(context, 'Pilih minimal satu menu.', isError: true);
      return;
    }

    final periodError = validatePeriod(startsOn: _startsOn, endsOn: _endsOn);
    if (periodError != null) {
      showAppToast(context, periodError, isError: true);
      return;
    }

    final value = _kind == DiscountKind.percent
        ? int.tryParse(_valueCtrl.text.trim()) ?? 0
        : parseRupiah(_valueCtrl.text) ?? 0;

    setState(() => _saving = true);
    try {
      await _repo.save(Discount(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        restoId: widget.restoId,
        name: _nameCtrl.text.trim(),
        basis: _basis,
        kind: _kind,
        value: value,
        productIds: _productIds.toList(),
        minPurchase: _basis == DiscountBasis.minPurchase
            ? (parseRupiah(_minCtrl.text) ?? 0)
            : 0,
        compare: _compare,
        minQty: _basis == DiscountBasis.products
            ? (int.tryParse(_qtyCtrl.text.trim()) ?? 1).clamp(1, 999)
            : 1,
        startsOn: _startsOn,
        endsOn: _endsOn,
        active: widget.existing?.active ?? true,
        createdBy: context.read<AuthProvider>().user?.email,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductProvider>().products;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Diskon Baru' : 'Ubah Diskon'),
      ),
      body: Form(
        key: _formKey,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  label: requiredLabel('Nama Diskon'),
                  hintText: 'Contoh: Paket Hemat Siang, Diskon Gajian',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 18),

              const Text('Berlaku Untuk',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<DiscountBasis>(
                segments: [
                  for (final b in DiscountBasis.values)
                    ButtonSegment(value: b, label: Text(kDiscountBasisLabels[b]!)),
                ],
                selected: {_basis},
                onSelectionChanged: (v) => setState(() => _basis = v.first),
              ),
              const SizedBox(height: 18),

              if (_basis == DiscountBasis.products) ...[
                _ProductPicker(
                  products: products,
                  memuat: _memuatProduk,
                  selected: _productIds,
                  onChanged: (ids) => setState(() => _productIds = ids),
                ),
                const SizedBox(height: 14),
                _MinQtyField(
                  controller: _qtyCtrl,
                  onChanged: () => setState(() {}),
                ),
              ] else
                _MinPurchaseFields(
                  controller: _minCtrl,
                  compare: _compare,
                  onCompareChanged: (v) => setState(() => _compare = v),
                ),
              const SizedBox(height: 18),

              const Text('Potongan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<DiscountKind>(
                      segments: const [
                        ButtonSegment(
                            value: DiscountKind.percent, label: Text('Persen')),
                        ButtonSegment(
                            value: DiscountKind.amount, label: Text('Rupiah')),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (v) => setState(() {
                        _kind = v.first;
                        _valueCtrl.clear();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _valueCtrl,
                keyboardType: TextInputType.number,
                inputFormatters:
                    _kind == DiscountKind.amount ? [ThousandsInputFormatter()] : null,
                decoration: InputDecoration(
                  label: requiredLabel(
                      _kind == DiscountKind.percent ? 'Persen (1–100)' : 'Nominal'),
                  prefixText: _kind == DiscountKind.amount ? 'Rp ' : null,
                  suffixText: _kind == DiscountKind.percent ? '%' : null,
                ),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isEmpty) return 'Wajib diisi';
                  if (_kind == DiscountKind.percent) {
                    final n = int.tryParse(raw);
                    if (n == null) return 'Harus angka';
                    if (n < 1 || n > 100) return 'Antara 1 sampai 100';
                  } else {
                    final n = parseRupiah(raw) ?? 0;
                    if (n <= 0) return 'Harus lebih dari 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 22),

              PromoPeriodFields(
                startsOn: _startsOn,
                endsOn: _endsOn,
                onChanged: (s, e) => setState(() {
                  _startsOn = s;
                  _endsOn = e;
                }),
              ),
              const SizedBox(height: 26),

              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pemilih menu — bisa lebih dari satu, dan itulah cara bundling
/// dinyatakan.
class _ProductPicker extends StatelessWidget {
  final List<Product> products;
  final bool memuat;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _ProductPicker({
    required this.products,
    required this.memuat,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Menu yang Didiskon',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const Spacer(),
            Text('${selected.length} dipilih',
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context))),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Pilih beberapa sekaligus untuk bundling — potongannya dihitung '
          'dari jumlah menu yang ikut, bukan per menu.',
          style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
        ),
        const SizedBox(height: 10),
        if (products.isEmpty && memuat)
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: KaataTheme.mutedOf(context)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Memuat daftar menu…',
                    style: TextStyle(color: KaataTheme.mutedOf(context))),
              ),
            ],
          )
        else if (products.isEmpty)
          Text('Belum ada produk di resto ini.',
              style: TextStyle(color: KaataTheme.mutedOf(context)))
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              border: Border.all(color: KaataTheme.borderOf(context)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in products)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(p.id),
                    title: Text(p.name, style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(p.category,
                        style: const TextStyle(fontSize: 11)),
                    onChanged: (v) {
                      final next = {...selected};
                      if (v == true) {
                        next.add(p.id);
                      } else {
                        next.remove(p.id);
                      }
                      onChanged(next);
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Berapa banyak menunya harus dibeli supaya promonya berlaku.
///
/// Isinya angka, tapi yang dibaca orang yang mengisi formulir ini adalah
/// kalimat promonya. Karena itu kalimat itu ditulis balik ke layar
/// begitu angkanya berubah — "berlaku kalau menu yang dipilih dipesan
/// minimal 2" salah dibaca jauh lebih sulit daripada kotak isian
/// bertuliskan "Qty".
class _MinQtyField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _MinQtyField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final qty = int.tryParse(controller.text.trim()) ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Minimum Jumlah',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Jumlah',
                  suffixText: 'pcs',
                ),
                onChanged: (_) => onChanged(),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim()) ?? 0;
                  return n < 1 ? 'Minimal 1' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                qty <= 1
                    ? 'Berlaku berapa pun jumlah yang dibeli.'
                    : 'Berlaku kalau menu yang dipilih dipesan minimal '
                        '$qty pcs. Kalau ada beberapa menu, tiap menu '
                        'dihitung sendiri.',
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MinPurchaseFields extends StatelessWidget {
  final TextEditingController controller;
  final MinCompare compare;
  final ValueChanged<MinCompare> onCompareChanged;

  const _MinPurchaseFields({
    required this.controller,
    required this.compare,
    required this.onCompareChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Minimum Belanja',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsInputFormatter()],
          decoration: InputDecoration(
            label: requiredLabel('Nilai Minimum'),
            prefixText: 'Rp ',
          ),
          validator: (v) {
            final n = parseRupiah(v ?? '') ?? 0;
            return n <= 0 ? 'Harus lebih dari 0' : null;
          },
        ),
        const SizedBox(height: 10),
        // Pembandingnya opsional dalam arti bawaan sudah dipilihkan (≥),
        // tapi tetap ditampilkan: transaksi yang nilainya pas di batas
        // adalah yang paling sering jadi perselisihan di meja kasir, dan
        // menebaknya diam-diam berarti kasir yang menanggung jawabannya.
        Text('Cara membandingkan',
            style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context))),
        const SizedBox(height: 6),
        SegmentedButton<MinCompare>(
          segments: [
            for (final c in MinCompare.values)
              ButtonSegment(value: c, label: Text(kMinCompareLabels[c]!)),
          ],
          selected: {compare},
          onSelectionChanged: (v) => onCompareChanged(v.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11.5)),
          ),
        ),
      ],
    );
  }
}
