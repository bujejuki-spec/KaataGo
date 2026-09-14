import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/absensi_repository.dart';
import '../models/absensi.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../utils/mesin_wajah.dart';
import '../utils/pesan_galat.dart';
import '../utils/resto_location.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';
import 'slip_gaji_screen.dart';

/// Absensi karyawan: wajah, titik GPS, dan waktunya.
///
/// Satu layar untuk semua peran. Yang membedakan bukan perannya
/// melainkan keadaannya — belum daftar wajah, belum absen masuk, sudah
/// masuk tapi belum pulang, atau sudah selesai hari itu.
class AbsensiScreen extends StatefulWidget {
  const AbsensiScreen({super.key});

  @override
  State<AbsensiScreen> createState() => _AbsensiScreenState();
}

class _AbsensiScreenState extends State<AbsensiScreen> {
  final _repo = AbsensiRepository();

  static final _jam = DateFormat('HH:mm', 'id_ID');
  static final _tanggalPanjang = DateFormat('EEEE, d MMMM yyyy', 'id_ID');

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  bool _wajahTerdaftar = false;
  bool _modelSiap = false;
  BarisAbsensi? _hariIni;
  List<BarisAbsensi> _riwayat = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  String? get _restoId => context.read<AuthProvider>().restoId;
  String? get _email => context.read<AuthProvider>().user?.email;

