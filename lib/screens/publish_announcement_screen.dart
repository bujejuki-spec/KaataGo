import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../db/announcement_repository.dart';
import '../providers/auth_provider.dart';
import '../widgets/responsive.dart';
import '../widgets/app_toast.dart';

/// Menerbitkan pengumuman ke kotak masuk semua orang sekaligus.
///
/// Untuk saat ini isinya pemberitahuan versi baru: setelah APK diunggah,
/// pengumuman ini yang membuat penggunanya tahu ada yang perlu diunduh.
/// Terbatas untuk Super Admin — pesan yang muncul di HP semua orang
/// bukan sesuatu yang boleh dikirim siapa saja.
class PublishAnnouncementScreen extends StatefulWidget {
  const PublishAnnouncementScreen({super.key});

  @override
  State<PublishAnnouncementScreen> createState() => _PublishAnnouncementScreenState();
}

class _PublishAnnouncementScreenState extends State<PublishAnnouncementScreen> {
  static const _downloadUrl =
      'https://github.com/bujejuki-spec/KaataGo-LandingPage/releases/latest/download/KaataGo.apk';

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();
  final _urlCtrl = TextEditingController(text: _downloadUrl);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Versi yang terpasang di HP ini dipakai sebagai isian awal: yang
    // menerbitkan pengumuman biasanya baru saja memasang APK barunya.
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _versionCtrl.text = info.version;
        _titleCtrl.text = 'KaataGo ${info.version} sudah tersedia';
        _bodyCtrl.text = 'Versi baru KaataGo sudah bisa diunduh. '
            'Perbarui aplikasimu untuk mendapat perbaikan dan fitur terbaru.';
      });
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _versionCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    final email = context.read<AuthProvider>().user?.email ?? 'Super Admin';
    final toast = AppToast.of(context);
    final navigator = Navigator.of(context);

    setState(() => _saving = true);
    try {
      await AnnouncementRepository().publish(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        version: _versionCtrl.text.trim().isEmpty ? null : _versionCtrl.text.trim(),
        downloadUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
        createdBy: email,
      );
      toast.show('Pengumuman terkirim ke semua kotak masuk.');
      navigator.pop();
    } catch (e) {
      toast.show('Gagal mengirim: $e', isError: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kirim Pengumuman')),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.25)),
                ),
                child: const Text(
                  'Pengumuman ini muncul di kotak masuk semua pengguna yang '
                  'login, dan sebagai banner di layar awal untuk yang memesan '
                  'tanpa akun.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF075985)),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Judul'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _bodyCtrl,
                decoration: const InputDecoration(labelText: 'Isi Pesan'),
                maxLines: 4,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _versionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Versi (mis. 1.32.0)',
                  helperText: 'Dipakai untuk tahu apakah aplikasi pengguna sudah tertinggal',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(labelText: 'Link Unduh'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.campaign_outlined),
                  label: const Text('Kirim ke Semua'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _saving ? null : _publish,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
