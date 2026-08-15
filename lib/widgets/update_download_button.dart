import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/apk_updater.dart';
import 'app_toast.dart';

/// Tombol unduh versi terbaru di dalam pengumuman kotak masuk.
///
/// Mengunduh langsung di sini, bukan melempar ke browser. Yang dilempar
/// ke browser jarang selesai: orangnya berpindah aplikasi, menunggu di
/// sana, lalu harus mencari sendiri berkasnya di folder unduhan — dan
/// pembaruan yang tidak terpasang sama saja dengan pembaruan yang tidak
/// pernah dirilis.
///
/// Browser tetap disediakan sebagai jalan keluar kalau unduhannya gagal.
/// Cara lama yang merepotkan masih jauh lebih baik daripada buntu.
class UpdateDownloadButton extends StatefulWidget {
  final String url;

  const UpdateDownloadButton({super.key, required this.url});

  @override
  State<UpdateDownloadButton> createState() => _UpdateDownloadButtonState();
}

class _UpdateDownloadButtonState extends State<UpdateDownloadButton> {
  ApkUpdater? _updater;
  double? _progress;
  bool _busy = false;

  @override
  void dispose() {
    _updater?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _progress = 0;
    });

    final updater = ApkUpdater(
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    _updater = updater;

    final error = await updater.downloadAndInstall(widget.url);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      _updater = null;
    });
    if (error != null) showAppToast(context, error, isError: true);
  }

  void _cancel() {
    _updater?.cancel();
    setState(() {
      _busy = false;
      _progress = null;
      _updater = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final percent = _progress == null ? null : (_progress! * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(
              !_busy
                  ? 'Unduh Versi Terbaru'
                  : percent == null
                      ? 'Mengunduh…'
                      : 'Mengunduh $percent%',
            ),
            onPressed: _busy ? null : _start,
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          // Batangnya menyusul tombolnya, bukan menggantikannya: angka
          // persen di tombol menjawab "sudah sejauh mana", batang ini
          // menjawab "masih jalan atau menggantung".
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _progress, minHeight: 5),
          ),
          const SizedBox(height: 4),
          Text(
            'Berkasnya sekitar 80 MB. Layar pemasang terbuka sendiri '
            'setelah selesai.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          TextButton(onPressed: _cancel, child: const Text('Batalkan')),
        ] else
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(widget.url),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Unduh lewat browser',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }
}
