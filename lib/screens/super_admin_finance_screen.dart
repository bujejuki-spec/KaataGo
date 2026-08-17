import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/billing_repository.dart';
import '../db/gl_journal_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/billing.dart';
import '../models/gl_journal_entry.dart';
import '../theme.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/responsive.dart';
import 'billing_discount_screen.dart';
import 'finance_balance_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_journal_screen.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Keuangan KaataGo sendiri — bukan keuangan resto.
///
/// Seluruh isinya memakai mesin pembukuan yang sama persis dengan resto,
/// hanya dengan penyewa yang berbeda: KaataGo punya barisnya sendiri di
/// tabel restaurants, ditandai `is_platform`. Itulah kenapa layar Saldo,
/// Mapping GL, dan Jurnal di bawah bisa dipakai apa adanya.
///
/// Yang **tidak** ada di sini: Setor Saldo Cash. Menyetor tunai ke
/// rekening sendiri adalah pekerjaan resto yang uangnya menumpuk di
/// laci; KaataGo tidak punya laci.
class SuperAdminFinanceScreen extends StatelessWidget {
  const SuperAdminFinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Finance KaataGo')),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('PENDAPATAN',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 10),
            HubMenuTile(
              icon: Icons.receipt_long_outlined,
              title: 'Riwayat Langganan',
              subtitle: 'Tagihan yang sudah dibayar resto, per bulan',
              color: const Color(0xFF10B981),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BillingHistoryScreen(),
              )),
            ),
            const SizedBox(height: 12),
            HubMenuTile(
              icon: Icons.local_offer_outlined,
              title: 'Diskon Langganan',
              subtitle: 'Potongan harga untuk resto tertentu',
              color: const Color(0xFF6366F1),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BillingDiscountScreen(),
              )),
            ),
            const SizedBox(height: 22),
            Text('PEMBUKUAN KAATAGO',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 10),
            HubMenuTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Saldo & Pengeluaran',
              subtitle: 'Petty cash dan pengeluaran KaataGo',
              color: const Color(0xFF0EA5E9),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const FinanceBalanceScreen(restoId: kPlatformRestoId),
              )),
            ),
            const SizedBox(height: 12),
            HubMenuTile(
              icon: Icons.tag,
              title: 'Mapping GL Account',
              subtitle: 'Nomor akun pendapatan, diskon, dan pengeluaran',
              color: const Color(0xFF8B5CF6),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const FinanceGlMappingScreen(restoId: kPlatformRestoId),
              )),
            ),
            const SizedBox(height: 12),
            HubMenuTile(
              icon: Icons.menu_book_outlined,
              title: 'Jurnal GL KaataGo',
              subtitle: 'Pergerakan uang di pembukuan KaataGo',
              color: const Color(0xFF14B8A6),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const FinanceJournalScreen(restoId: kPlatformRestoId),
              )),
            ),
            const SizedBox(height: 22),
            Text('SELURUH RESTO',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 10),
            HubMenuTile(
              icon: Icons.travel_explore_outlined,
              title: 'Jurnal GL Semua Resto',
              subtitle: 'Hanya untuk dilihat — tidak bisa diubah',
              color: const Color(0xFF64748B),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AllRestoJournalScreen(),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

/// Riwayat tagihan langganan yang sudah dibayar.
class BillingHistoryScreen extends StatefulWidget {
  const BillingHistoryScreen({super.key});

  @override
  State<BillingHistoryScreen> createState() => _BillingHistoryScreenState();
}

class _BillingHistoryScreenState extends State<BillingHistoryScreen> {
  final _repo = BillingRepository();
  List<BillingInvoice> _items = const [];
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
      final items = await _repo.paidInvoices();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<int>(0, (a, b) => a + b.amount);
    final diskon = _items.fold<int>(0, (a, b) => a + b.discountAmount);

    // Dikelompokkan per bulan pembayaran. Yang ingin diketahui dari
    // layar ini hampir selalu "bulan ini masuk berapa", bukan urutan
    // tagihan satu per satu.
    final perBulan = <String, List<BillingInvoice>>{};
    for (final i in _items) {
      final k = DateFormat('MMMM yyyy', 'id_ID')
          .format(i.confirmedAt ?? i.dueDate);
      perBulan.putIfAbsent(k, () => []).add(i);
    }

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Riwayat Langganan')),
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
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFF10B981),
                              Color(0xFF047857),
                            ]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Diterima',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12.5)),
                              const SizedBox(height: 6),
                              Text(_rupiah.format(total),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(
                                '${_items.length} tagihan'
                                '${diskon > 0 ? ' · diskon ${_rupiah.format(diskon)}' : ''}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: Text('Belum ada tagihan yang dibayar.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: KaataTheme.mutedOf(context))),
                          ),
                        for (final entry in perBulan.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 6),
                            child: Row(
                              children: [
                                Text(entry.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const Spacer(),
                                Text(
                                  _rupiah.format(entry.value
                                      .fold<int>(0, (a, b) => a + b.amount)),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          for (final i in entry.value) _BarisTagihan(invoice: i),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _BarisTagihan extends StatelessWidget {
  final BillingInvoice invoice;
  const _BarisTagihan({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final lewatMesin = invoice.paidVia == 'xendit_va';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.restoName ?? invoice.restoId,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(
                  '${invoice.id} · '
                  '${_tanggal.format(invoice.confirmedAt ?? invoice.dueDate)}',
                  style: TextStyle(
                      fontSize: 11.5, color: KaataTheme.mutedOf(context)),
                ),
                if (invoice.discountAmount > 0)
                  Text(
                    '${invoice.discountName ?? 'Diskon'} '
                    '−${_rupiah.format(invoice.discountAmount)}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.orange),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_rupiah.format(invoice.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5)),
              const SizedBox(height: 2),
              // Yang dibedakan adalah bagaimana tagihannya dinyatakan
              // lunas, bukan cara transfernya — dan itu perlu ditulis
              // utuh. "manual" sendirian tidak memberi tahu siapa pun
              // apa yang terjadi; yang membacanya enam bulan lagi akan
              // menebak, dan menebak soal uang selalu mahal.
              Text(
                lewatMesin ? 'Lunas via VA' : 'Dikonfirmasi manual',
                style: TextStyle(
                  fontSize: 10.5,
                  color: lewatMesin
                      ? Colors.green
                      : KaataTheme.mutedOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Jurnal GL seluruh resto — hanya untuk dilihat.
///
/// Tidak ada satu pun tombol yang mengubah isinya, dan itu bukan
/// kelalaian: tiap baris jurnal ditulis pemicu yang mengikuti kejadian
/// nyata di pesanan dan pengeluaran. Tangan yang bisa menulis langsung
/// ke sini adalah tangan yang bisa membuat pembukuan berbeda dari yang
/// benar-benar terjadi — dan itu berlaku untuk Super Admin persis
/// seperti untuk yang lain.
class AllRestoJournalScreen extends StatefulWidget {
  const AllRestoJournalScreen({super.key});

  @override
  State<AllRestoJournalScreen> createState() => _AllRestoJournalScreenState();
}

class _AllRestoJournalScreenState extends State<AllRestoJournalScreen> {
  final _repo = GlJournalRepository();
  final _restoRepo = RestaurantRepository();

  List<GlJournalEntry> _semua = const [];
  Map<String, String> _namaResto = const {};
  String? _saring;
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
      final entries = await _repo.getAll();
      final resto = await _restoRepo.getAll();
      if (!mounted) return;
      setState(() {
        _semua = entries;
        _namaResto = {
          for (final r in resto) r.id: r.name,
          kPlatformRestoId: 'KaataGo',
        };
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

  @override
  Widget build(BuildContext context) {
    final tampil = _saring == null
        ? _semua
        : _semua.where((e) => e.restoId == _saring).toList();

    final debit = tampil
        .where((e) => e.entryType == JournalEntryType.debit)
        .fold<int>(0, (a, b) => a + b.amount);
    final kredit = tampil
        .where((e) => e.entryType == JournalEntryType.credit)
        .fold<int>(0, (a, b) => a + b.amount);

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Jurnal GL Semua Resto'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: 'Saring resto',
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _saring = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Semua resto')),
              for (final e in _namaResto.entries)
                PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
        ],
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
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      color: KaataTheme.surfaceOf(context),
                      child: ResponsiveCenter(
                        child: Row(
                          children: [
                            Expanded(
                              child: _Angka(
                                  label: 'Total Debit',
                                  nilai: debit,
                                  warna: Colors.red),
                            ),
                            Expanded(
                              child: _Angka(
                                  label: 'Total Kredit',
                                  nilai: kredit,
                                  warna: Colors.green),
                            ),
                            Expanded(
                              child: _Angka(
                                  label: 'Baris',
                                  nilai: tampil.length,
                                  warna: KaataTheme.mutedOf(context),
                                  rupiah: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: tampil.isEmpty
                          ? Center(
                              child: Text('Belum ada jurnal.',
                                  style: TextStyle(
                                      color: KaataTheme.mutedOf(context))),
                            )
                          : RefreshIndicator(
                              onRefresh: _muat,
                              child: ResponsiveCenter(
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 12, 14, 28),
                                  itemCount: tampil.length,
                                  itemBuilder: (_, i) => _BarisJurnal(
                                    entry: tampil[i],
                                    namaResto:
                                        _namaResto[tampil[i].restoId] ??
                                            tampil[i].restoId,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _Angka extends StatelessWidget {
  final String label;
  final int nilai;
  final Color warna;
  final bool rupiah;

  const _Angka({
    required this.label,
    required this.nilai,
    required this.warna,
    this.rupiah = true,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: KaataTheme.mutedOf(context))),
          const SizedBox(height: 3),
          Text(rupiah ? _rupiah.format(nilai) : '$nilai',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: warna)),
        ],
      );
}

class _BarisJurnal extends StatelessWidget {
  final GlJournalEntry entry;
  final String namaResto;

  const _BarisJurnal({required this.entry, required this.namaResto});

  @override
  Widget build(BuildContext context) {
    final masuk = entry.entryType == JournalEntryType.credit;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Row(
        children: [
          Icon(masuk ? Icons.south_west : Icons.north_east,
              size: 17, color: masuk ? Colors.green : Colors.red),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.glCode} — ${entry.glName ?? ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                  '$namaResto · ${_tanggal.format(entry.entryDate)} '
                  '${entry.entryTime.substring(0, 5)}',
                  style: TextStyle(
                      fontSize: 11, color: KaataTheme.mutedOf(context)),
                ),
                if (entry.description != null)
                  Text(entry.description!,
                      style: TextStyle(
                          fontSize: 11,
                          color: KaataTheme.mutedOf(context))),
              ],
            ),
          ),
          Text(
            _rupiah.format(entry.amount),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: masuk ? Colors.green : Colors.red),
          ),
        ],
      ),
    );
  }
}
