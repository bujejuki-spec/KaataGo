import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/bank_account_repository.dart';
import '../models/bank_account.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/daftar_bank.dart';
import '../utils/field_rules.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

/// Rekening perusahaan yang dipakai resto ini.
///
/// Satu resto boleh punya beberapa — misalnya satu untuk setoran tunai,
/// satu lagi untuk transfer pelanggan — dan satu rekening boleh dipakai
/// beberapa cabang. Yang utama dipakai kalau tidak disebut yang mana:
/// tujuan setoran tunai, dan yang ditampilkan di layar Transfer.
class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  final _repo = BankAccountRepository();

  List<BankAccount> _rekening = const [];
  bool _memuat = true;
  bool _sibuk = false;

  String? get _restoId => context.read<AuthProvider>().restoId;

  /// Kasir melihat, Owner dan Finance mengubah.
  ///
  /// Mengganti nomor rekening berarti mengganti ke mana uang laci pergi,
  /// dan itu bukan keputusan yang dibuat sambil melayani antrean.
  /// Servernya menegakkan hal yang sama.
  bool get _bolehUbah {
    final auth = context.read<AuthProvider>();
    return auth.isSuperAdmin || auth.isOwner || auth.isFinance;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  Future<void> _muat() async {
    final restoId = _restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    try {
      final hasil = await _repo.untukResto(restoId);
      if (!mounted) return;
      setState(() {
        _rekening = hasil;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat rekening: ${pesanGalat(e)}',
          isError: true);
    }
  }

  Future<void> _tambahAtauUbah({BankAccount? ada}) async {
    final hasil = await showDialog<BankAccount>(
      context: context,
      builder: (_) => _DialogRekening(ada: ada),
    );
    if (hasil == null || !mounted) return;

    final restoId = _restoId;
    if (restoId == null) return;

    setState(() => _sibuk = true);
    try {
      if (ada == null) {
        await _repo.tambah(
          restoId: restoId,
          rekening: hasil,
          // Yang pertama otomatis jadi utama. Resto yang punya satu
          // rekening tidak perlu diminta menunjuk mana yang utama.
          jadikanUtama: _rekening.isEmpty,
        );
      } else {
        await _repo.ubah(hasil);
      }
      await _muat();
      if (!mounted) return;
      showAppToast(context, ada == null ? 'Rekening ditambahkan.' : 'Tersimpan.');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: ${pesanGalat(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _jadikanUtama(BankAccount r) async {
    final restoId = _restoId;
    if (restoId == null) return;
    setState(() => _sibuk = true);
    try {
      await _repo.jadikanUtama(restoId, r.id);
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal mengubah: ${pesanGalat(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _lepas(BankAccount r) async {
    if (r.isPrimary) {
      showAppToast(
        context,
        'Rekening utama tidak bisa dilepas. Tunjuk rekening lain sebagai '
        'utama dulu.',
        isError: true,
      );
      return;
    }

    final yakin = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Lepas Rekening?'),
        content: Text(
          '${r.ringkas}\n\n'
          'Rekeningnya tidak dihapus — cuma tidak lagi dipakai merchant '
          'ini. Cabang lain yang memakainya tidak terpengaruh.',
        ),
        actions: [
          DialogActions(
            confirmLabel: 'Lepas',
            destructive: true,
            onCancel: () => Navigator.pop(d, false),
            onConfirm: () => Navigator.pop(d, true),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
    if (yakin != true || !mounted) return;

    final restoId = _restoId;
    if (restoId == null) return;
    setState(() => _sibuk = true);
    try {
      await _repo.lepas(restoId, r.id);
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal melepas: ${pesanGalat(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rekening Perusahaan')),
      floatingActionButton: _bolehUbah
          ? FloatingActionButton.extended(
              onPressed: _sibuk ? null : () => _tambahAtauUbah(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Rekening'),
            )
          : null,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                  children: [
                    Text(
                      'Rekening utama dipakai sebagai tujuan setoran tunai '
                      'dan ditampilkan ke pelanggan yang membayar lewat '
                      'transfer.',
                      style: TextStyle(
                          fontSize: 12.5, color: KaataTheme.mutedOf(context)),
                    ),
                    const SizedBox(height: 14),
                    if (_rekening.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            'Belum ada rekening.\nTambahkan satu supaya '
                            'setoran tunai punya tujuan.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: KaataTheme.mutedOf(context)),
                          ),
                        ),
                      ),
                    for (final r in _rekening) _kartu(r),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _kartu(BankAccount r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: r.isPrimary
              ? KaataTheme.brand
              : KaataTheme.borderOf(context),
          width: r.isPrimary ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.tampilan,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
              if (r.isPrimary)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KaataTheme.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('UTAMA',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: KaataTheme.brand)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(r.bankName,
              style:
                  TextStyle(fontSize: 12.5, color: KaataTheme.mutedOf(context))),
          Text(
            r.accountNumber,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          Text('a.n. ${r.accountHolder}',
              style:
                  TextStyle(fontSize: 12.5, color: KaataTheme.mutedOf(context))),
          if (_bolehUbah) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                if (!r.isPrimary)
                  TextButton.icon(
                    onPressed: _sibuk ? null : () => _jadikanUtama(r),
                    icon: const Icon(Icons.star_outline, size: 17),
                    label: const Text('Jadikan Utama'),
                  ),
                TextButton.icon(
                  onPressed: _sibuk ? null : () => _tambahAtauUbah(ada: r),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('Ubah'),
                ),
                if (!r.isPrimary)
                  TextButton(
                    onPressed: _sibuk ? null : () => _lepas(r),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Lepas'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DialogRekening extends StatefulWidget {
  final BankAccount? ada;

  const _DialogRekening({this.ada});

  @override
  State<_DialogRekening> createState() => _DialogRekeningState();
}

class _DialogRekeningState extends State<_DialogRekening> {
  final _formKey = GlobalKey<FormState>();
  late final List<String> _pilihanBank;
  String? _bank;
  late final TextEditingController _nomor;
  late final TextEditingController _atasNama;
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    final a = widget.ada;
    _pilihanBank = daftarBankUntuk(a?.bankName);
    _bank = bankTerpilih(a?.bankName, _pilihanBank);
    _nomor = TextEditingController(text: a?.accountNumber ?? '');
    _atasNama = TextEditingController(text: a?.accountHolder ?? '');
    _label = TextEditingController(text: a?.label ?? '');
  }

  @override
  void dispose() {
    _nomor.dispose();
    _atasNama.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.ada == null ? 'Rekening Baru' : 'Ubah Rekening'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dipilih, bukan diketik. Keunikan rekening ditentukan
              // pasangan nama bank dan nomornya, dan selama namanya
              // diketik tangan, "BCA" dan "Bank BCA" adalah dua bank
              // berbeda bagi basis data — rekening yang sama berakhir
              // sebagai dua baris dengan mutasi tertaut sebagian.
              DropdownButtonFormField<String>(
                value: _bank,
                isExpanded: true,
                decoration: InputDecoration(label: requiredLabel('Bank')),
                items: [
                  for (final b in _pilihanBank)
                    DropdownMenuItem(value: b, child: Text(b)),
                ],
                onChanged: (v) => setState(() => _bank = v),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Pilih banknya dulu' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nomor,
                decoration:
                    InputDecoration(label: requiredLabel('Nomor Rekening')),
                keyboardType: TextInputType.number,
                inputFormatters: accountNumberFormatters,
                validator: validateAccountNumber,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _atasNama,
                decoration: InputDecoration(label: requiredLabel('Atas Nama')),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    validateName(v, label: 'Nama pemilik rekening'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Sebutan (opsional)',
                  helperText: 'Misal: BCA Operasional',
                ),
                inputFormatters: nameFormatters,
              ),
            ],
          ),
        ),
      ),
      actions: [
        DialogActions(
          confirmLabel: 'Simpan',
          onCancel: () => Navigator.pop(context),
          onConfirm: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              BankAccount(
                id: widget.ada?.id ?? '',
                bankName: _bank!,
                accountNumber: _nomor.text.trim(),
                accountHolder: _atasNama.text.trim(),
                label: _label.text.trim(),
                isPrimary: widget.ada?.isPrimary ?? false,
              ),
            );
          },
        ),
      ],
      actionsAlignment: MainAxisAlignment.center,
    );
  }
}
