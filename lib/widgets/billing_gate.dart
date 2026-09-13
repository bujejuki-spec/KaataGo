import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/billing_repository.dart';
import '../db/paket_langganan_repository.dart';
import '../models/billing.dart';
import '../models/paket_langganan.dart';
import '../providers/auth_provider.dart';
import '../screens/billing_screen.dart';
import '../screens/pilih_paket_screen.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/responsive.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMMM yyyy', 'id_ID');

/// Membungkus layar utama tiap peran resto.
///
/// Tiga keadaan, dan urutannya menentukan apa yang dilihat orangnya:
///
///   terkunci   → seluruh layar diganti halaman tagihan
///   H-3        → pita pengingat di atas layarnya, isinya tetap dipakai
///   selain itu → tidak ada apa-apa
///
/// Yang tidak dilakukan di sini: menegakkan penguncian. Layar yang
/// terkunci hanyalah layar — penegakannya ada di kebijakan RLS, dan
/// gerbang ini cuma menerjemahkannya jadi sesuatu yang bisa dibaca
/// orang. Kalau keduanya sampai berbeda pendapat, yang menang database,
/// dan gejalanya adalah tombol yang bisa ditekan tapi tidak menyimpan
/// apa pun.
class BillingGate extends StatefulWidget {
  final Widget child;

  const BillingGate({super.key, required this.child});

  @override
  State<BillingGate> createState() => _BillingGateState();
}

class _BillingGateState extends State<BillingGate> {
  final _repo = BillingRepository();
  final _paket = PaketLanggananRepository();
  BillingState _state = BillingState.tenang;

