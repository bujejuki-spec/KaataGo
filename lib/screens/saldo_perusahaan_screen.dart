import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/balance_topup_repository.dart';
import '../models/balance_topup.dart';
import '../db/expense_repository.dart';
import '../db/expense_gl_account_repository.dart';
import '../models/expense.dart';
import '../models/expense_gl_account.dart';
import '../db/bank_account_repository.dart';
import '../db/company_balance_repository.dart';
import '../models/bank_account.dart';
import '../models/company_deposit.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/akses_menu.dart';
import '../utils/gambar_base64.dart';
import '../utils/lebar_web.dart';
import '../utils/pesan_galat.dart';
import '../utils/photo_picker.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/judul_bagian.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

/// Uang perusahaan, dan di mana ia berada.
///
/// Layar Saldo & Pengeluaran menjawab pertanyaan harian: berapa yang
/// masuk hari ini, berapa yang dibelanjakan, berapa isi laci. Layar ini
/// menjawab pertanyaan yang lain sama sekali — berapa uang perusahaan
/// seluruhnya, dan berapa yang di tangan berbanding yang di rekening.
///
/// Angkanya dibaca dari pergerakan dua akun GL, lewat satu fungsi di
/// server. Menghitungnya ulang di sini dari tabel pesanan dan setoran
/// akan melahirkan angka kedua yang berpisah dari jurnalnya pada
/// perubahan berikutnya.
class SaldoPerusahaanScreen extends StatefulWidget {
  const SaldoPerusahaanScreen({super.key});

  @override
  State<SaldoPerusahaanScreen> createState() => _SaldoPerusahaanScreenState();
}

class _SaldoPerusahaanScreenState extends State<SaldoPerusahaanScreen> {
  final _repo = CompanyBalanceRepository();
  final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _waktu = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

  int _cash = 0;
  int _bank = 0;
  List<CompanyDeposit> _setoran = const [];
  List<BalanceTopup> _modal = const [];

  /// Pengeluaran yang dibayar dari uang perusahaan — bukan dari petty
  /// cash kasir, yang punya layarnya sendiri.
  List<Expense> _pengeluaran = const [];
  List<ExpenseGlAccount> _akunBiaya = const [];
  List<BankAccount> _rekening = const [];
  bool _memuat = true;
  String? _galat;

  /// Terbuka atau tertutupnya tiap bagian.
  ///
  /// Ketiganya tumbuh terus dan tidak pernah menyusut; yang dicari orang
  /// saat membuka layar ini adalah kedua saldo di atas, bukan daftar
  /// panjang di bawahnya.
  bool _setoranTerbuka = true;
  bool _biayaTerbuka = true;
  bool _modalTerbuka = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  String? get _restoId => context.read<AuthProvider>().restoId;

