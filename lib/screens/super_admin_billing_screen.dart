import 'dart:convert';

import '../db/paket_langganan_repository.dart';
import '../models/paket_langganan.dart';
import '../utils/pesan_galat.dart';
import '../widgets/lencana_paket_aktif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/bank_account_repository.dart';
import '../db/billing_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/bank_account.dart';
import '../models/billing.dart';
import '../models/restaurant.dart';
import '../theme.dart';
import '../widgets/kotak_cari.dart';
import '../utils/kontak_merchant.dart';
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

  /// Rekening KaataGo, untuk merchant yang ditagih lewat transfer.
  BankAccount? _rekeningKaataGo;
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
      // Gagalnya tidak menggagalkan halaman: rekening ini cuma dipakai
      // sebagian merchant, dan daftar tagihan tetap harus terbuka.
      BankAccount? rekening;
      try {
        rekening = await BankAccountRepository().utama(kPlatformRestoId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _resto = resto;
        _setelan = setelan;
        _tagihan = tagihan;
        _rekeningKaataGo = rekening;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = '$e';
        _memuat = false;
      });
    }
    // Keadaan paketnya menyusul, dan kegagalannya tidak menggagalkan
    // daftarnya: baris tanpa penanda paket masih berguna, layar kosong
    // tidak.
    try {
      final p = await _paketRepo.keadaanSemua();
      if (mounted) setState(() => _paket = p);
    } catch (_) {}
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

  final _paketRepo = PaketLanggananRepository();

  /// Keadaan paket tiap merchant, ditarik sekali untuk seluruh daftar.
  var _paket = const <String, KeadaanLangganan>{};

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

  /// Paket dan masa percobaan, terpisah dari harga dan tanggal tagih.
  Future<void> _aturPaket(Restaurant resto) async {
    final hasil = await showDialog<_PilihanPaket>(
      context: context,
      builder: (_) => _DialogPaket(resto: resto),
    );
    if (hasil == null || !mounted) return;
    try {
      if (hasil.percobaan) {
        final sampai = await _paketRepo.setelPercobaan(
          restoId: resto.id,
          hari: hasil.hariPercobaan!,
          paket: hasil.paketPercobaan!,
        );
        if (!mounted) return;
        showAppToast(
          context,
          'Percobaan ${hasil.paketPercobaan!.label} untuk ${resto.name} '
          'sampai ${DateFormat('d MMM yyyy', 'id_ID').format(sampai)}.',
        );
      } else {
        await _paketRepo.setelPaket(restoId: resto.id, paket: hasil.paket);
        if (!mounted) return;
        showAppToast(
          context,
          hasil.paket == null
              ? 'Paket ${resto.name} dilepas.'
              : 'Paket ${resto.name} disetel ke ${hasil.paket!.label}, '
                  'akses menunya ikut disesuaikan.',
        );
      }
      // Lencana di beranda merchant itu ikut berubah.
      LencanaPaketAktif.lupakan(resto.id);
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, pesanGalat(e), isError: true);
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
      // Tagihan yang dibatalkan tidak ditampilkan.
      //
      // Ia bukan pekerjaan dan bukan riwayat yang dibaca siapa pun di
      // sini: tidak menunggu diperiksa, tidak menunggu dibayar, dan
      // tidak menambah apa-apa ke jumlah yang tertagih. Yang
      // dilakukannya cuma menumpuk di antara baris yang memang harus
      // dilihat — dan makin banyak baris mati di satu daftar, makin
      // besar peluang yang hidup ikut terlewat.
      //
      // Barisnya tetap ada di basis data. Yang dihilangkan tampilannya.
      if (t.status == InvoiceStatus.cancelled) continue;

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
                            'tenggang ${s.graceDays} hari · '
                            '${s.tagihLewatTransfer ? 'Transfer' : 'VA'}',
                    style: TextStyle(
                        fontSize: 12, color: KaataTheme.mutedOf(context)),
                  ),
                  // Dua hal yang berbeda: harga dan tanggal tagihnya
                  // (ketuk barisnya), dan paket berikut masa
                  // percobaannya (tombol di kanan). Menggabungkannya
                  // jadi satu dialog panjang membuat yang cuma ingin
                  // memberi trial menggulir melewati enam kolom yang
                  // tidak dia sentuh.
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PenandaBaris(keadaan: _paket[r.id]),
                      IconButton(
                        icon: const Icon(Icons.workspace_premium_outlined,
                            size: 19),
                        tooltip: 'Paket & masa percobaan',
                        onPressed: () => _aturPaket(r),
                      ),
                      const Icon(Icons.edit_outlined, size: 19),
                    ],
                  ),
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
                        setelan: _setelan[e.value.first.restoId],
                        rekeningKaataGo: _rekeningKaataGo,
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
  final RestoBilling? setelan;
  final BankAccount? rekeningKaataGo;
  final void Function(BillingInvoice) onTerima;
  final void Function(BillingInvoice) onTolak;
  final void Function(BillingInvoice) onSegarkan;

  const _KelompokTagihan({
    required this.nama,
    required this.tagihan,
    required this.awalTerbuka,
    required this.resto,
    required this.setelan,
    required this.rekeningKaataGo,
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
        // Dua penanda, dan keduanya menjawab pertanyaan berbeda.
        //
        // Merah: tagihan yang belum dibayar sama sekali — itu uang yang
        // belum masuk, dan itulah yang dicari saat membuka layar ini.
        // Oranye: yang sudah dibayar dan menunggu diperiksa — pekerjaan
        // yang ada di tangan KaataGo, bukan di tangan merchant.
        //
        // Kalau keduanya ada, merah yang dipajang: yang menunggu
        // diperiksa akan terlihat sendiri begitu kelompoknya dibuka,
        // sedangkan tunggakan adalah alasan membukanya.
        trailing: (belum > 0 || menunggu > 0)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (belum > 0) _Penanda(jumlah: belum, warna: Colors.red),
                  if (belum > 0 && menunggu > 0) const SizedBox(width: 6),
                  if (menunggu > 0)
                    _Penanda(jumlah: menunggu, warna: Colors.orange),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 20),
                ],
              )
            : const Icon(Icons.expand_more),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          for (final t in tagihan)
            _KartuTagihanAdmin(
              invoice: t,
              resto: resto,
              setelan: setelan,
              rekeningKaataGo: rekeningKaataGo,
              onTerima: () => onTerima(t),
              onTolak: () => onTolak(t),
              onSegarkan: () => onSegarkan(t),
            ),
        ],
      ),
    );
  }
}