  Future<void> _muat() async {
    final restoId = _restoId;
    final email = _email;
    if (restoId == null || email == null) {
      setState(() {
        _memuat = false;
        _galat = 'Akunmu belum terhubung ke merchant mana pun.';
      });
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final kini = DateTime.now().toWib();
      final hasil = await Future.wait([
        _repo.wajahTerdaftar(restoId),
        _repo.hariIni(restoId, email),
        _repo.rentang(
          restoId,
          mulai: DateTime(kini.year, kini.month - 1, kini.day),
          akhir: DateTime(kini.year, kini.month, kini.day),
          email: email,
        ),
        MesinWajah.siap(),
      ]);
      if (!mounted) return;
      setState(() {
        _wajahTerdaftar = hasil[0] as bool;
        _hariIni = hasil[1] as BarisAbsensi?;
        _riwayat = hasil[2] as List<BarisAbsensi>;
        _modelSiap = hasil[3] as bool;
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

  /// Memotret wajah lalu mengubahnya jadi sidik.
  ///
  /// Kamera depan, dan tidak boleh dari galeri: gambar yang boleh
  /// dipilih dari galeri adalah gambar yang bisa dipilih dari foto
  /// teman.
  Future<HasilWajah?> _pindaiWajah() async {
    try {
      final foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1080,
        imageQuality: 90,
      );
      if (foto == null) return null;
      return await MesinWajah.pindai(foto.path);
    } on WajahGagal catch (e) {
      if (mounted) showAppToast(context, e.pesan, isError: true);
      return null;
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'Gagal membaca wajah: ${pesanGalat(e)}',
            isError: true);
      }
      return null;
    }
  }

  Future<void> _daftarWajah() async {
    final restoId = _restoId;
    final email = _email;
    if (restoId == null || email == null) return;

    final setuju = await _konfirmasiDaftar();
    if (setuju != true || !mounted) return;

    setState(() => _sibuk = true);
    try {
      final wajah = await _pindaiWajah();
      if (wajah == null) return;

      final url = await _repo.unggah(
        restoId: restoId,
        email: email,
        bytes: wajah.potongan,
        jenis: 'wajah',
      );
      await _repo.daftarWajah(
        restoId: restoId,
        sidik: wajah.sidik,
        model: MesinWajah.namaModel,
        fotoUrl: url,
        setujuVersi: MesinWajah.versiPersetujuan,
      );
      if (!mounted) return;
      showAppToast(context, 'Wajahmu terdaftar. Sekarang bisa absen.');
      await _muat();
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<bool?> _konfirmasiDaftar() => showDialog<bool>(
        context: context,
        builder: (c) => const _DialogPersetujuanWajah(),
      );

  Future<void> _absen({required bool pulang}) async {
    final restoId = _restoId;
    final email = _email;
    if (restoId == null || email == null) return;

    setState(() => _sibuk = true);
    try {
      // Lokasinya diambil lebih dulu, sebelum kamera.
      //
      // GPS butuh beberapa detik mengunci, dan memintanya sesudah orang
      // selesai berfoto berarti menahannya lagi di depan layar yang
      // tidak menjelaskan sedang menunggu apa.
      final posisi = await currentPosition();
      if (!mounted) return;

      final wajah = await _pindaiWajah();
      if (wajah == null) return;

      String? url;
      // Fotonya boleh gagal diunggah tanpa membatalkan absennya.
      //
      // Yang menentukan sah tidaknya absen adalah sidik wajah dan
      // titik GPS, dan keduanya sudah ada. Menolak absen orang yang
      // sudah berdiri di tempatnya hanya karena jaringan warung sedang
      // lambat mengunggah gambar adalah hukuman untuk hal yang salah.
      try {
        url = await _repo.unggah(
          restoId: restoId,
          email: email,
          bytes: wajah.potongan,
          jenis: pulang ? 'pulang' : 'masuk',
        );
      } catch (_) {}

      final hasil = await _repo.absen(
        restoId: restoId,
        sidik: wajah.sidik,
        lat: posisi.latitude,
        lng: posisi.longitude,
        fotoUrl: url,
        pulang: pulang,
      );

      if (!mounted) return;
      showAppToast(
        context,
        '${pulang ? 'Absen pulang' : 'Absen masuk'} tercatat '
        '${_jam.format(hasil.waktu.toWib())} — ${hasil.jarakM} m dari merchant.',
      );
      await _muat();
    } on LocationFailure catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _ajukanTidakMasuk() async {
    final restoId = _restoId;
    final email = _email;
    if (restoId == null || email == null) return;

    final hasil = await showDialog<_PengajuanTidakMasuk>(
      context: context,
      builder: (_) => const _DialogTidakMasuk(),
    );
    if (hasil == null || !mounted) return;

    setState(() => _sibuk = true);
    try {
      String? bukti;
      if (hasil.bukti != null) {
        bukti = await _repo.unggah(
          restoId: restoId,
          email: email,
          bytes: hasil.bukti!,
          jenis: 'bukti',
        );
      }
      await _repo.ajukanTidakMasuk(
        restoId: restoId,
        tanggal: hasil.tanggal,
        status: hasil.status,
        alasan: hasil.alasan,
        buktiUrl: bukti,
      );
      if (!mounted) return;
      showAppToast(context, 'Pengajuan ${hasil.status.label.toLowerCase()} tercatat.');
      await _muat();
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Absensi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Slip Gaji',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SlipGajiScreen()),
            ),
          ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    if (_galat != null) _Peringatan(pesan: _galat!),
                    if (kIsWeb)
                      const _Peringatan(
                        pesan: 'Absen hanya bisa lewat aplikasi KaataGo di HP — '
                            'yang diperlukan kamera depan dan GPS yang kamu bawa.',
                      )
                    else if (!_modelSiap) ...[
                      // Tidak menyuruh memperbarui aplikasi.
                      //
                      // Modelnya tidak ada di versi mana pun — ia belum
                      // dipasang KaataGo sama sekali. Menyuruh orang
                      // memperbarui berarti menyuruhnya mengerjakan
                      // sesuatu yang tidak akan menolong, lalu menyimpulkan
                      // sendiri bahwa aplikasinya rusak saat ternyata
                      // pesannya tetap sama.
                      const _Peringatan(
                        pesan: 'Absen wajah belum diaktifkan KaataGo untuk '
                            'aplikasi ini. Mengajukan izin, sakit, atau cuti '
                            'tetap bisa dilakukan di bawah.',
                      ),
                      // Izin dan sakit memang tidak butuh wajah maupun
                      // GPS — yang sedang sakit di rumah tidak bisa
                      // berdiri di depan merchant. Menyembunyikannya di
                      // balik pemeriksaan model berarti orang yang sakit
                      // hari ini tidak punya cara menyatakannya sama
                      // sekali.
                      _KartuTidakMasukSaja(
                        baris: _hariIni,
                        sibuk: _sibuk,
                        tanggal: _tanggalPanjang,
                        onTidakMasuk: _ajukanTidakMasuk,
                      ),
                    ] else if (!_wajahTerdaftar)
                      _KartuDaftarWajah(sibuk: _sibuk, onDaftar: _daftarWajah)
                    else
                      _KartuHariIni(
                        baris: _hariIni,
                        sibuk: _sibuk,
                        jam: _jam,
                        tanggal: _tanggalPanjang,
                        onMasuk: () => _absen(pulang: false),
                        onPulang: () => _absen(pulang: true),
                        onTidakMasuk: _ajukanTidakMasuk,
                      ),
                    const SizedBox(height: 18),
                    Text('Riwayat 30 hari',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: KaataTheme.mutedOf(context))),
                    const SizedBox(height: 8),
                    if (_riwayat.isEmpty)
                      Text('Belum ada absensi.',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: KaataTheme.mutedOf(context)))
                    else
                      for (final a in _riwayat) _BarisRiwayat(baris: a, jam: _jam),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Peringatan extends StatelessWidget {
  final String pesan;

  const _Peringatan({required this.pesan});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.tintOf(context, Colors.orange),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: KaataTheme.onTintOf(context, Colors.orange)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(pesan,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: KaataTheme.onTintOf(context, Colors.orange))),
          ),
        ],
      ),
    );
  }
}