  Future<void> _muat() async {
    final restoId = _restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final saldo = await _repo.saldo(restoId);
      final setoran = await _repo.setoran(restoId);
      final modal = await BalanceTopupRepository().getForResto(restoId);
      final biaya = await ExpenseRepository().getForResto(restoId);
      final akunBiaya =
          await ExpenseGlAccountRepository().getForResto(restoId);
      // Rekeningnya pelengkap: setoran tetap bisa dicatat tanpa daftar
      // rekening, cuma tujuannya jadi tidak disebut.
      List<BankAccount> rekening = const [];
      try {
        rekening = await BankAccountRepository().untukResto(restoId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _cash = saldo.cash;
        _bank = saldo.bank;
        _setoran = setoran;
        _modal = modal;
        // Yang dibayar dari petty cash tidak ikut: itu urusan layar
        // Saldo & Pengeluaran, dan menampilkannya di sini membuat satu
        // pengeluaran terbaca dua kali.
        _pengeluaran = [
          for (final e in biaya)
            if (e.fundSource == 'cash' || e.fundSource == 'bank') e,
        ];
        _akunBiaya = akunBiaya;
        _rekening = rekening;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = pesanGalat(e);
        _memuat = false;
      });
    }
  }

  Future<void> _setelSaldoAwal() async {
    final restoId = _restoId;
    if (restoId == null) return;
    final tersimpan = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogSaldoAwal(restoId: restoId),
    );
    if (tersimpan == true) {
      if (!mounted) return;
      _muat();
    }
  }

  Future<void> _topUpModal() async {
    final restoId = _restoId;
    if (restoId == null) return;
    final tersimpan = await showDialog<bool>(
      context: context,
      builder: (_) => _FormModal(restoId: restoId),
    );
    if (tersimpan == true) {
      if (!mounted) return;
      showAppToast(context, 'Setoran modal tercatat.');
      _muat();
    }
  }

  Future<void> _catatPengeluaran() async {
    final restoId = _restoId;
    if (restoId == null) return;
    final tersimpan = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogPengeluaran(
        restoId: restoId,
        akunBiaya: _akunBiaya,
        saldoCash: _cash,
        saldoBank: _bank,
      ),
    );
    if (tersimpan == true) {
      if (!mounted) return;
      showAppToast(context, 'Pengeluaran tercatat.');
      _muat();
    }
  }

  Future<void> _setor() async {
    final restoId = _restoId;
    if (restoId == null) return;
    final hasil = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogSetor(
        restoId: restoId,
        saldoCash: _cash,
        rekening: _rekening,
      ),
    );
    if (hasil == true) {
      if (!mounted) return;
      showAppToast(context, 'Setoran tercatat.');
      _muat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return berdasarkanAkses(
      context,
      'Saldo Perusahaan',
      Scaffold(
        backgroundColor: KaataTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Saldo Perusahaan'),
          actions: [
            // Di menu tiga titik, bukan tombol tetap: menyetel saldo awal
            // dilakukan sekali saat pembukuannya dimulai, bukan pekerjaan
            // harian. Tombol yang selalu terpampang untuk hal yang
            // dilakukan setahun sekali cuma mengundang orang menekannya.
            if (bolehUbahDiSini(context))
              PopupMenuButton<String>(
                tooltip: 'Lainnya',
                onSelected: (p) {
                  if (p == 'saldo-awal') _setelSaldoAwal();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'saldo-awal',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(Icons.tune),
                      title: Text('Setel Saldo Awal'),
                      subtitle: Text('Samakan dengan mutasi bank',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 44, color: Colors.red),
                          const SizedBox(height: 12),
                          Text('Gagal memuat: $_galat',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton(
                              onPressed: _muat, child: const Text('Coba Lagi')),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _muat,
                    child: ResponsiveCenter(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        children: [
                          _KartuTotal(total: _cash + _bank, rp: _rp),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _KartuSaldo(
                                  ikon: Icons.payments_outlined,
                                  judul: 'Saldo Cash',
                                  nilai: _rp.format(_cash),
                                  keterangan: 'Tunai yang dipegang perusahaan',
                                  warna: const Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _KartuSaldo(
                                  ikon: Icons.account_balance_outlined,
                                  judul: 'Saldo Bank',
                                  nilai: _rp.format(_bank),
                                  keterangan: 'Uang di Rekening Perusahaan',
                                  warna: const Color(0xFF0EA5E9),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _Keterangan(),
                          const SizedBox(height: 20),
                          JudulBagian(
                            title: 'Setoran ke Bank',
                            open: _setoranTerbuka,
                            count: _setoran.length,
                            onToggle: () => setState(
                                () => _setoranTerbuka = !_setoranTerbuka),
                            action: bolehUbahDiSini(context)
                                ? TombolPil(
                                    icon: Icons.account_balance_outlined,
                                    label: 'Setor',
                                    color: const Color(0xFF6366F1),
                                    onTap: _setor,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 8),
                          if (!_setoranTerbuka)
                            const SizedBox.shrink()
                          else if (_setoran.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  'Belum ada setoran dari kas perusahaan.',
                                  style: TextStyle(
                                      color: KaataTheme.mutedOf(context)),
                                ),
                              ),
                            )
                          else
                            for (final s in _setoran)
                              _BarisSetoran(
                                  setoran: s, rp: _rp, waktu: _waktu),
                          const SizedBox(height: 20),
                          JudulBagian(
                            title: 'Pengeluaran Perusahaan',
                            open: _biayaTerbuka,
                            count: _pengeluaran.length,
                            onToggle: () => setState(
                                () => _biayaTerbuka = !_biayaTerbuka),
                            action: bolehUbahDiSini(context)
                                ? TombolPil(
                                    icon: Icons.remove_circle_outline,
                                    label: 'Catat',
                                    color: const Color(0xFFEF4444),
                                    onTap: _catatPengeluaran,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 8),
                          if (!_biayaTerbuka)
                            const SizedBox.shrink()
                          else if (_pengeluaran.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  'Belum ada pengeluaran dari uang perusahaan.',
                                  style: TextStyle(
                                      color: KaataTheme.mutedOf(context)),
                                ),
                              ),
                            )
                          else
                            for (final e in _pengeluaran)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFFEF4444)
                                        .withOpacity(0.12),
                                    child: const Icon(
                                        Icons.receipt_long_outlined,
                                        color: Color(0xFFEF4444),
                                        size: 20),
                                  ),
                                  title: Text(e.description,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  subtitle: Text(
                                    'Dari ${e.labelSumberDana}'
                                    '${e.glCode != null ? ' · GL ${e.glCode}' : ''}'
                                    '\n${_waktu.format(e.createdAt.toLocal())} · ${e.createdBy}',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  trailing: Text('- ${_rp.format(e.amount)}',
                                      style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  isThreeLine: true,
                                ),
                              ),
                          const SizedBox(height: 20),
                          JudulBagian(
                            title: 'Setoran Modal',
                            open: _modalTerbuka,
                            count: _modal.length,
                            onToggle: () =>
                                setState(() => _modalTerbuka = !_modalTerbuka),
                            action: bolehUbahDiSini(context)
                                ? TombolPil(
                                    icon: Icons.add_circle_outline,
                                    label: 'Top Up',
                                    color: const Color(0xFF14B8A6),
                                    onTap: _topUpModal,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 8),
                          if (!_modalTerbuka)
                            const SizedBox.shrink()
                          else if (_modal.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text('Belum ada setoran modal.',
                                    style: TextStyle(
                                        color: KaataTheme.mutedOf(context))),
                              ),
                            )
                          else
                            for (final m in _modal)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF14B8A6)
                                        .withOpacity(0.12),
                                    child: const Icon(Icons.savings_outlined,
                                        color: Color(0xFF14B8A6), size: 20),
                                  ),
                                  title: Text(_rp.format(m.amount),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  subtitle: Text(
                                    'Dari ${m.source} · masuk ${m.labelTujuan}'
                                    '${m.note != null && m.note!.isNotEmpty ? ' · ${m.note}' : ''}'
                                    '\n${_waktu.format(m.createdAt.toLocal())}',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  isThreeLine: true,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

/// Apa yang membuat kedua angka di atas naik dan turun.
///
/// Saldo yang tidak bisa ditelusuri asalnya akan dicurigai, lalu
/// dihitung ulang tangan di buku lain — dan sejak itu ada dua
/// pembukuan.
class _Keterangan extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.softFillOf(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo Cash bertambah dari serah terima cash pickup dan dari '
              'top up modal yang diserahkan tunai, dan berkurang saat '
              'disetor ke bank atau dipakai membayar pengeluaran bersumber '
              'tunai.',
              style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 8),
          Text('Saldo Bank bertambah dari penjualan QRIS Dinamis, QRIS '
              'Statis, dan Transfer, dari setoran kasir yang sudah '
              'disetujui, dari setoran di layar ini, dan dari top up Modal '
              'Non Cash merchant — semuanya dicatat setiap jam 5 pagi WIB. '
              'Berkurang oleh pengeluaran bersumber dari Saldo Bank.',
              style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 8),
          // Kenapa bukan seketika. Tanpa kalimat ini, yang membuka layar
          // sore hari mengira penjualan siang tadi hilang.
          Text('Penjualan non-tunai tidak langsung masuk: uangnya ditahan '
              'penyedia pembayaran dan baru cair belakangan. Yang hari ini '
              'terlihat di Saldo Bank adalah yang sudah pada masuk.',
              style: TextStyle(fontSize: 12.5, color: muted)),
        ],
      ),
    );
  }
}

class _KartuTotal extends StatelessWidget {
  final int total;
  final NumberFormat rp;

  const _KartuTotal({required this.total, required this.rp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF0F766E)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Uang Perusahaan',
              style: TextStyle(color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 6),
          Text(rp.format(total),
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 6),
          Text('Tunai di tangan + uang di rekening',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.75), fontSize: 12)),
        ],
      ),
    );
  }
}

