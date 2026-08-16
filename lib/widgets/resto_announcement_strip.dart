import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/announcement_repository.dart';
import '../models/announcement.dart';
import '../theme.dart';

/// Pengumuman resto untuk pelanggan, di atas daftar menunya.
///
/// Pelanggan tidak punya kotak masuk — sebagian besar bahkan tidak
/// punya akun. Padahal justru merekalah yang dituju saat admin resto
/// mengumumkan promo atau perubahan jam buka. Jadi kabarnya dibawa ke
/// tempat yang pasti mereka lewati: halaman menu resto itu sendiri.
///
/// Hanya pengumuman milik resto yang sedang dibuka. Yang dari Super
/// Admin — pemberitahuan versi aplikasi — sengaja tidak ikut: itu
/// urusan orang yang mengelola aplikasinya, bukan orang yang sedang
/// memilih makan siang.
class RestoAnnouncementStrip extends StatefulWidget {
  final String restoId;

  const RestoAnnouncementStrip({super.key, required this.restoId});

  @override
  State<RestoAnnouncementStrip> createState() => _RestoAnnouncementStripState();
}

class _RestoAnnouncementStripState extends State<RestoAnnouncementStrip> {
  static const _dismissedKey = 'resto_announcements_dismissed';

  List<Announcement> _items = [];
  Set<String> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RestoAnnouncementStrip old) {
    super.didUpdateWidget(old);
    if (old.restoId != widget.restoId) _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getStringList(_dismissedKey)?.toSet() ?? {};
      final items = await AnnouncementRepository().generalForResto(widget.restoId);
      if (!mounted) return;
      setState(() {
        _dismissed = dismissed;
        _items = items;
      });
    } catch (_) {
      // Luring, atau tabelnya belum dimigrasi. Halaman menunya tetap
      // harus jalan tanpa pengumuman.
    }
  }

  /// Ditutup per perangkat, bukan per orang.
  ///
  /// Pelanggan tamu tidak punya identitas yang bisa dipakai menyimpan
  /// "sudah dibaca" di server. Menyimpannya di HP-nya sendiri sudah
  /// cukup: yang ingin dihindari cuma pengumuman yang sama menghadang
  /// tiap kali dia membuka menunya.
  Future<void> _dismiss(Announcement item) async {
    setState(() => _dismissed = {..._dismissed, item.id});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedKey, _dismissed.toList());
  }

  void _open(Announcement item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(item.title, style: const TextStyle(fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.hasImage) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(item.imageBase64!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(item.body, style: const TextStyle(fontSize: 14, height: 1.45)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _items.where((i) => !_dismissed.contains(i.id)).take(2).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final item in visible)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Material(
              color: KaataTheme.brand.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _open(item),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_outlined,
                          size: 19, color: KaataTheme.brand),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              item.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Sembunyikan',
                        onPressed: () => _dismiss(item),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