class _KartuDaftarWajah extends StatelessWidget {
  final bool sibuk;
  final VoidCallback onDaftar;

  const _KartuDaftarWajah({required this.sibuk, required this.onDaftar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KaataTheme.brand, KaataTheme.brandDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.face_retouching_natural,
              color: Colors.white, size: 34),
          const SizedBox(height: 12),
          const Text('Daftarkan wajahmu dulu',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Sekali saja. Setelah itu absenmu dicocokkan dengan wajah ini, '
            'jadi tidak bisa dititipkan ke siapa pun.',
            style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Colors.white.withOpacity(0.9)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: KaataTheme.brandDark),
              icon: sibuk
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.camera_alt_outlined, size: 18),
              label: Text(sibuk ? 'Memproses...' : 'Daftarkan Wajah'),
              onPressed: sibuk ? null : onDaftar,
            ),
          ),
        ],
      ),
    );
  }
}

class _KartuHariIni extends StatelessWidget {
  final BarisAbsensi? baris;
  final bool sibuk;
  final DateFormat jam;
  final DateFormat tanggal;
  final VoidCallback onMasuk;
  final VoidCallback onPulang;
  final VoidCallback onTidakMasuk;

  const _KartuHariIni({
    required this.baris,
    required this.sibuk,
    required this.jam,
    required this.tanggal,
    required this.onMasuk,
    required this.onPulang,
    required this.onTidakMasuk,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final kini = DateTime.now().toWib();
    final sudahMasuk = baris?.sudahMasuk == true;
    final sudahPulang = baris?.sudahPulang == true;
    final tidakMasuk = baris != null && baris!.status != StatusAbsen.hadir;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tanggal.format(kini),
              style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Cap(
                  label: 'Masuk',
                  nilai: baris?.masukAt == null
                      ? '—'
                      : jam.format(baris!.masukAt!.toWib()),
                  aktif: sudahMasuk,
                ),
              ),
              Expanded(
                child: _Cap(
                  label: 'Pulang',
                  nilai: baris?.pulangAt == null
                      ? '—'
                      : jam.format(baris!.pulangAt!.toWib()),
                  aktif: sudahPulang,
                ),
              ),
            ],
          ),
          if (tidakMasuk) ...[
            const SizedBox(height: 12),
            Text(
              'Hari ini tercatat ${baris!.status.label.toLowerCase()}'
              '${baris!.alasan == null ? '' : ' — ${baris!.alasan}'}.',
              style: TextStyle(fontSize: 12.5, color: muted),
            ),
          ],
          const SizedBox(height: 16),
          if (!sudahMasuk && !tidakMasuk)
            _Tombol(
              label: 'Absen Masuk',
              ikon: Icons.login,
              sibuk: sibuk,
              onTap: onMasuk,
            )
          else if (sudahMasuk && !sudahPulang)
            _Tombol(
              label: 'Absen Pulang',
              ikon: Icons.logout,
              sibuk: sibuk,
              onTap: onPulang,
            )
          else if (sudahPulang)
            Row(
              children: [
                const Icon(Icons.check_circle, size: 18, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    baris?.lamaTeks == null
                        ? 'Absensi hari ini sudah lengkap.'
                        : 'Selesai — hari ini ${baris!.lamaTeks} di tempat '
                            'kerja.',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ),
              ],
            ),
          if (!sudahMasuk) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_busy_outlined, size: 17),
                label: const Text('Tidak Masuk Hari Ini'),
                onPressed: sibuk ? null : onTidakMasuk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Saat absen wajahnya belum bisa dipakai, tapi menyatakan tidak masuk