class _KartuSaldo extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String nilai;
  final String keterangan;
  final Color warna;

  const _KartuSaldo({
    required this.ikon,
    required this.judul,
    required this.nilai,
    required this.keterangan,
    required this.warna,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: warna),
          const SizedBox(height: 8),
          Text(judul,
              style: TextStyle(
                  fontSize: 12, color: KaataTheme.mutedOf(context))),
          const SizedBox(height: 2),
          Text(nilai,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(keterangan,
              style: TextStyle(
                  fontSize: 11, color: KaataTheme.mutedOf(context))),
        ],
      ),
    );
  }
}

class _BarisSetoran extends StatelessWidget {
  final CompanyDeposit setoran;
  final NumberFormat rp;
  final DateFormat waktu;

  const _BarisSetoran(
      {required this.setoran, required this.rp, required this.waktu});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: setoran.adaBukti
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(byteGambar(setoran.proofBase64!),
                    width: 44, height: 44, fit: BoxFit.cover),
              )
            : CircleAvatar(
                backgroundColor: const Color(0xFF0EA5E9).withOpacity(0.12),
                child: const Icon(Icons.account_balance_outlined,
                    color: Color(0xFF0EA5E9), size: 20),
              ),
        title: Text(rp.format(setoran.amount),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          [
            waktu.format(setoran.createdAt.toLocal()),
            if (setoran.createdBy != null) setoran.createdBy!,
            if (setoran.note != null && setoran.note!.isNotEmpty) setoran.note!,
          ].join(' · '),
          style: TextStyle(fontSize: 11.5, color: muted),
        ),
        isThreeLine: false,
      ),
    );
  }
}

