import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/billing_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/billing.dart';
import '../models/restaurant.dart';
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

/// Diskon harga langganan untuk resto tertentu.
///
/// Dipilih per resto, bukan berlaku untuk semuanya. Yang sering terjadi
/// justru satu-dua resto yang perlu diperlakukan berbeda — masa
/// percobaan, promo pembukaan, kompensasi gangguan — dan diskon yang
/// hanya bisa berlaku untuk semua akan dipakai sebagai pengganti yang
/// mustahil: menurunkan harga daftarnya diam-diam.
class BillingDiscountScreen extends StatefulWidget {
  const BillingDiscountScreen({super.key});

  @override
  State<BillingDiscountScreen> createState() => _BillingDiscountScreenState();
}

class _BillingDiscountScreenState extends State<BillingDiscountScreen> {
  final _repo = BillingRepository();
  final _restoRepo = RestaurantRepository();

  List<BillingDiscount> _items = const [];
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
      final items = await _repo.discounts();
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

  Future<void> _ubah([BillingDiscount? existing]) async {
    final hasil = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _FormDiskon(existing: existing, resto: _resto),
    ));
    if (hasil == true) _muat();
  }

  Future<void> _hapus(BillingDiscount d) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus diskon?', style: TextStyle(fontSize: 17)),
        content: Text(
          'Tagihan yang sudah terbit tidak berubah — potongannya sudah '
          'tersalin ke sana. Yang berhenti hanya tagihan berikutnya.',
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
      await _repo.deleteDiscount(d.id);
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
      appBar: AppBar(title: const Text('Diskon Langganan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ubah(),
        icon: const Icon(Icons.add),
        label: const Text('Diskon Baru'),
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
                          'Belum ada diskon langganan.\nSeluruh resto membayar '
                          'harga penuh.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: KaataTheme.mutedOf(context)),
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
                            diskon: _items[i],
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
  final BillingDiscount diskon;
  final List<Restaurant> resto;
  final VoidCallback onTap;
  final VoidCallback onHapus;

  const _Kartu({
    required this.diskon,
    required this.resto,
    required this.onTap,
    required this.onHapus,
  });

  @override
  Widget build(BuildContext context) {
    final nama = {for (final r in resto) r.id: r.name};
    final sasaran = diskon.restoIds.map((id) => nama[id] ?? id).toList();
    final fmt = DateFormat('d MMM yyyy', 'id_ID');
    final periode = [
      if (diskon.startsOn != null) 'mulai ${fmt.format(diskon.startsOn!)}',
      if (diskon.endsOn != null) 'sampai ${fmt.format(diskon.endsOn!)}',
    ].join(' · ');
    final berjalan = diskon.isLive();

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
                Expanded(
                  child: Text(diskon.name,
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
                    berjalan ? 'Berjalan' : 'Tidak berlaku',
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
            Text(
              diskon.kind == DiscountKindBilling.percent
                  ? 'Potong ${diskon.value}%'
                  : 'Potong ${_rupiah.format(diskon.value)}',
              style: TextStyle(
                  fontSize: 12.5, color: KaataTheme.brandOf(context)),
            ),
            const SizedBox(height: 4),
            Text(
              sasaran.isEmpty
                  ? 'Belum ada resto dipilih — diskon ini tidak mengenai siapa pun'
                  : '${sasaran.length} resto: ${sasaran.join(', ')}',
              style: TextStyle(
                fontSize: 11.5,
                color:
                    sasaran.isEmpty ? Colors.orange : KaataTheme.mutedOf(context),
              ),
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

class _FormDiskon extends StatefulWidget {
  final BillingDiscount? existing;
  final List<Restaurant> resto;

  const _FormDiskon({this.existing, required this.resto});

  @override
  State<_FormDiskon> createState() => _FormDiskonState();
}

class _FormDiskonState extends State<_FormDiskon> {
  final _formKey = GlobalKey<FormState>();
  final _repo = BillingRepository();

  late final _nama =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _nilai = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.kind == DiscountKindBilling.percent
            ? '${widget.existing!.value}'
            : formatRupiahInput(widget.existing!.value),
  );

  late DiscountKindBilling _jenis =
      widget.existing?.kind ?? DiscountKindBilling.percent;
  late final Set<String> _sasaran = {...?widget.existing?.restoIds};
  late DateTime? _mulai = widget.existing?.startsOn;
  late DateTime? _akhir = widget.existing?.endsOn;
  late bool _aktif = widget.existing?.active ?? true;
  bool _menyimpan = false;

  @override
  void dispose() {
    _nama.dispose();
    _nilai.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    // Diskon tanpa sasaran tidak mengenai apa pun. Menyimpannya berarti
    // meninggalkan aturan yang terlihat berlaku di daftar tapi tidak
    // pernah memotong satu tagihan pun — dan yang mencarinya nanti akan
    // mencari di tempat yang salah.
    if (_sasaran.isEmpty) {
      showAppToast(context, 'Pilih minimal satu resto.', isError: true);
      return;
    }

    final galatPeriode = validatePeriod(startsOn: _mulai, endsOn: _akhir);
    if (galatPeriode != null) {
      showAppToast(context, galatPeriode, isError: true);
      return;
    }

    final nilai = _jenis == DiscountKindBilling.percent
        ? int.tryParse(_nilai.text.trim()) ?? 0
        : parseRupiah(_nilai.text) ?? 0;

    setState(() => _menyimpan = true);
    try {
      await _repo.saveDiscount(BillingDiscount(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nama.text.trim(),
        kind: _jenis,
        value: nilai,
        restoIds: _sasaran.toList(),
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
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Diskon Langganan Baru'
            : 'Ubah Diskon Langganan'),
      ),
      body: Form(
        key: _formKey,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              TextFormField(
                controller: _nama,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  label: requiredLabel('Nama Diskon'),
                  hintText: 'Contoh: Promo Pembukaan, Kompensasi Gangguan',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 18),
              const Text('Potongan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<DiscountKindBilling>(
                      segments: const [
                        ButtonSegment(
                            value: DiscountKindBilling.percent,
                            label: Text('Persen')),
                        ButtonSegment(
                            value: DiscountKindBilling.amount,
                            label: Text('Rupiah')),
                      ],
                      selected: {_jenis},
                      onSelectionChanged: (v) => setState(() {
                        _jenis = v.first;
                        _nilai.clear();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nilai,
                keyboardType: TextInputType.number,
                inputFormatters: _jenis == DiscountKindBilling.percent
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : [ThousandsInputFormatter()],
                decoration: InputDecoration(
                  label: requiredLabel('Nilai'),
                  prefixText:
                      _jenis == DiscountKindBilling.amount ? 'Rp ' : null,
                  suffixText:
                      _jenis == DiscountKindBilling.percent ? '%' : null,
                ),
                validator: (v) {
                  final n = _jenis == DiscountKindBilling.percent
                      ? int.tryParse((v ?? '').trim()) ?? 0
                      : parseRupiah(v ?? '') ?? 0;
                  if (n <= 0) return 'Harus lebih dari 0';
                  if (_jenis == DiscountKindBilling.percent && n > 100) {
                    return 'Maksimal 100%';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Resto yang Dapat',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Text('${_sasaran.length} dipilih',
                      style: TextStyle(
                          fontSize: 11.5, color: KaataTheme.mutedOf(context))),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  border: Border.all(color: KaataTheme.borderOf(context)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: widget.resto.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Belum ada resto terdaftar.',
                            style:
                                TextStyle(color: KaataTheme.mutedOf(context))),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final r in widget.resto)
                            CheckboxListTile(
                              dense: true,
                              value: _sasaran.contains(r.id),
                              title: Text(r.name,
                                  style: const TextStyle(fontSize: 13.5)),
                              subtitle: Text(r.address,
                                  style: const TextStyle(fontSize: 11)),
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
              const SizedBox(height: 20),
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
                      ? 'Dipakai saat tagihan berikutnya terbit'
                      : 'Disimpan, tapi tidak memotong apa pun',
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
                'Diskon dipakai saat tagihan berikutnya diterbitkan. Tagihan '
                'yang sudah terbit tidak ikut berubah — potongannya sudah '
                'tersalin ke sana.',
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