/// masih bisa.
class _KartuTidakMasukSaja extends StatelessWidget {
  final BarisAbsensi? baris;
  final bool sibuk;
  final DateFormat tanggal;
  final VoidCallback onTidakMasuk;

  const _KartuTidakMasukSaja({
    required this.baris,
    required this.sibuk,
    required this.tanggal,
    required this.onTidakMasuk,
  });

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final sudahDiajukan = baris != null && baris!.status != StatusAbsen.hadir;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        border: Border.all(color: KaataTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tanggal.format(DateTime.now().toWib()),
              style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 10),
          if (sudahDiajukan)
            Text(
              'Hari ini tercatat ${baris!.status.label.toLowerCase()}'
              '${baris!.alasan == null ? '' : ' — ${baris!.alasan}'}.',
              style: const TextStyle(fontSize: 14),
            )
          else
            Text(
              'Belum ada catatan untuk hari ini.',
              style: TextStyle(fontSize: 14, color: muted),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              icon: const Icon(Icons.event_busy_outlined, size: 18),
              label: Text(sudahDiajukan
                  ? 'Ubah Pengajuan'
                  : 'Ajukan Izin / Sakit / Cuti'),
              onPressed: sibuk ? null : onTidakMasuk,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cap extends StatelessWidget {
  final String label;
  final String nilai;
  final bool aktif;

  const _Cap({required this.label, required this.nilai, required this.aktif});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context))),
        const SizedBox(height: 2),
        Text(nilai,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: aktif ? KaataTheme.brandOf(context) : null,
            )),
      ],
    );
  }
}

class _Tombol extends StatelessWidget {
  final String label;
  final IconData ikon;
  final bool sibuk;
  final VoidCallback onTap;

  const _Tombol({
    required this.label,
    required this.ikon,
    required this.sibuk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton.icon(
        icon: sibuk
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(ikon, size: 18),
        label: Text(sibuk ? 'Memproses...' : label),
        onPressed: sibuk ? null : onTap,
      ),
    );
  }
}

class _BarisRiwayat extends StatelessWidget {
  final BarisAbsensi baris;
  final DateFormat jam;

  static final _tgl = DateFormat('EEE, d MMM', 'id_ID');

  const _BarisRiwayat({required this.baris, required this.jam});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    final warna = switch (baris.status) {
      StatusAbsen.hadir => const Color(0xFF10B981),
      StatusAbsen.izin => const Color(0xFF0EA5E9),
      StatusAbsen.sakit => const Color(0xFFF59E0B),
      StatusAbsen.cuti => const Color(0xFF8B5CF6),
      StatusAbsen.alpa => const Color(0xFFEF4444),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 4, height: 34,
              decoration: BoxDecoration(
                  color: warna, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tgl.format(baris.tanggal),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  baris.status == StatusAbsen.hadir
                      ? '${baris.masukAt == null ? '—' : jam.format(baris.masukAt!.toWib())}'
                          ' → ${baris.pulangAt == null ? 'belum pulang' : jam.format(baris.pulangAt!.toWib())}'
                          '${baris.lamaTeks == null ? '' : '  ·  ${baris.lamaTeks}'}'
                      : (baris.alasan?.isNotEmpty == true
                          ? baris.alasan!
                          : baris.status.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ),
          if (baris.potongGaji)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('potong gaji',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB91C1C))),
            )
          else
            Text(baris.status.label,
                style: TextStyle(fontSize: 11.5, color: muted)),
        ],
      ),
    );
  }
}

