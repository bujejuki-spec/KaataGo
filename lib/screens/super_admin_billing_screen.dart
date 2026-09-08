import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/billing_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/billing.dart';
import '../models/restaurant.dart';
import '../theme.dart';
import '../widgets/kotak_cari.dart';
import '../utils/kontak_merchant.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';
import '../widgets/dialog_actions.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Billing seluruh resto — hanya Super Admin.
///
/// Dua tab yang sengaja dipisah karena dua pekerjaan yang berbeda
/// waktunya: menetapkan harga dilakukan sekali saat resto bergabung,
/// memverifikasi pembayaran dilakukan tiap bulan.
class SuperAdminBillingScreen extends StatefulWidget {
  const SuperAdminBillingScreen({super.key});

  @override
  State<SuperAdminBillingScreen> createState() =>
      _SuperAdminBillingScreenState();
}

class _SuperAdminBillingScreenState extends State<SuperAdminBillingScreen> {
  final _repo = BillingRepository();
  final _restoRepo = RestaurantRepository();

  List<Restaurant> _resto = const [];

  /// Resto pemilik sebuah tagihan, atau null kalau restonya sudah tidak
  /// ada di daftar — dihapus, atau belum termuat.
  Restaurant? _restoDari(String restoId) {
    for (final r in _resto) {
      if (r.id == restoId) return r;
    }
    return null;
  }
  Map<String, RestoBilling> _setelan = const {};
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
      final resto = await _restoRepo.getAll();
      final setelan = await _repo.allSettings();
      final tagihan = await _repo.allInvoices();
      if (!mounted) return;
      setState(() {
        _resto = resto;
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

  Future<void> _terbitkanSekarang() async {
    try {
      final n = await _repo.generateNow();
      if (!mounted) return;
      showAppToast(
          context, n == 0 ? 'Tidak ada tagihan baru.' : '$n tagihan terbit.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal: $e', isError: true);
    }
  }

  Future<void> _atur(Restaurant resto) async {
    final hasil = await showDialog<RestoBilling>(
      context: context,
      builder: (_) => _DialogSetelan(
        resto: resto,
        awal: _setelan[resto.id] ?? RestoBilling(restoId: resto.id),
      ),
    );
    if (hasil == null || !mounted) return;
    try {
      await _repo.saveSettings(hasil);
      if (!mounted) return;
      showAppToast(context, 'Setelan langganan ${resto.name} tersimpan.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  Future<void> _segarkan(BillingInvoice inv) async {
    try {
      final baru = await _repo.refreshInvoice(inv.id);
      if (!mounted) return;
      showAppToast(
        context,
        baru == inv.amount
            ? 'Nominalnya sudah sesuai.'
            : 'Diperbarui jadi ${_rupiah.format(baru)}.',
      );
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal: $e', isError: true);
    }
  }

  Future<void> _putuskan(BillingInvoice inv, bool terima) async {
    String? alasan;
    if (!terima) {
      alasan = await showDialog<String>(
        context: context,
        builder: (_) => const _DialogTolak(),
      );
      if (alasan == null) return;
    }
    try {
      await _repo.review(inv.id, accept: terima, reason: alasan);
      if (!mounted) return;
      showAppToast(context,
          terima ? 'Tagihan ${inv.id} lunas.' : 'Bukti ${inv.id} ditolak.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menunggu =
        _tagihan.where((t) => t.status == InvoiceStatus.review).length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: KaataTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Billing Merchant'),
          actions: [
            IconButton(
              tooltip: 'Terbitkan tagihan sekarang',
              icon: const Icon(Icons.playlist_add_outlined),
              onPressed: _terbitkanSekarang,
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Paket & Harga'),
              Tab(text: menunggu > 0 ? 'Tagihan ($menunggu)' : 'Tagihan'),
            ],
          ),
        ),
        body: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Gagal memuat: $_galat',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: KaataTheme.mutedOf(context))),
                    ),
                  )
                : TabBarView(
                    children: [_tabPaket(), _tabTagihan()],
                  ),
      ),
    );
  }

  final _cariPaket = TextEditingController();
  final _cariTagihan = TextEditingController();
  String _kataPaket = '';
  String _kataTagihan = '';

  @override
  void dispose() {
    _cariPaket.dispose();
    _cariTagihan.dispose();
    super.dispose();
  }

  List<Restaurant> get _restoTersaring => [
        for (final r in _resto)
          if (cocokCari(_kataPaket, [r.name, r.address, r.category])) r
      ];

  /// Tagihan dikelompokkan per merchant, terbanyak menunggu di atas.
  ///
  /// Satu daftar panjang berisi tagihan dari puluhan merchant menuntut
  /// yang membacanya menyusun sendiri di kepalanya siapa punya apa —
  /// dan yang dikerjakan orang di layar ini justru per merchant:
  /// memeriksa, menerima, lalu menagih yang belum bayar.
  Map<String, List<BillingInvoice>> get _tagihanPerMerchant {
    final hasil = <String, List<BillingInvoice>>{};
    for (final t in _tagihan) {
      final resto = _restoDari(t.restoId);
      final nama = t.restoName ?? resto?.name ?? t.restoId;
      if (!cocokCari(_kataTagihan, [nama, t.id, resto?.address])) continue;
      hasil.putIfAbsent(nama, () => []).add(t);
    }
    final urut = hasil.keys.toList()
      ..sort((a, b) {
        // Yang punya tagihan menunggu diperiksa naik ke atas: itu
        // pekerjaan yang benar-benar menunggu seseorang.
        int menunggu(String k) => hasil[k]!
            .where((t) => t.status == InvoiceStatus.review)
            .length;
        final selisih = menunggu(b).compareTo(menunggu(a));
        return selisih != 0 ? selisih : a.toLowerCase().compareTo(b.toLowerCase());
      });
    return {for (final k in urut) k: hasil[k]!};
  }

  Widget _tabPaket() => Column(
        children: [
          KotakCari(
            controller: _cariPaket,
            petunjuk: 'Cari merchant',
            onUbah: (v) => setState(() => _kataPaket = v),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          ),
          if (_restoTersaring.isEmpty)
            Expanded(
              child: Center(
                child: Text('Tidak ada merchant yang cocok dengan '
                    '"$_kataPaket".'),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
        onRefresh: _muat,
        child: ResponsiveCenter(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            itemCount: _restoTersaring.length,
            itemBuilder: (_, i) {
              final r = _restoTersaring[i];
              final s = _setelan[r.id] ?? RestoBilling(restoId: r.id);
              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                  color: KaataTheme.surfaceOf(context),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: KaataTheme.borderOf(context)),
                ),
                child: ListTile(
                  title: Text(r.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    s.gratis || !s.active
                        ? (s.active ? 'Gratis' : 'Langganan dimatikan')
                        : '${_rupiah.format(s.monthlyPrice)} / bulan · '
                            'tiap tanggal ${s.billingDay} · '
                            'tenggang ${s.graceDays} hari',
                    style: TextStyle(
                        fontSize: 12, color: KaataTheme.mutedOf(context)),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 19),
                  onTap: () => _atur(r),
                ),
              );
            },
          ),
        ),
      ),
            ),
        ],
      );

  Widget _tabTagihan() {
    if (_tagihan.isEmpty) {
      return Center(
        child: Text('Belum ada tagihan terbit.',
            style: TextStyle(color: KaataTheme.mutedOf(context))),
      );
    }
    final kelompok = _tagihanPerMerchant;
    return Column(
      children: [
        KotakCari(
          controller: _cariTagihan,
          petunjuk: 'Cari merchant atau nomor tagihan',
          onUbah: (v) => setState(() => _kataTagihan = v),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        ),
        if (kelompok.isEmpty)
          Expanded(
            child: Center(
              child: Text('Tidak ada tagihan yang cocok dengan '
                  '"$_kataTagihan".'),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                  children: [
                    for (final e in kelompok.entries)
                      _KelompokTagihan(
                        nama: e.key,
                        tagihan: e.value,
                        // Dibuka sendiri saat sedang mencari, dan saat
                        // ada yang menunggu diperiksa — keduanya berarti
                        // isinya memang yang dicari orang.
                        awalTerbuka: _kataTagihan.isNotEmpty ||
                            e.value.any(
                                (t) => t.status == InvoiceStatus.review),
                        resto: _restoDari(e.value.first.restoId),
                        onTerima: (t) => _putuskan(t, true),
                        onTolak: (t) => _putuskan(t, false),
                        onSegarkan: _segarkan,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Satu merchant dan tagihannya, ditumpuk di balik satu baris.
class _KelompokTagihan extends StatelessWidget {
  final String nama;
  final List<BillingInvoice> tagihan;
  final bool awalTerbuka;
  final Restaurant? resto;
  final void Function(BillingInvoice) onTerima;
  final void Function(BillingInvoice) onTolak;
  final void Function(BillingInvoice) onSegarkan;

  const _KelompokTagihan({
    required this.nama,
    required this.tagihan,
    required this.awalTerbuka,
    required this.resto,
    required this.onTerima,
    required this.onTolak,
    required this.onSegarkan,
  });

  @override
  Widget build(BuildContext context) {
    final menunggu =
        tagihan.where((t) => t.status == InvoiceStatus.review).length;
    final belum =
        tagihan.where((t) => t.status == InvoiceStatus.unpaid).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('tagihan-$nama-$awalTerbuka'),
        initiallyExpanded: awalTerbuka,
        leading: const Icon(Icons.storefront_outlined),
        title: Text(nama,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          [
            '${tagihan.length} tagihan',
            if (menunggu > 0) '$menunggu perlu diperiksa',
            if (belum > 0) '$belum belum dibayar',
          ].join(' · '),
          style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
        ),
        trailing: menunggu > 0
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$menunggu',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange)),
              )
            : const Icon(Icons.expand_more),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          for (final t in tagihan)
            _KartuTagihanAdmin(
              invoice: t,
              resto: resto,
              onTerima: () => onTerima(t),
              onTolak: () => onTolak(t),
              onSegarkan: () => onSegarkan(t),
            ),
        ],
      ),
    );
  }
}

class _KartuTagihanAdmin extends StatelessWidget {
  final BillingInvoice invoice;
  final Restaurant? resto;
  final VoidCallback onTerima;
  final VoidCallback onTolak;
  final VoidCallback onSegarkan;

  const _KartuTagihanAdmin({
    required this.invoice,
    required this.resto,
    required this.onTerima,
    required this.onTolak,
    required this.onSegarkan,
  });

  /// Isi tagihan yang dikirim ke merchant.
  ///
  /// Ditulis sekali dan dipakai WhatsApp maupun surel. Dua salinan yang
  /// menyebut nominal yang sama akan berpisah pada perubahan berikutnya,
  /// dan yang berpisah pada pesan tagihan berarti dua angka beredar
  /// untuk satu tagihan.
  String _pesan() {
    final nama = invoice.restoName ?? resto?.name ?? invoice.restoId;
    final periode =
        '${_tanggal.format(invoice.periodStart)} – ${_tanggal.format(invoice.periodEnd)}';
    return 'Halo $nama,\n\n'
        'Berikut tagihan langganan KaataGo yang belum dibayar:\n\n'
        'Merchant : $nama\n'
        'Periode  : $periode\n'
        'Nominal  : ${_rupiah.format(invoice.amount)}\n'
        'Jatuh tempo : ${_tanggal.format(invoice.dueDate)}\n'
        'No. tagihan : ${invoice.id}\n\n'
        'Pembayaran bisa dilakukan lewat menu Tagihan Langganan di '
        'aplikasi KaataGo. Terima kasih.';
  }

  String _subjek() {
    final nama = invoice.restoName ?? resto?.name ?? invoice.restoId;
    return 'Tagihan Langganan KaataGo — $nama '
        '(${_tanggal.format(invoice.periodStart)} – '
        '${_tanggal.format(invoice.periodEnd)})';
  }

  @override
  Widget build(BuildContext context) {
    final (warna, label) = switch (invoice.status) {
      InvoiceStatus.paid => (Colors.green, 'Lunas'),
      InvoiceStatus.waived => (Colors.blueGrey, 'Dibebaskan'),
      InvoiceStatus.review => (Colors.orange, 'Perlu Diperiksa'),
      InvoiceStatus.unpaid => (Colors.red, 'Belum Dibayar'),
      // Jadwal tagihnya berubah sebelum jatuh tempo. Nomornya
      // tetap ada supaya statusnya tidak menggantung terbuka di
      // penyedia pembayaran.
      InvoiceStatus.cancelled => (Colors.grey, 'Dibatalkan'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: invoice.status == InvoiceStatus.review
              ? Colors.orange
              : KaataTheme.borderOf(context),
          width: invoice.status == InvoiceStatus.review ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(invoice.restoName ?? invoice.restoId,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: warna.withOpacity(0.12),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_rupiah.format(invoice.amount)} · ${invoice.id}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (invoice.status == InvoiceStatus.unpaid)
                IconButton(
                  tooltip: 'Hitung ulang mengikuti diskon',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: onSegarkan,
                ),
            ],
          ),
          if (invoice.discountAmount > 0)
            Text(
              'Harga ${_rupiah.format(invoice.grossAmount ?? invoice.amount)} · '
              '${invoice.discountName ?? 'Diskon'} '
              '−${_rupiah.format(invoice.discountAmount)}',
              style: const TextStyle(fontSize: 11.5, color: Colors.green),
            ),
          Text(
            'Jatuh tempo ${_tanggal.format(invoice.dueDate)}',
            style:
                TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
          ),
          if (invoice.paidNote != null && invoice.paidNote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Catatan: ${invoice.paidNote}',
                  style: TextStyle(
                      fontSize: 11.5, color: KaataTheme.mutedOf(context))),
            ),
          if (invoice.confirmedBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Diputuskan ${invoice.confirmedBy}',
                  style: TextStyle(
                      fontSize: 11, color: KaataTheme.mutedOf(context))),
            ),
          if (invoice.hasProof) ...[
            const SizedBox(height: 9),
            GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.memory(base64Decode(invoice.proofBase64!)),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(invoice.proofBase64!),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
          // Hanya untuk yang belum dibayar. Mengirimkan tagihan yang
          // sudah lunas adalah cara tercepat membuat merchant berhenti
          // mempercayai pesan tagihan berikutnya.
          if (invoice.status == InvoiceStatus.unpaid) ...[
            const SizedBox(height: 11),
            if (!punyaWhatsApp(resto?.phone) && !punyaSurel(resto?.email))
              Text(
                'Nomor HP dan email merchant belum diisi — tagihannya '
                'belum bisa dikirim. Lengkapi di List Merchant.',
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              )
            else
              Row(
                children: [
                  if (punyaWhatsApp(resto?.phone))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => bukaWhatsApp(context, resto!.phone,
                            pesan: _pesan()),
                        icon: const Icon(Icons.chat_outlined,
                            size: 17, color: Color(0xFF25D366)),
                        label: const Text('Kirim WA'),
                      ),
                    ),
                  if (punyaWhatsApp(resto?.phone) && punyaSurel(resto?.email))
                    const SizedBox(width: 9),
                  if (punyaSurel(resto?.email))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => bukaSurel(context, resto!.email,
                            subjek: _subjek(), isi: _pesan()),
                        icon: const Icon(Icons.mail_outline, size: 17),
                        label: const Text('Kirim Email'),
                      ),
                    ),
                ],
              ),
          ],
          if (invoice.status == InvoiceStatus.review) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onTerima,
                    icon: const Icon(Icons.check, size: 17),
                    label: const Text('Terima'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTolak,
                    icon: const Icon(Icons.close, size: 17, color: Colors.red),
                    label: const Text('Tolak',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DialogSetelan extends StatefulWidget {
  final Restaurant resto;
  final RestoBilling awal;

  const _DialogSetelan({required this.resto, required this.awal});

  @override
  State<_DialogSetelan> createState() => _DialogSetelanState();
}

class _DialogSetelanState extends State<_DialogSetelan> {
  late final _harga = TextEditingController(
    text: widget.awal.monthlyPrice == 0
        ? ''
        : formatRupiahInput(widget.awal.monthlyPrice),
  );
  late final _tenggang =
      TextEditingController(text: '${widget.awal.graceDays}');
  late int _tanggalTagih = widget.awal.billingDay;
  late bool _aktif = widget.awal.active;

  @override
  void dispose() {
    _harga.dispose();
    _tenggang.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Langganan ${widget.resto.name}',
          style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _harga,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: InputDecoration(
                label: requiredLabel('Biaya per Bulan'),
                prefixText: 'Rp ',
                helperText: 'Kosong atau 0 berarti gratis — tidak pernah '
                    'ditagih dan tidak pernah terkunci.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 16),
            // Tanggal 29–31 boleh dipilih, dan di bulan yang lebih
            // pendek jatuh di hari terakhirnya — 31 jadi 30 di April,
            // 28 di Februari biasa, 29 di Februari kabisat.
            //
            // Dulu daftarnya berhenti di 28 supaya artinya sama di
            // bulan mana pun. Itu menghindari pertanyaannya dengan cara
            // melarang resto memilih tanggal tagihnya sendiri; resto
            // yang siklus kasnya di akhir bulan terpaksa menagih di
            // tanggal yang bukan tanggalnya.
            DropdownButtonFormField<int>(
              value: _tanggalTagih,
              decoration: const InputDecoration(
                labelText: 'Tanggal Tagihan',
                helperText: 'Tiap bulan pada tanggal ini. Tanggal 29–31 '
                    'jatuh di hari terakhir bulan yang lebih pendek.',
                // Tiga, bukan dua. Popup di web lebih sempit daripada
                // layar HP tempat angka ini dipilih, dan kalimat yang
                // terpotong di tengah kata justru kalimat yang
                // menjelaskan kenapa tanggal 31 boleh dipilih.
                helperMaxLines: 3,
              ),
              items: [
                for (var d = 1; d <= 31; d++)
                  DropdownMenuItem(
                    value: d,
                    child: Text(d > 28 ? 'Tanggal $d (atau akhir bulan)'
                        : 'Tanggal $d'),
                  ),
              ],
              onChanged: (v) => setState(() => _tanggalTagih = v ?? 1),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tenggang,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Tenggang (hari)',
                helperText: 'Merchant terkunci setelah lewat tenggang ini',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _aktif,
              title: const Text('Langganan aktif',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                _aktif
                    ? 'Ditagih tiap bulan'
                    : 'Tidak ditagih dan tidak pernah terkunci',
                style: TextStyle(
                    fontSize: 11.5, color: KaataTheme.mutedOf(context)),
              ),
              onChanged: (v) => setState(() => _aktif = v),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // DialogActions, bukan dua tombol berjajar.
        //
        // Baris `actions` milik AlertDialog melipat jadi kolom begitu
        // labelnya tidak muat — dan saat melipat, urutannya mengikuti
        // daftar, jadi Batal berdiri di atas hal yang justru
        // didatangi orangnya.
        DialogActions(
          confirmLabel: 'Simpan',
          onConfirm: () => Navigator.pop(
            context,
            widget.awal.copyWith(
              monthlyPrice: parseRupiah(_harga.text) ?? 0,
              billingDay: _tanggalTagih,
              graceDays: (int.tryParse(_tenggang.text.trim()) ?? 1).clamp(0, 30),
              active: _aktif,
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogTolak extends StatefulWidget {
  const _DialogTolak();

  @override
  State<_DialogTolak> createState() => _DialogTolakState();
}

class _DialogTolakState extends State<_DialogTolak> {
  final _alasan = TextEditingController();

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Tolak Bukti Bayar', style: TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alasannya dibaca merchant. Tanpa alasan, yang ditolak tidak tahu '
            'apa yang harus diperbaiki — dan akan mengirim bukti yang sama '
            'lagi.',
            style: TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _alasan,
            autofocus: true,
            decoration: InputDecoration(
              label: requiredLabel('Alasan'),
              hintText: 'Contoh: nominal tidak sesuai',
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogActions(
          confirmLabel: 'Tolak',
          destructive: true,
          onConfirm: () {
            final t = _alasan.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, t);
          },
        ),
      ],
    );
  }
}
