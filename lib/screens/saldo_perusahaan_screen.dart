import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
  List<BankAccount> _rekening = const [];
  bool _memuat = true;
  String? _galat;

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
        appBar: AppBar(title: const Text('Saldo Perusahaan')),
        floatingActionButton: !bolehUbahDiSini(context) || _memuat
            ? null
            : FloatingActionButton.extended(
                onPressed: _setor,
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Setor ke Bank'),
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
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
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
                                  keterangan: 'Uang di rekening merchant',
                                  warna: const Color(0xFF0EA5E9),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _Keterangan(),
                          const SizedBox(height: 20),
                          const Text('Setoran ke Bank',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          if (_setoran.isEmpty)
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
          Text('Saldo Cash bertambah dari serah terima cash pickup, dan '
              'berkurang saat disetor ke bank atau dipakai membayar '
              'pengeluaran bersumber tunai.',
              style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 8),
          Text('Saldo Bank bertambah dari penjualan QRIS Dinamis, QRIS '
              'Statis, dan Transfer, dari setoran tunai kasir yang sudah '
              'disetujui, dan dari setoran di layar ini. Berkurang oleh '
              'pengeluaran bersumber bank.',
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