/// Yang dipilih orang di dialog "tidak masuk".
class _PengajuanTidakMasuk {
  final DateTime tanggal;
  final StatusAbsen status;
  final String alasan;
  final Uint8List? bukti;

  const _PengajuanTidakMasuk({
    required this.tanggal,
    required this.status,
    required this.alasan,
    this.bukti,
  });
}

/// Mengajukan tidak masuk, berikut buktinya kalau ada.
///
/// Buktinya opsional dan memang harus begitu. Surat dokter tidak selalu
/// ada di tangan pada hari orangnya sakit, dan menuntutnya sebagai
/// syarat berarti absennya tercatat alpa hanya karena kliniknya baru
/// buka besok. Yang memutuskan potong gaji tetap atasannya, dan dia
/// yang melihat ada tidaknya bukti itu.
class _DialogTidakMasuk extends StatefulWidget {
  const _DialogTidakMasuk();

  @override
  State<_DialogTidakMasuk> createState() => _DialogTidakMasukState();
}

class _DialogTidakMasukState extends State<_DialogTidakMasuk> {
  static final _tgl = DateFormat('d MMM yyyy', 'id_ID');

  StatusAbsen _status = StatusAbsen.izin;
  DateTime _tanggal = DateTime.now().toWib();
  final _alasan = TextEditingController();
  Uint8List? _bukti;

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggal() async {
    final kini = DateTime.now().toWib();
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      // Tiga puluh hari ke belakang: mengajukan izin untuk bulan lalu
      // berarti membetulkan rekap gaji yang mungkin sudah dibayar.
      firstDate: DateTime(kini.year, kini.month, kini.day)
          .subtract(const Duration(days: 30)),
      lastDate: DateTime(kini.year, kini.month, kini.day),
      helpText: 'Tidak masuk tanggal',
    );
    if (hasil != null && mounted) setState(() => _tanggal = hasil);
  }

  Future<void> _ambilBukti() async {
    final foto = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 80,
    );
    if (foto == null) return;
    final bytes = await foto.readAsBytes();
    if (mounted) setState(() => _bukti = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return AlertDialog(
      title: const Text('Tidak Masuk'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final s in [
                  StatusAbsen.izin,
                  StatusAbsen.sakit,
                  StatusAbsen.cuti,
                ])
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(_tgl.format(_tanggal)),
              onPressed: _pilihTanggal,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _alasan,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Alasan',
                hintText: 'Contoh: demam sejak semalam',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            if (_bukti == null)
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file, size: 16),
                label: const Text('Unggah Bukti (opsional)'),
                onPressed: _ambilBukti,
              )
            else
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Bukti terlampir',
                        style: TextStyle(fontSize: 12.5, color: muted)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _bukti = null),
                    child: const Text('Hapus'),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        DialogActions(
          confirmLabel: 'Ajukan',
          onConfirm: _alasan.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _PengajuanTidakMasuk(
                      tanggal: _tanggal,
                      status: _status,
                      alasan: _alasan.text.trim(),
                      bukti: _bukti,
                    ),
                  ),
        ),
      ],
    );
  }
}

/// Syarat pemakaian data wajah, berikut centang yang wajib dicentang.
///
/// ── Kenapa tidak cukup satu tombol "Daftarkan" ───────────────────────
///
/// Wajah termasuk data pribadi yang bersifat spesifik menurut UU
/// 27/2022. Persetujuan yang sah bukan sekadar orangnya menekan tombol:
/// dia harus tahu apa yang diambil, untuk apa dipakai, siapa yang bisa
/// melihatnya, berapa lama disimpan, dan bagaimana mencabutnya.
///
/// Karena itu tombolnya mati sampai centangnya dicentang. Bukan untuk
/// menyulitkan — melainkan supaya "setuju" berarti seseorang benar-benar
/// memilihnya, bukan melewatinya.
///
/// Versi teks yang disetujui ikut tercatat di basis data. Kalau suatu
/// hari syaratnya berubah, yang pernah menyetujui teks lama tetap
/// tercatat menyetujui teks lama — tanpa versinya, catatan persetujuan
/// tidak membuktikan apa pun karena tidak ada yang tahu dia menyetujui
/// apa.
class _DialogPersetujuanWajah extends StatefulWidget {
  const _DialogPersetujuanWajah();