/// Bulatan berisi angka di ujung baris merchant.
class _Penanda extends StatelessWidget {
  final int jumlah;
  final Color warna;

  const _Penanda({required this.jumlah, required this.warna});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$jumlah',
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.bold, color: warna)),
    );
  }
}

class _KartuTagihanAdmin extends StatelessWidget {
  final BillingInvoice invoice;
  final Restaurant? resto;

  /// Cara merchant ini ditagih, dan rekening KaataGo kalau lewat
  /// transfer. Keduanya masuk ke pesan tagihan: pengingat membayar yang
  /// tidak menyebutkan ke mana membayar cuma kabar cemas.
  final RestoBilling? setelan;
  final BankAccount? rekeningKaataGo;
  final VoidCallback onTerima;
  final VoidCallback onTolak;
  final VoidCallback onSegarkan;

  const _KartuTagihanAdmin({
    required this.invoice,
    required this.resto,
    required this.setelan,
    required this.rekeningKaataGo,
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
    // Cara bayarnya ikut ditulis, berikut nomornya.
    //
    // Pengingat yang cuma menyebut nominal dan tanggal memaksa yang
    // menerimanya membuka aplikasi dulu hanya untuk mencari nomor — dan
    // sebagian tidak jadi membuka sama sekali. Nomor yang ada di pesan
    // bisa langsung disalin ke aplikasi bank.
    final caraBayar = StringBuffer();
    if (setelan?.tagihLewatTransfer ?? false) {
      final r = rekeningKaataGo;
      caraBayar.writeln('Transfer ke rekening KaataGo:');
      if (r == null) {
        caraBayar.writeln('(rekening belum diatur — hubungi KaataGo)');
      } else {
        caraBayar.writeln('Bank      : ${r.bankName}');
        caraBayar.writeln('Rekening  : ${r.accountNumber}');
        caraBayar.writeln('Atas nama : ${r.accountHolder}');
      }
    } else if (invoice.vaHidup) {
      caraBayar.writeln('Bayar lewat Virtual Account:');
      caraBayar.writeln('Bank : ${invoice.vaBank ?? '-'}');
      caraBayar.writeln('No VA : ${invoice.vaNumber}');
    } else {
      caraBayar.writeln(
          'Nomor Virtual Account-nya bisa dilihat di aplikasi KaataGo, '
          'menu Tagihan Langganan.');
    }

    return 'Halo $nama,\n\n'
        'Berikut tagihan langganan KaataGo yang belum dibayar:\n\n'
        'Merchant : $nama\n'
        'Periode  : $periode\n'
        'Nominal  : ${_rupiah.format(invoice.amount)}\n'
        'Jatuh tempo : ${_tanggal.format(invoice.dueDate)}\n'
        'No. tagihan : ${invoice.id}\n\n'
        '$caraBayar\n'
        'Setelah membayar, silakan unggah bukti pembayaran di aplikasi '
        'KaataGo — menu Tagihan Langganan — supaya tagihannya bisa kami '
        'periksa dan ditandai lunas.\n\n'
        'Terima kasih.';
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
  late final _tenggang =
      TextEditingController(text: '${widget.awal.graceDays}');
  late String _caraTagih = widget.awal.paymentMethod;
  late int _tanggalTagih = widget.awal.billingDay;
  late bool _aktif = widget.awal.active;

  @override
  void dispose() {
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
            const SizedBox(height: 12),
            // Cara menagihnya, per merchant.
            //
            // VA menuntut akun penyedia pembayaran yang aktif, dan
            // sebagian merchant ditagih pada masa ketika akunnya belum
            // siap. Yang terjadi kalau VA-nya tidak terbit: tagihannya
            // tetap ada, jatuh temponya tetap berjalan, dan merchant
            // tidak punya satu pun nomor untuk membayar.
            DropdownButtonFormField<String>(
              value: _caraTagih,
              decoration: const InputDecoration(
                labelText: 'Cara Penagihan',
                helperText: 'VA lewat penyedia, atau transfer ke rekening '
                    'KaataGo',
                helperMaxLines: 2,
              ),
              items: const [
                DropdownMenuItem(
                    value: 'va', child: Text('Virtual Account')),
                DropdownMenuItem(
                    value: 'transfer', child: Text('Transfer Rekening')),
              ],
              onChanged: (v) => setState(() => _caraTagih = v ?? 'va'),
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
              // Harganya TIDAK ikut disimpan dari sini.
              //
              // Ia mengikuti harga paket yang berlaku, dan dua tempat
              // yang sama-sama boleh menentukan satu angka akan
              // berselisih — biasanya pada hari harga paketnya naik,
              // dan yang membayar harga lama adalah merchant yang
              // nilainya kebetulan pernah diketik tangan di sini.
              billingDay: _tanggalTagih,
              graceDays: (int.tryParse(_tenggang.text.trim()) ?? 1).clamp(0, 30),
              active: _aktif,
              paymentMethod: _caraTagih,
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

/// Apa yang dipilih KaataGo Admin di dialog paket.
///
/// Salah satu saja: menyetel langganan, atau memberi masa percobaan.
/// Keduanya sekaligus tidak punya arti — memberi trial pada merchant
/// yang sudah berlangganan berarti menggratiskan yang sudah membayar.
class _PilihanPaket {
  final Paket? paket;
  final int? hariPercobaan;
  final Paket? paketPercobaan;

  const _PilihanPaket.langganan(this.paket)
      : hariPercobaan = null,
        paketPercobaan = null;

  const _PilihanPaket.percobaan(int hari, Paket paket)
      : hariPercobaan = hari,
        paketPercobaan = paket,
        paket = null;

  bool get percobaan => hariPercobaan != null;
}

/// Menyetel paket dan masa percobaan satu merchant.
///
/// ── Kenapa keduanya dipisah tegas ────────────────────────────────────
///
/// Sebelumnya tombol paket dan kolom percobaan berdiri berdampingan
/// tanpa batas yang jelas, dan keduanya memang mengerjakan hal yang
/// sangat berbeda: yang satu memulai penagihan bulanan, yang satu
/// memberi gratis sekian hari. Yang menekan "Basic" karena ingin
/// mencobakan Basic justru membuat merchant itu langsung berlangganan.
///
/// Sekarang dua bagian dengan judul dan kartunya sendiri, dan yang
/// mengubah keadaan cuma satu tombol di masing-masing bagian.
class _DialogPaket extends StatefulWidget {
  final Restaurant resto;

  const _DialogPaket({required this.resto});

  @override
  State<_DialogPaket> createState() => _DialogPaketState();
}

class _DialogPaketState extends State<_DialogPaket> {
  final _repo = PaketLanggananRepository();
  final _hari = TextEditingController();

  KeadaanLangganan? _keadaan;
  bool _memuat = true;

  /// Paket yang dipilih untuk masa percobaan.
  Paket _paketPercobaan = Paket.premium;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _hari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    try {
      final k = await _repo.keadaan(widget.resto.id);
      if (!mounted) return;
      setState(() {
        _keadaan = k;
        // Lama percobaan yang sudah pernah disetel dibaca kembali, bukan
        // dikembalikan ke 14. Kolom yang melupakan angka yang barusan
        // diisi orang membuat setiap pembukaan berikutnya terlihat
        // seperti perubahan yang gagal tersimpan.
        _paketPercobaan = k.trialPaket ?? Paket.premium;
        _hari.text = '${k.trialHari ?? 14}';
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hari.text = '14';
        _memuat = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final k = _keadaan;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      // Judulnya dipendekkan sendiri, bukan dibiarkan mendorong lebar
      // dialognya di layar sempit.
      title: Text('Paket ${widget.resto.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        // Dipatok selebar dialognya supaya isinya tidak mengembang
        // mengikuti teks terpanjang — di layar 5 inci itulah yang
        // membuat tombolnya terpotong.
        width: 340,
        child: _memuat
            ? const SizedBox(
                height: 90, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Sekarang(keadaan: k),
                    const SizedBox(height: 20),
                    _Bagian(
                      judul: 'Langganan',
                      keterangan:
                          'Paketnya disetel lewat pengajuan langganan yang '
                          'disetujui, bukan dari sini — supaya tiap paket '
                          'yang berjalan punya bukti bayarnya.',
                      anak: [
                        // Yang tersisa cuma melepas, dan itu bukan pintu
                        // kedua untuk berlangganan.
                        //
                        // Menyetel paket dari sini berarti ada merchant
                        // yang paketnya berjalan tanpa satu pun
                        // pengajuan — tidak ada bukti transfer, tidak
                        // ada jejak siapa yang menyetujui, dan tidak ada
                        // yang bisa ditunjukkan saat ditanya kenapa dia
                        // ditagih. Jadi pintunya ditutup.
                        //
                        // Melepas dibiarkan justru karena kekeliruan
                        // harus punya jalan pulang: paket yang salah
                        // disetujui tidak boleh jadi keadaan yang tidak
                        // bisa dibatalkan siapa pun.
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: k?.paket == null
                                ? null
                                : () => Navigator.pop(context,
                                    const _PilihanPaket.langganan(null)),
                            child: const Text('Lepas Paket'),
                          ),
                        ),
                      ],
                    ),
                    // Masa percobaan cuma untuk yang BELUM berlangganan.
                    //
                    // set_trial_resto menyetel paket jadi null dan
                    // harganya jadi nol — memberi percobaan ke merchant
                    // yang sudah membayar diam-diam membatalkan
                    // langganannya dan menghentikan penagihannya. Yang
                    // menemukannya bukan kita, melainkan tagihan yang
                    // berhenti datang.
                    if (k?.paket != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Merchant ini sudah berlangganan, jadi masa '
                        'percobaan tidak ditawarkan. Lepas paketnya dulu '
                        'kalau memang mau dikembalikan ke percobaan.',
                        style: TextStyle(
                            fontSize: 11.5, height: 1.4, color: muted),
                      ),
                    ] else ...[
                    const SizedBox(height: 18),
                    _Bagian(
                      judul: 'Masa percobaan',
                      keterangan:
                          'Gratis sekian hari dengan akses paket yang dicoba. '
                          'Dua hari sebelum habis, merchant diingatkan sendiri '
                          'lewat aplikasinya.',
                      anak: [
                        _PilihPaketBaris(
                          terpilih: _paketPercobaan,
                          onPilih: (p) => setState(() => _paketPercobaan = p!),
                          bolehKosong: false,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _hari,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Hari',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor:
                                        warnaPaket(_paketPercobaan)),
                                onPressed: () {
                                  final hari = int.tryParse(_hari.text) ?? 0;
                                  if (hari < 1 || hari > 365) {
                                    showAppToast(
                                        context,
                                        'Lama percobaannya antara 1 dan 365 '
                                        'hari.',
                                        isError: true);
                                    return;
                                  }
                                  Navigator.pop(
                                    context,
                                    _PilihanPaket.percobaan(
                                        hari, _paketPercobaan),
                                  );
                                },
                                // Satu baris, tidak dipatahkan jadi
                                // "Beri Percobaa / n" seperti dulu.
                                child: const Text('Beri Percobaan',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (k?.dalamPercobaan == true) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Memberi percobaan lagi menimpa yang sedang berjalan.',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ],
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}

/// Keadaan merchant ini sekarang, disebut lebih dulu.
///
/// Tanpa ini yang membuka dialog harus menebak sendiri apakah dia sedang
/// mengubah sesuatu yang sudah berjalan atau memulai dari nol.
class _Sekarang extends StatelessWidget {
  final KeadaanLangganan? keadaan;

  const _Sekarang({required this.keadaan});

  @override
  Widget build(BuildContext context) {
    final k = keadaan;
    final muted = KaataTheme.mutedOf(context);

    final (teks, warna) = switch (k) {
      null => ('Keadaannya belum terbaca.', null),
      _ when k.paket != null => (
          'Berlangganan ${k.paket!.label}.',
          warnaPaket(k.paket!)
        ),
      _ when k.dalamPercobaan => (
          'Percobaan ${k.trialPaket?.label ?? ''} — sisa ${k.sisaHari} hari.',
          warnaPaket(k.trialPaket ?? Paket.premium)
        ),
      _ when k.percobaanHabis => (
          'Percobaan sudah habis — merchant terkunci.',
          const Color(0xFFEF4444)
        ),
      _ => ('Di luar jalur paket — berjalan tanpa pembatasan.', null),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (warna ?? Colors.grey).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: warna ?? muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(teks,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: warna ?? muted)),
          ),
        ],
      ),
    );
  }
}

/// Satu bagian bertajuk, dengan jarak yang sama di mana pun dipakai.
class _Bagian extends StatelessWidget {
  final String judul;
  final String keterangan;
  final List<Widget> anak;

  const _Bagian({
    required this.judul,
    required this.keterangan,
    required this.anak,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(judul,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 3),
        Text(keterangan,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: muted)),
        const SizedBox(height: 12),
        ...anak,
      ],
    );
  }
}

/// Dua paket berdampingan, dipilih salah satu.
///
/// Berdampingan, bukan bertumpuk: keduanya pilihan sederajat, dan dua
/// tombol lebar bertumpuk terbaca sebagai dua tindakan berurutan.
class _PilihPaketBaris extends StatelessWidget {
  final Paket? terpilih;
  final ValueChanged<Paket?> onPilih;
  final bool bolehKosong;

  const _PilihPaketBaris({
    required this.terpilih,
    required this.onPilih,
    this.bolehKosong = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final p in Paket.values) ...[
          if (p != Paket.values.first) const SizedBox(width: 10),
          Expanded(
            child: _KotakPaket(
              paket: p,
              dipilih: terpilih == p,
              onTap: () => onPilih(
                  bolehKosong && terpilih == p ? null : p),
            ),
          ),
        ],
      ],
    );
  }
}

class _KotakPaket extends StatelessWidget {
  final Paket paket;
  final bool dipilih;
  final VoidCallback onTap;

  const _KotakPaket({
    required this.paket,
    required this.dipilih,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final warna = warnaPaket(paket);
    return Material(
      color: dipilih ? warna : KaataTheme.softFillOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: dipilih ? warna : KaataTheme.borderOf(context)),
          ),
          child: Text(
            paket.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: dipilih ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Penanda paket di baris daftar merchant.
///
/// Ada karena tanpanya layar ini tidak punya satu pun tempat yang
/// menyebut siapa yang sedang percobaan — dan yang sedang percobaan
/// justru merchant yang paling perlu dilihat, karena aksesnya berhenti
/// pada tanggal tertentu.
class _PenandaBaris extends StatelessWidget {
  final KeadaanLangganan? keadaan;

  const _PenandaBaris({this.keadaan});

  @override
  Widget build(BuildContext context) {
    final k = keadaan;
    if (k == null || k.belumPernahDiberiPaket) return const SizedBox.shrink();

    final (teks, warna) = switch (k) {
      _ when k.paket != null => (k.paket!.label, warnaPaket(k.paket!)),
      _ when k.dalamPercobaan => (
          'Trial ${k.sisaHari}h',
          warnaPaket(k.trialPaket ?? Paket.premium)
        ),
      _ when k.percobaanHabis => ('Terkunci', const Color(0xFFEF4444)),
      _ => ('', null),
    };
    if (teks.isEmpty || warna == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(teks,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.bold, color: warna)),
    );
  }
}
