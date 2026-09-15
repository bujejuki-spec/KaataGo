import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/setelan_platform_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/pesan_galat.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';

/// KaataGo Admin menyetel tautan situs yang dibuka dari Tentang KaataGo.
///
/// Tautannya disimpan di basis data supaya bisa diganti tanpa merilis
/// APK — dan yang paling diuntungkan justru HP yang belum memperbarui,
/// karena merekalah yang akan terus membuka alamat lama selamanya kalau
/// tautannya tertulis mati di dalam aplikasi.
class TautanSitusScreen extends StatefulWidget {
  const TautanSitusScreen({super.key});

  @override
  State<TautanSitusScreen> createState() => _TautanSitusScreenState();
}

class _TautanSitusScreenState extends State<TautanSitusScreen> {
  final _repo = SetelanPlatformRepository();
  final _tautan = TextEditingController();

  bool _memuat = true;
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _tautan.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    final t = await _repo.tautanSitus();
    if (!mounted) return;
    setState(() {
      _tautan.text = t;
      _memuat = false;
    });
  }

  bool get _sah => SetelanPlatformRepository.tautanSah(_tautan.text.trim());

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);
    try {
      await _repo.simpanTautanSitus(
        _tautan.text,
        oleh: context.read<AuthProvider>().user?.email,
      );
      if (!mounted) return;
      showAppToast(context, 'Tautan situs disimpan.');
    } catch (e) {
      if (mounted) showAppToast(context, pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Tautan Situs KaataGo')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Dibuka dari tombol "Situs KaataGo" di layar Tentang '
                    'KaataGo — termasuk dari halaman login, oleh orang yang '
                    'belum punya akun. Perubahan berlaku di semua HP tanpa '
                    'perlu memperbarui aplikasi.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: muted),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _tautan,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Tautan',
                      hintText: 'https://…',
                      border: const OutlineInputBorder(),
                      // Ditolak sebelum menyimpan, dengan kalimat yang
                      // bisa dibaca — basis datanya juga menolak, tapi
                      // penolakan dari sana datang sebagai galat.
                      errorText: _tautan.text.trim().isEmpty || _sah
                          ? null
                          : 'Harus diawali https:// dan tanpa spasi.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 17),
                          label: const Text('Coba Buka'),
                          // Dicoba dulu sebelum disimpan. Tautan yang
                          // salah ketik satu huruf baru ketahuan dari
                          // calon merchant yang mendarat di halaman 404.
                          onPressed: _sah
                              ? () => launchUrl(Uri.parse(_tautan.text.trim()),
                                  mode: LaunchMode.externalApplication)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _sah && !_menyimpan ? _simpan : null,
                          child: _menyimpan
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Simpan'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