  @override
  State<_DialogPersetujuanWajah> createState() =>
      _DialogPersetujuanWajahState();
}

class _DialogPersetujuanWajahState extends State<_DialogPersetujuanWajah> {
  bool _setuju = false;

  static const _syarat = <(String, String)>[
    (
      'Yang diambil',
      'Satu foto wajahmu. Dari foto itu dihitung deret angka — sidik '
          'wajah — yang dipakai mencocokkan absenmu nanti. Fotonya sendiri '
          'ikut disimpan sebagai bukti kalau suatu hari ada sengketa soal '
          'kehadiran atau gaji.',
    ),
    (
      'Untuk apa dipakai',
      'Hanya untuk absensi dan perhitungan gaji di merchant ini. Tidak '
          'dipakai untuk iklan, tidak dijual, dan tidak dibagikan ke '
          'pihak lain.',
    ),
    (
      'Fotonya diproses di HP-mu',
      'Pencocokan wajahnya berjalan di HP ini, bukan dikirim ke server '
          'luar. Yang tersimpan di penyimpanan merchant cuma foto dan '
          'sidik angkanya.',
    ),
    (
      'Siapa yang bisa melihat',
      'Owner, Admin, dan Finance merchant ini. Rekan kerjamu tidak bisa, '
          'dan foto absensi tidak bisa dibuka lewat tautan oleh siapa pun '
          'yang tidak berhak.',
    ),
    (
      'Berapa lama disimpan',
      'Selama kamu masih tercatat sebagai karyawan merchant ini, '
          'ditambah masa simpan catatan gaji sesuai aturan yang berlaku.',
    ),
    (
      'Mencabutnya',
      'Kamu bisa meminta wajahmu dihapus kapan saja ke Owner atau Admin. '
          'Sesudah dihapus, absenmu dicatat dengan cara lain yang '
          'disepakati merchant.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);

    return AlertDialog(
      title: const Text('Daftarkan wajahmu'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sebelum wajahmu didaftarkan, baca dulu bagaimana datanya '
                'dipakai.',
                style: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
              ),
              const SizedBox(height: 14),
              for (final (judul, isi) in _syarat) ...[
                Text(judul,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(isi,
                    style:
                        TextStyle(fontSize: 12, height: 1.45, color: muted)),
                const SizedBox(height: 12),
              ],
              Text(
                'Pendaftarannya cuma sekali. Kalau perlu didaftar ulang, '
                'Owner atau Admin yang membukanya — supaya absenmu tidak '
                'bisa dipindahkan ke wajah orang lain diam-diam.',
                style: TextStyle(fontSize: 12, height: 1.45, color: muted),
              ),
              const SizedBox(height: 6),
              // Seluruh barisnya bisa ditekan, bukan cuma kotak kecilnya.
              // Sasaran sentuh sebesar 18 piksel di HP adalah alasan orang
              // menekan tiga kali lalu mengira aplikasinya rusak.
              InkWell(
                onTap: () => setState(() => _setuju = !_setuju),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _setuju,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) =>
                            setState(() => _setuju = v ?? false),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 9),
                          child: Text(
                            'Saya sudah membaca dan setuju wajah saya '
                            'dipakai untuk absensi di merchant ini.',
                            style: TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        DialogActions(
          confirmLabel: 'Daftarkan',
          cancelLabel: 'Nanti',
          // Mati sampai dicentang. Persetujuan yang bisa dilewati tanpa
          // sengaja bukan persetujuan.
          onConfirm: _setuju ? () => Navigator.pop(context, true) : null,
          onCancel: () => Navigator.pop(context, false),
        ),
      ],
    );
  }
}
