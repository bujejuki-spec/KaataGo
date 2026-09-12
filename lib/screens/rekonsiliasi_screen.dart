import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/bank_account_repository.dart';
import '../utils/akses_menu.dart';
import '../db/settlement_repository.dart';
import '../models/bank_account.dart';
import '../models/settlement.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../utils/pesan_galat.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

/// Mencocokkan mutasi rekening dengan yang tercatat di aplikasi.
///
/// Dua daftar sisa, dan keduanya menanyakan hal yang berbeda:
///
///   mutasi tanpa pasangan   uang masuk yang tidak ada catatannya
///   catatan tanpa mutasi    uang yang dinyatakan terkirim tapi tidak
///                           pernah sampai
///
/// Yang kedua itu yang mahal, dan yang selama ini tidak pernah terlihat.
/// Membandingkan total saja takkan menemukan keduanya: dua kekeliruan
/// berlawanan arah bisa menghasilkan total yang kebetulan cocok.
class RekonsiliasiScreen extends StatefulWidget {
  const RekonsiliasiScreen({super.key});

  @override
  State<RekonsiliasiScreen> createState() => _RekonsiliasiScreenState();
}

class _RekonsiliasiScreenState extends State<RekonsiliasiScreen> {
  final _repo = SettlementRepository();

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _tgl = DateFormat('d MMM yyyy', 'id_ID');

  List<BankAccount> _rekening = const [];
  BankAccount? _dipilih;

  List<BankMutation> _mutasi = const [];
  List<BelumCocok> _setoran = const [];
  List<BelumCocok> _pembayaran = const [];

  bool _memuat = true;
  bool _sibuk = false;