  /// Keadaan paketnya, terpisah dari keadaan tagihan bulanannya.
  ///
  /// Dua hal yang berbeda, dan menggabungkannya jadi satu angka membuat
  /// merchant yang masa percobaannya habis menerima kalimat tentang
  /// tagihan yang belum pernah diterbitkan.
  KeadaanLangganan _langganan = const KeadaanLangganan();
  bool _sudahMemeriksa = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _periksa());
  }

  Future<void> _periksa() async {
    final auth = context.read<AuthProvider>();
    final restoId = auth.restoId;

    // Super Admin tidak pernah terkunci — dialah yang membuka kuncinya.
    if (restoId == null || auth.isSuperAdmin) {
      if (mounted) setState(() => _sudahMemeriksa = true);
      return;
    }

    try {
      final hasil = await Future.wait([
        _repo.stateOf(restoId),
        _paket.keadaan(restoId),
      ]);
      if (!mounted) return;
      setState(() {
        _state = hasil[0] as BillingState;
        _langganan = hasil[1] as KeadaanLangganan;
        _sudahMemeriksa = true;
      });
    } catch (_) {
      // Luring, atau gangguan sesaat. Membiarkan aplikasinya jalan lebih
      // baik daripada mengunci resto yang tagihannya mungkin lunas:
      // penguncian yang sebenarnya tetap dijaga database, jadi tidak ada
      // yang lolos karena kelonggaran di sini.
      if (mounted) setState(() => _sudahMemeriksa = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_sudahMemeriksa) return widget.child;

    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return widget.child;

    // Paket lebih dulu daripada tagihan bulanan.
    //
    // Merchant yang masa percobaannya habis belum punya tagihan sama
    // sekali — yang dia butuhkan adalah memilih paket, bukan membayar
    // tagihan yang tidak ada. Menaruh gerbang tagihan di depan akan
    // menyodorkan halaman kosong yang tidak bisa diapa-apakan.
    if (_langganan.terkunciPaket) {
      return _LayarPilihPaket(
        langganan: _langganan,
        onSelesai: _periksa,
      );
    }

    if (_state.locked) {
      return _LayarTerkunci(state: _state, restoId: restoId);
    }

    Future<void> bukaPaket() async {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PilihPaketScreen()));
      _periksa();
    }

    // Dua hari sebelum percobaan habis, dan seterusnya sampai habis.
    //
    // Diketuk membuka layar pemilihan paket langsung, bukan sekadar
    // memberi tahu: pemberitahuan yang tidak membawa ke tempat
    // menyelesaikannya cuma menambah satu langkah mencari sendiri.
    if (_langganan.mendekatiHabis) {
      return Column(
        children: [
          _PitaPercobaan(langganan: _langganan, onBuka: bukaPaket),
          Expanded(child: widget.child),
        ],
      );
    }

    if (!_state.perluDiingatkan) return widget.child;

    return Column(
      children: [
        _PitaPengingat(
          state: _state,
          onBuka: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => BillingScreen(restoId: restoId),
            ));
            _periksa();
          },
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _PitaPengingat extends StatelessWidget {
  final BillingState state;
  final VoidCallback onBuka;

  const _PitaPengingat({required this.state, required this.onBuka});

  @override
  Widget build(BuildContext context) {
    final sisa = state.daysLeft ?? 0;
    final mendesak = sisa < 0;

    final pesan = state.menungguVerifikasi
        ? 'Bukti bayar sedang diperiksa KaataGo.'
        : mendesak
            ? 'Tagihan lewat ${-sisa} hari. Merchant terkunci kalau belum '
                'dibayar.'
            : sisa == 0
                ? 'Tagihan jatuh tempo hari ini.'
                : 'Tagihan jatuh tempo $sisa hari lagi.';

    final warna = state.menungguVerifikasi
        ? Colors.blue
        : mendesak
            ? Colors.red
            : Colors.orange;

    return Material(
      color: warna.withOpacity(0.12),
      child: InkWell(
        onTap: onBuka,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
            child: Row(
              children: [
                Icon(
                  state.menungguVerifikasi
                      ? Icons.hourglass_top_outlined
                      : Icons.info_outline,
                  size: 17,
                  color: warna,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pesan,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: warna)),
                      if (state.amount != null)
                        Text(
                          '${_rupiah.format(state.amount)}'
                          '${state.dueDate == null ? '' : ' · '
                              'jatuh tempo ${_tanggal.format(state.dueDate!)}'}',
                          style: TextStyle(
                              fontSize: 11,
                              color: KaataTheme.mutedOf(context)),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: warna),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Halaman yang menggantikan seluruh isi aplikasi saat resto terkunci.
///
/// Dua tombol saja, dan keduanya harus ada: membuka tagihan supaya bisa
/// membayar, dan keluar akun supaya perangkat yang dipinjam tidak
/// tersangkut di layar ini.
class _LayarTerkunci extends StatelessWidget {
  final BillingState state;
  final String restoId;

  const _LayarTerkunci({required this.state, required this.restoId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      body: SafeArea(
        child: ResponsiveCenter(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 44, color: Colors.red),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Aplikasi Terkunci Sementara',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tagihan langganan KaataGo belum lunas. Merchant ini bisa '
                  'dipakai lagi begitu pembayarannya diterima.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: KaataTheme.mutedOf(context)),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KaataTheme.surfaceOf(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: KaataTheme.borderOf(context)),
                  ),
                  child: Column(
                    children: [
                      if (state.amount != null)
                        Text(_rupiah.format(state.amount),
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                      if (state.dueDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Jatuh tempo ${_tanggal.format(state.dueDate!)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: KaataTheme.mutedOf(context)),
                        ),
                      ],
                      if (state.invoiceId != null) ...[
                        const SizedBox(height: 2),
                        Text(state.invoiceId!,
                            style: TextStyle(
                                fontSize: 11,
                                color: KaataTheme.mutedOf(context))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BillingScreen(restoId: restoId),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Lihat & Bayar Tagihan'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () async {
                    if (!await confirmLogout(context)) return;
                    if (!context.mounted) return;
                    await context.read<AuthProvider>().signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.logout, size: 17),
                  label: const Text('Keluar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pita pengingat masa percobaan, dua hari terakhir.
///
/// Warnanya merah pada hari terakhir, oranye sebelum itu. Satu warna
/// untuk kedua keadaan membuat hari terakhir terbaca sama mendesaknya
/// dengan dua hari lagi — dan yang membacanya menunda lagi.
class _PitaPercobaan extends StatelessWidget {
  final KeadaanLangganan langganan;
  final VoidCallback onBuka;

  const _PitaPercobaan({required this.langganan, required this.onBuka});

  @override
  Widget build(BuildContext context) {
    final sisa = langganan.sisaHari ?? 0;
    final mendesak = sisa <= 0;
    final warna = mendesak ? Colors.red : Colors.orange;

    return Material(
      color: warna.withOpacity(0.12),
      child: InkWell(
        onTap: onBuka,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
            child: Row(
              children: [
                Icon(Icons.hourglass_bottom, size: 17, color: warna.shade800),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    langganan.sedangDiperiksa
                        ? 'Pembayaran langgananmu sedang diperiksa KaataGo.'
                        : mendesak
                            ? 'Masa percobaan berakhir hari ini. Pilih paket '
                                'sekarang.'
                            : 'Masa percobaan tinggal $sisa hari. Pilih paket '
                                'langgananmu.',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: warna.shade900),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Pilih',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: warna.shade900)),
                Icon(Icons.chevron_right, size: 18, color: warna.shade800),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seluruh layar diganti saat masa percobaan habis dan belum
/// berlangganan.
///
/// Bukan pita di atas layar yang masih bisa dipakai: yang habis masa
/// percobaannya memang sudah tidak boleh memakai aplikasinya, dan pita
/// yang bisa diabaikan akan diabaikan sampai kasirnya menemukan
/// sendiri bahwa pesanan tidak bisa disimpan.
class _LayarPilihPaket extends StatelessWidget {
  final KeadaanLangganan langganan;
  final VoidCallback onSelesai;

  const _LayarPilihPaket({required this.langganan, required this.onSelesai});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final diperiksa = langganan.sedangDiperiksa;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      body: SafeArea(
        child: ResponsiveCenter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  diperiksa ? Icons.hourglass_top : Icons.lock_clock,
                  size: 56,
                  color: diperiksa ? Colors.orange : Colors.red,
                ),
                const SizedBox(height: 18),
                Text(
                  diperiksa
                      ? 'Pembayaranmu sedang diperiksa'
                      : 'Masa percobaan sudah berakhir',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  diperiksa
                      ? 'Paling lama 1×24 jam. Begitu KaataGo memastikan '
                          'pembayarannya masuk, aplikasinya bisa dipakai '
                          'kembali.'
                      : 'Pilih paket langgananmu untuk melanjutkan. Seluruh '
                          'data merchantmu tetap utuh dan langsung bisa '
                          'dipakai lagi setelah berlangganan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: muted),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    icon: Icon(
                        diperiksa ? Icons.refresh : Icons.workspace_premium,
                        size: 18),
                    label: Text(diperiksa
                        ? 'Periksa Status'
                        : 'Pilih Paket Langganan'),
                    onPressed: () async {
                      if (diperiksa) {
                        onSelesai();
                        return;
                      }
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PilihPaketScreen()));
                      onSelesai();
                    },
                  ),
                ),
                if (diperiksa) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PilihPaketScreen())),
                    child: const Text('Lihat pengajuanku'),
                  ),
                ],
                const SizedBox(height: 6),
                TextButton.icon(
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Keluar'),
                  onPressed: () async {
                    if (!await confirmLogout(context)) return;
                    if (!context.mounted) return;
                    await context.read<AuthProvider>().signOut();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