class _DialogSetor extends StatefulWidget {
  final String restoId;
  final int saldoCash;
  final List<BankAccount> rekening;

  const _DialogSetor({
    required this.restoId,
    required this.saldoCash,
    required this.rekening,
  });

  @override
  State<_DialogSetor> createState() => _DialogSetorState();
}

class _DialogSetorState extends State<_DialogSetor> {
  final _formKey = GlobalKey<FormState>();
  final _nominal = TextEditingController();
  final _catatan = TextEditingController();
  final _repo = CompanyBalanceRepository();

  BankAccount? _tujuan;
  Uint8List? _bukti;
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _tujuan = widget.rekening.isEmpty ? null : widget.rekening.first;
  }

  @override
  void dispose() {
    _nominal.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _menyimpan = true);
    try {
      await _repo.setor(CompanyDeposit(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_nominal.text)!,
        bankAccountId: _tujuan?.id,
        note: _catatan.text.trim().isEmpty ? null : _catatan.text.trim(),
        proofBase64: _bukti == null ? null : base64Encode(_bukti!),
        createdBy: context.read<AuthProvider>().user?.email,
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: ${pesanGalat(e)}', isError: true);
      setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rp =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final muted = KaataTheme.mutedOf(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Setor ke Bank',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Memindahkan uang tunai perusahaan ke rekeningnya. '
                        'Saldo Cash berkurang, Saldo Bank bertambah.',
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KaataTheme.softFillOf(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                            'Saldo Cash: ${rp.format(widget.saldoCash)}',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nominal,
                        decoration:
                            InputDecoration(label: requiredLabel('Nominal')),
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsInputFormatter()],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        autofocus: true,
                        validator: (v) {
                          final n = parseRupiah(v ?? '');
                          if (n == null || n <= 0) {
                            return 'Wajib diisi, angka > 0';
                          }
                          // Menyetor lebih dari yang dipegang berarti
                          // salah hitung di suatu tempat, dan kalau
                          // dibiarkan saldonya minus — angka yang tidak
                          // berarti apa-apa.
                          if (n > widget.saldoCash) {
                            return 'Melebihi Saldo Cash '
                                '(maks ${rp.format(widget.saldoCash)})';
                          }
                          return null;
                        },
                      ),
                      if (widget.rekening.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _tujuan?.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Rekening Tujuan',
                            isDense: true,
                          ),
                          items: [
                            for (final r in widget.rekening)
                              DropdownMenuItem(
                                value: r.id,
                                child: Text(
                                  '${r.bankName} · ${r.accountNumber}'
                                  '${r.isPrimary ? '  (utama)' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            for (final r in widget.rekening) {
                              if (r.id == v) _tujuan = r;
                            }
                          }),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _catatan,
                        decoration: const InputDecoration(
                            labelText: 'Catatan (opsional)'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      Text('Bukti Setor (opsional)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: muted)),
                      const SizedBox(height: 8),
                      if (_bukti == null)
                        OutlinedButton.icon(
                          onPressed: () async {
                            final dipilih = await pickProofPhoto(context);
                            if (dipilih != null && mounted) {
                              setState(() => _bukti = dipilih);
                            }
                          },
                          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                          label: const Text('Ambil Bukti'),
                        )
                      else
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_bukti!,
                                  width: 58, height: 58, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () => setState(() => _bukti = null),
                              child: const Text('Ganti'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              DialogActions(
                confirmLabel: 'Setor',
                busy: _menyimpan,
                onConfirm: _simpan,
                onCancel: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormModal extends StatefulWidget {
  final String restoId;

  const _FormModal({required this.restoId});

  @override
  State<_FormModal> createState() => _FormModalState();
}


/// Formulir setoran modal.
///
/// Nominal, dari siapa, keterangan, bukti kalau ada — dan kantong
/// tujuannya. Modal masuk ke perusahaan, bukan ke penjualan hari ini:
/// ia menambah Saldo Cash atau Saldo Bank Perusahaan, dan tidak
/// menyentuh Saldo Cash maupun Saldo Non Cash merchant sama sekali.
class _FormModalState extends State<_FormModal> {
  final _repo = BalanceTopupRepository();
  final _formKey = GlobalKey<FormState>();
  final _nominal = TextEditingController();
  final _dari = TextEditingController();
  final _catatan = TextEditingController();
  String? _bukti;

  /// Mendarat di mana uangnya. Bawaannya rekening: setoran modal yang
  /// besar hampir selalu ditransfer, dan yang menyerahkannya tunai akan
  /// menyadarinya justru karena harus memilih.
  String _tujuan = 'bank';

  bool _menyimpan = false;

  @override
  void dispose() {
    for (final c in [_nominal, _dari, _catatan]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pilihBukti() async {
    final bytes = await pickProofPhoto(context);
    if (bytes == null || !mounted) return;
    setState(() => _bukti = base64Encode(bytes));
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _menyimpan = true);
    try {
      await _repo.add(
        restoId: widget.restoId,
        amount: parseRupiah(_nominal.text) ?? 0,
        source: _dari.text.trim(),
        destination: _tujuan,
        note: _catatan.text.trim(),
        proofBase64: _bukti,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      AppToast.show(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Top Up Saldo'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Uang masuk dari luar penjualan — setoran investor atau '
                'modal awal. Menambah Saldo Perusahaan di kantong yang '
                'dipilih, terpisah dari pendapatan penjualan.',
                style: TextStyle(
                    fontSize: 12, color: KaataTheme.mutedOf(context)),
              ),
              const SizedBox(height: 14),
              // Kantongnya disebut penyetornya. Uang yang ditransfer
              // dan uang yang diserahkan tunai mendarat di tempat yang
              // berbeda, dan menebaknya berarti salah satu dari dua
              // saldo selalu meleset.
              DropdownButtonFormField<String>(
                value: _tujuan,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Masuk ke',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'bank',
                      child: Text('Saldo Bank — masuk rekening')),
                  DropdownMenuItem(
                      value: 'cash',
                      child: Text('Saldo Cash — diserahkan tunai')),
                ],
                onChanged: (v) => setState(() => _tujuan = v ?? 'bank'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nominal,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: InputDecoration(
                  label: requiredLabel('Nominal'),
                  prefixText: 'Rp ',
                ),
                validator: (v) =>
                    (parseRupiah(v ?? '') ?? 0) > 0 ? null : 'Isi nominalnya',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dari,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  label: requiredLabel('Dari'),
                  hintText: 'Nama investor atau penyetor',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Sebutkan penyetornya' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _catatan,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                ),
              ),
              const SizedBox(height: 14),
              if (_bukti == null)
                OutlinedButton.icon(
                  onPressed: _pilihBukti,
                  icon: const Icon(Icons.attach_file, size: 17),
                  label: const Text('Lampirkan Bukti (opsional)'),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('Bukti terlampir')),
                    TextButton(
                      onPressed: () => setState(() => _bukti = null),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogActions(
          confirmLabel: 'Simpan',
          busy: _menyimpan,
          onConfirm: _simpan,
          onCancel: () => Navigator.pop(context, false),
        ),
      ],
    );
  }
}

/// Mencatat pengeluaran yang dibayar dari uang perusahaan.
///
/// Kantongnya dipilih lebih dulu, sebelum nominalnya: batas nominal
/// mengikuti kantongnya, dan kotak yang berubah aturannya sesudah diisi
/// memaksa orang mengetik ulang.
///
/// Akun biayanya diambil dari daftar GL Pengeluaran milik restonya —
/// daftar yang sama dengan yang dipakai pengeluaran petty cash, supaya
/// laporan per akun tidak terbelah menurut dari kantong mana uangnya
/// diambil.
class _DialogPengeluaran extends StatefulWidget {
  final String restoId;
  final List<ExpenseGlAccount> akunBiaya;
  final int saldoCash;
  final int saldoBank;

  const _DialogPengeluaran({
    required this.restoId,
    required this.akunBiaya,
    required this.saldoCash,
    required this.saldoBank,
  });

  @override
  State<_DialogPengeluaran> createState() => _DialogPengeluaranState();
}

class _DialogPengeluaranState extends State<_DialogPengeluaran> {
  final _formKey = GlobalKey<FormState>();
  final _nominal = TextEditingController();
  final _keterangan = TextEditingController();
  final _repo = ExpenseRepository();

  /// 'cash' atau 'bank'. Tidak ada 'petty' di sini: kas kecil kasir
  /// dibelanjakan dari layar Saldo & Pengeluaran.
  String _sumber = 'bank';
  String? _glCode;
  Uint8List? _nota;
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _glCode = widget.akunBiaya.isEmpty ? null : widget.akunBiaya.first.glCode;
  }

  @override
  void dispose() {
    _nominal.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  int get _tersedia => _sumber == 'cash' ? widget.saldoCash : widget.saldoBank;

  String get _namaSumber => _sumber == 'cash'
      ? 'Saldo Cash Perusahaan'
      : 'Saldo Bank Perusahaan';

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _menyimpan = true);
    try {
      await _repo.create(Expense(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_nominal.text)!,
        description: _keterangan.text.trim(),
        glCode: _glCode,
        receiptBase64: _nota == null ? null : base64Encode(_nota!),
        fundSource: _sumber,
        createdBy: context.read<AuthProvider>().user?.email ?? 'Finance',
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: ${pesanGalat(e)}', isError: true);
      setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rp =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final muted = KaataTheme.mutedOf(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Catat Pengeluaran Perusahaan',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Dipotong dari kantong yang dipilih, dan tercatat di '
                        'akun GL Pengeluaran yang disebut.',
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _sumber,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sumber Dana',
                          isDense: true,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'bank',
                            child: Text('Saldo Bank Perusahaan — '
                                '${rp.format(widget.saldoBank)}'),
                          ),
                          DropdownMenuItem(
                            value: 'cash',
                            child: Text('Saldo Cash Perusahaan — '
                                '${rp.format(widget.saldoCash)}'),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _sumber = v ?? 'bank';
                          // Nominalnya diperiksa ulang terhadap batas
                          // yang baru, bukan dibiarkan lolos dari
                          // pemeriksaan kantong sebelumnya.
                          _formKey.currentState?.validate();
                        }),
                      ),
                      const SizedBox(height: 12),
                      if (widget.akunBiaya.isEmpty)
                        const Text(
                          'Belum ada akun GL Pengeluaran. Tambahkan dulu di '
                          'Mapping GL Account.',
                          style: TextStyle(
                              fontSize: 12.5, color: Color(0xFFDC2626)),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _glCode,
                          isExpanded: true,
                          decoration: InputDecoration(
                            label: requiredLabel('Akun Pengeluaran'),
                            isDense: true,
                          ),
                          items: [
                            for (final a in widget.akunBiaya)
                              DropdownMenuItem(
                                value: a.glCode,
                                child: Text('${a.glCode} — ${a.glName}',
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() => _glCode = v),
                          validator: (v) =>
                              v == null ? 'Pilih akun pengeluarannya' : null,
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nominal,
                        decoration: InputDecoration(
                          label: requiredLabel('Jumlah'),
                          prefixText: 'Rp ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsInputFormatter()],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        validator: (v) {
                          final n = parseRupiah(v ?? '');
                          if (n == null || n <= 0) {
                            return 'Wajib diisi, angka > 0';
                          }
                          // Membelanjakan lebih dari yang dipegang
                          // membuat saldonya minus — angka yang tidak
                          // berarti apa-apa.
                          if (n > _tersedia) {
                            return 'Melebihi $_namaSumber '
                                '(maks ${rp.format(_tersedia)})';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _keterangan,
                        decoration:
                            InputDecoration(label: requiredLabel('Keterangan')),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Sebutkan pengeluarannya'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      Text('Nota (opsional)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: muted)),
                      const SizedBox(height: 8),
                      if (_nota == null)
                        OutlinedButton.icon(
                          onPressed: () async {
                            final dipilih = await pickProofPhoto(context);
                            if (dipilih != null && mounted) {
                              setState(() => _nota = dipilih);
                            }
                          },
                          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                          label: const Text('Ambil Foto Nota'),
                        )
                      else
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_nota!,
                                  width: 58, height: 58, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () => setState(() => _nota = null),
                              child: const Text('Ganti'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              DialogActions(
                confirmLabel: 'Simpan',
                busy: _menyimpan,
                onConfirm: _simpan,
                onCancel: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menyetel saldo awal sebuah kantong.
///
/// Yang diminta bukan tebakan melainkan satu kenyataan dari luar: berapa
/// isi rekening pada suatu tanggal menurut mutasi bank sungguhan, atau
/// berapa uang tunai yang benar-benar dihitung tangan hari itu.
///
/// Selisih terhadap yang tercatat ditulis sebagai penyesuaian bertanggal
/// itu. Pergerakan sesudahnya tidak disentuh — ia berjalan di atas saldo
/// awalnya.
class _DialogSaldoAwal extends StatefulWidget {
  final String restoId;

  const _DialogSaldoAwal({required this.restoId});

  @override
  State<_DialogSaldoAwal> createState() => _DialogSaldoAwalState();
}

class _DialogSaldoAwalState extends State<_DialogSaldoAwal> {
  final _formKey = GlobalKey<FormState>();
  final _nominal = TextEditingController();
  final _catatan = TextEditingController();
  final _repo = CompanyBalanceRepository();

  String _kantong = 'bank';
  DateTime _tanggal = DateTime.now();
  bool _menyimpan = false;

  @override
  void dispose() {
    _nominal.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggal() async {
    final dipilih = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Saldo per tanggal',
    );
    if (dipilih != null) setState(() => _tanggal = dipilih);
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _menyimpan = true);
    try {
      final selisih = await _repo.setelSaldoAwal(
        restoId: widget.restoId,
        kantong: _kantong,
        saldo: parseRupiah(_nominal.text)!,
        tanggal: _tanggal,
        catatan: _catatan.text.trim().isEmpty ? null : _catatan.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      final rp = NumberFormat.currency(
          locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
      showAppToast(
        context,
        selisih == 0
            ? 'Sudah cocok — tidak ada penyesuaian yang perlu ditulis.'
            : 'Penyesuaian ${rp.format(selisih.abs())} '
                '${selisih > 0 ? 'ditambahkan' : 'dikurangkan'}.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyetel: ${pesanGalat(e)}', isError: true);
      setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final tanggalFmt = DateFormat('d MMMM yyyy', 'id_ID');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Setel Saldo Awal',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Sebutkan isi kantong ini pada satu tanggal menurut '
                        'mutasi bank atau hitungan tangan. Selisihnya '
                        'terhadap catatan ditulis sebagai penyesuaian, dan '
                        'pergerakan sesudah tanggal itu tidak disentuh.',
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _kantong,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Kantong',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'bank',
                              child: Text('Saldo Bank Perusahaan')),
                          DropdownMenuItem(
                              value: 'cash',
                              child: Text('Saldo Cash Perusahaan')),
                        ],
                        onChanged: (v) => setState(() => _kantong = v ?? 'bank'),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _pilihTanggal,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Saldo per tanggal',
                            isDense: true,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(tanggalFmt.format(_tanggal))),
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nominal,
                        decoration: InputDecoration(
                          label: requiredLabel('Saldo Sebenarnya'),
                          prefixText: 'Rp ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsInputFormatter()],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        autofocus: true,
                        validator: (v) {
                          final n = parseRupiah(v ?? '');
                          if (n == null || n < 0) return 'Wajib diisi';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _catatan,
                        decoration: const InputDecoration(
                          labelText: 'Catatan (opsional)',
                          helperText: 'Misalnya: menurut mutasi BCA 31 Agustus',
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              DialogActions(
                confirmLabel: 'Setel',
                busy: _menyimpan,
                onConfirm: _simpan,
                onCancel: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