  String? get _restoId => context.read<AuthProvider>().restoId;
  String get _saya => context.read<AuthProvider>().user?.email ?? 'Finance';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muatAwal());
  }

  Future<void> _muatAwal() async {
    final restoId = _restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    try {
      final rek = await BankAccountRepository().untukResto(restoId);
      if (!mounted) return;
      setState(() {
        _rekening = rek;
        _dipilih = rek.isEmpty
            ? null
            : rek.firstWhere((r) => r.isPrimary, orElse: () => rek.first);
      });
      await _muat();
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat: ${pesanGalat(e)}', isError: true);
    }
  }

  Future<void> _muat() async {
    final restoId = _restoId;
    final rek = _dipilih;
    if (restoId == null || rek == null) {
      setState(() => _memuat = false);
      return;
    }
    try {
      final hasil = await Future.wait([
        _repo.mutasi(rek.id),
        _repo.setoranBelumCocok(restoId),
        _repo.pembayaranBelumCocok(restoId),
      ]);
      if (!mounted) return;
      setState(() {
        _mutasi = hasil[0] as List<BankMutation>;
        _setoran = hasil[1] as List<BelumCocok>;
        _pembayaran = hasil[2] as List<BelumCocok>;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat: ${pesanGalat(e)}', isError: true);
    }
  }

  List<BankMutation> get _belumCocok =>
      [for (final m in _mutasi) if (!m.sudahCocok) m];

  Future<void> _tambahMutasi() async {
    final rek = _dipilih;
    if (rek == null) return;
    final hasil = await showDialog<BankMutation>(
      context: context,
      builder: (_) => _DialogMutasi(bankAccountId: rek.id, oleh: _saya),
    );
    if (hasil == null || !mounted) return;

    setState(() => _sibuk = true);
    try {
      await _repo.tambahMutasi(hasil);
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: ${pesanGalat(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  /// Menautkan sebuah mutasi ke hal yang menjelaskannya.
  Future<void> _cocokkan(BankMutation m) async {
    final pilihan = await showModalBottomSheet<({String jenis, String? id})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SheetCocokkan(
        mutasi: m,
        setoran: _setoran,
        pembayaran: _pembayaran,
        rp: _rp,
      ),
    );
    if (pilihan == null || !mounted) return;

    setState(() => _sibuk = true);
    try {
      await _repo.cocokkan(m.id,
          jenis: pilihan.jenis, sasaranId: pilihan.id, oleh: _saya);
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal mencocokkan: ${pesanGalat(e)}',
          isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _lepasCocok(BankMutation m) async {
    setState(() => _sibuk = true);
    try {
      await _repo.cocokkan(m.id, jenis: null);
      await _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return berdasarkanAkses(context, 'Rekonsiliasi Bank', Scaffold(
      appBar: AppBar(title: const Text('Rekonsiliasi Bank')),
      floatingActionButton: _dipilih == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _sibuk ? null : _tambahMutasi,
              icon: const Icon(Icons.add),
              label: const Text('Catat Mutasi'),
            ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _rekening.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Belum ada rekening perusahaan.\nTambahkan satu di '
                      'Rekening Perusahaan sebelum mencocokkan mutasi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: KaataTheme.mutedOf(context)),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                      children: [
                        if (_rekening.length > 1) _pilihRekening(),
                        _ringkasan(),
                        const SizedBox(height: 18),
                        _judul('Mutasi Belum Dicocokkan', _belumCocok.length,
                            'Uang yang masuk rekening tapi belum ada '
                            'catatannya di aplikasi.'),
                        if (_belumCocok.isEmpty) _kosong('Semua mutasi sudah dicocokkan.'),
                        for (final m in _belumCocok) _kartuMutasi(m),
                        const SizedBox(height: 18),
                        _judul('Setoran Belum Terbukti Sampai', _setoran.length,
                            'Uang yang keluar laci dan belum terlihat di '
                            'mutasi rekening. Inilah yang paling mahal '
                            'kalau dibiarkan.'),
                        if (_setoran.isEmpty)
                          _kosong('Semua setoran sudah terbukti sampai.'),
                        for (final s in _setoran) _kartuBelum(s, setoran: true),
                        const SizedBox(height: 18),
                        _judul('Pembayaran Belum Terbukti Sampai',
                            _pembayaran.length,
                            'QRIS Statis dan transfer yang diakui lunas tapi '
                            'belum terlihat di rekening. 30 hari terakhir.'),
                        if (_pembayaran.isEmpty)
                          _kosong('Semua pembayaran sudah terbukti sampai.'),
                        for (final s in _pembayaran)
                          _kartuBelum(s, setoran: false),
                        const SizedBox(height: 18),
                        _judul('Mutasi Sudah Dicocokkan',
                            _mutasi.length - _belumCocok.length, null),
                        for (final m in _mutasi)
                          if (m.sudahCocok) _kartuMutasi(m),
                      ],
                    ),
                  ),
                ),
    ));
  }

  Widget _pilihRekening() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          value: _dipilih?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Rekening',
            isDense: true,
          ),
          items: [
            for (final r in _rekening)
              DropdownMenuItem(
                value: r.id,
                child: Text('${r.tampilan} · ${r.accountNumber}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            for (final r in _rekening) {
              if (r.id == v) setState(() => _dipilih = r);
            }
            _muat();
          },
        ),
      );

  Widget _ringkasan() {
    final masuk = _mutasi
        .where((m) => m.masuk)
        .fold<int>(0, (sum, m) => sum + m.amount);
    final belum = _belumCocok.fold<int>(0, (sum, m) => sum + m.amount);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total masuk tercatat',
                    style: TextStyle(
                        fontSize: 11.5, color: KaataTheme.mutedOf(context))),
                Text(_rp.format(masuk),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Belum dicocokkan',
                    style: TextStyle(
                        fontSize: 11.5, color: KaataTheme.mutedOf(context))),
                Text(_rp.format(belum),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: belum == 0
                            ? const Color(0xFF10B981)
                            : Colors.orange)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _judul(String teks, int jumlah, String? catatan) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(teks,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Text('$jumlah',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KaataTheme.mutedOf(context))),
              ],
            ),
            if (catatan != null) ...[
              const SizedBox(height: 2),
              Text(catatan,
                  style: TextStyle(
                      fontSize: 11.5, color: KaataTheme.mutedOf(context))),
            ],
          ],
        ),
      );

  Widget _kosong(String teks) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(teks,
            style: TextStyle(
                fontSize: 12.5, color: KaataTheme.mutedOf(context))),
      );

  Widget _kartuMutasi(BankMutation m) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(
          color: KaataTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: m.sudahCocok
                ? KaataTheme.borderOf(context)
                : Colors.orange.withOpacity(0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(m.masuk ? Icons.south_west : Icons.north_east,
                    size: 16,
                    color: m.masuk ? const Color(0xFF10B981) : Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_rp.format(m.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text(_tgl.format(m.mutatedOn),
                    style: TextStyle(
                        fontSize: 12, color: KaataTheme.mutedOf(context))),
              ],
            ),
            if (m.description != null && m.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(m.description!,
                    style: TextStyle(
                        fontSize: 12, color: KaataTheme.mutedOf(context))),
              ),
            if (m.reference != null && m.reference!.isNotEmpty)
              Text('Acuan ${m.reference}',
                  style: TextStyle(
                      fontSize: 11, color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 6),
            if (m.sudahCocok)
              Row(
                children: [
                  const Icon(Icons.link, size: 15, color: Color(0xFF10B981)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      BankMutation.labelJenis[m.matchedKind] ?? m.matchedKind!,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _sibuk ? null : () => _lepasCocok(m),
                    child: const Text('Lepas'),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _sibuk ? null : () => _cocokkan(m),
                  icon: const Icon(Icons.link, size: 17),
                  label: const Text('Cocokkan'),
                ),
              ),
          ],
        ),
      );

  Widget _kartuBelum(BelumCocok s, {required bool setoran}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        decoration: BoxDecoration(
          color: KaataTheme.tintOf(context, Colors.orange),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_rp.format(s.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(
                    [
                      setoran
                          ? (s.jenis == 'pickup' ? 'Cash pickup' : 'Setoran')
                          : (s.jenis == 'qris_static'
                              ? 'QRIS Statis'
                              : 'Transfer'),
                      _tgl.format(s.waktu.toWib()),
                      if (s.oleh != null) s.oleh!,
                    ].join(' · '),
                    style: TextStyle(
                        fontSize: 11.5,
                        color: KaataTheme.onTintOf(context, Colors.brown)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Memilih apa yang dijelaskan sebuah mutasi.
class _SheetCocokkan extends StatelessWidget {
  final BankMutation mutasi;
  final List<BelumCocok> setoran;
  final List<BelumCocok> pembayaran;
  final NumberFormat rp;

  const _SheetCocokkan({
    required this.mutasi,
    required this.setoran,
    required this.pembayaran,
    required this.rp,
  });

  @override
  Widget build(BuildContext context) {
    // Yang nominalnya sama persis ditaruh di atas. Hampir semua
    // pencocokan adalah nominal yang identik, dan menyuruh orang mencari
    // angka itu di daftar panjang adalah pekerjaan yang bisa dikerjakan
    // layarnya sendiri.
    List<BelumCocok> urut(List<BelumCocok> sumber) {
      final sama = [for (final s in sumber) if (s.amount == mutasi.amount) s];
      final beda = [for (final s in sumber) if (s.amount != mutasi.amount) s];
      return [...sama, ...beda];
    }

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Cocokkan ${rp.format(mutasi.amount)}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline),
              title: const Text('Bukan dari penjualan'),
              subtitle: const Text('Modal, pinjaman, atau uang dari luar usaha'),
              onTap: () =>
                  Navigator.pop(context, (jenis: 'other', id: null)),
            ),
            const Divider(),
            if (setoran.isNotEmpty) ...[
              const Text('Setoran & Pickup',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final s in urut(setoran))
                _baris(context, s, 'deposit',
                    s.jenis == 'pickup' ? 'Cash pickup' : 'Setoran'),
              const Divider(),
            ],
            if (pembayaran.isNotEmpty) ...[
              const Text('Pembayaran Pelanggan',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final s in urut(pembayaran))
                _baris(context, s, 'order',
                    s.jenis == 'qris_static' ? 'QRIS Statis' : 'Transfer'),
            ],
            if (setoran.isEmpty && pembayaran.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Tidak ada catatan yang menunggu dicocokkan. Kalau uang '
                  'ini memang bukan dari penjualan, pilih yang di atas.',
                  style: TextStyle(color: KaataTheme.mutedOf(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _baris(
      BuildContext context, BelumCocok s, String jenis, String label) {
    final pas = s.amount == mutasi.amount;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(pas ? Icons.check_circle_outline : Icons.circle_outlined,
          color: pas ? const Color(0xFF10B981) : KaataTheme.mutedOf(context)),
      title: Text(rp.format(s.amount),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$label · ${DateFormat('d MMM yyyy', 'id_ID').format(s.waktu.toWib())}'),
      trailing: pas
          ? const Text('nominal pas',
              style: TextStyle(fontSize: 11, color: Color(0xFF10B981)))
          : null,
      onTap: () => Navigator.pop(context, (jenis: jenis, id: s.id)),
    );
  }
}

class _DialogMutasi extends StatefulWidget {
  final String bankAccountId;
  final String oleh;

  const _DialogMutasi({required this.bankAccountId, required this.oleh});

  @override
  State<_DialogMutasi> createState() => _DialogMutasiState();
}

class _DialogMutasiState extends State<_DialogMutasi> {
  final _formKey = GlobalKey<FormState>();
  final _jumlah = TextEditingController();
  final _keterangan = TextEditingController();
  final _acuan = TextEditingController();

  DateTime _tanggal = DateTime.now().toWib();
  String _arah = 'in';

  @override
  void dispose() {
    _jumlah.dispose();
    _keterangan.dispose();
    _acuan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat Mutasi'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'in', label: Text('Masuk')),
                  ButtonSegment(value: 'out', label: Text('Keluar')),
                ],
                selected: {_arah},
                onSelectionChanged: (v) => setState(() => _arah = v.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _jumlah,
                decoration: InputDecoration(label: requiredLabel('Nominal')),
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                autofocus: true,
                validator: (v) {
                  final n = parseRupiah(v ?? '');
                  return (n == null || n <= 0) ? 'Wajib diisi, angka > 0' : null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final pilih = await showDatePicker(
                    context: context,
                    initialDate: _tanggal,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().toWib(),
                  );
                  if (pilih != null) setState(() => _tanggal = pilih);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Tanggal Mutasi'),
                  child: Text(
                      DateFormat('d MMM yyyy', 'id_ID').format(_tanggal)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keterangan,
                decoration: const InputDecoration(
                  labelText: 'Keterangan',
                  hintText: 'Seperti tertulis di mutasi banknya',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _acuan,
                decoration: const InputDecoration(
                  labelText: 'Nomor Acuan (opsional)',
                  helperText: 'Mencegah satu mutasi dicatat dua kali',
                ),
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
              BankMutation(
                id: '',
                bankAccountId: widget.bankAccountId,
                mutatedOn: _tanggal,
                amount: parseRupiah(_jumlah.text)!,
                direction: _arah,
                description: _keterangan.text.trim().isEmpty
                    ? null
                    : _keterangan.text.trim(),
                reference:
                    _acuan.text.trim().isEmpty ? null : _acuan.text.trim(),
                createdBy: widget.oleh,
              ),
            );
          },
        ),
      ],
      actionsAlignment: MainAxisAlignment.center,
    );
  }
}
