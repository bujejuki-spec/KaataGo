import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement.dart';

class AnnouncementRepository {
  final _client = Supabase.instance.client;

  /// Inbox seseorang: seluruh pengumuman yang belum dia hapus.
  ///
  /// Penghapusan dicatat per orang, bukan dengan membuang pengumumannya —
  /// satu orang membersihkan inbox-nya tidak boleh menghilangkan
  /// pengumuman itu dari orang lain.
  ///
  /// [restoId] menyaring pengumuman milik resto lain. Disaring di sini,
  /// bukan di query, karena penyaringannya berupa "milik semua resto ATAU
  /// milik resto saya" — dan baris untuk semua resto adalah yang
  /// resto_id-nya kosong, yang paling mudah terlewat kalau ditulis
  /// sebagai kondisi SQL.
  Future<List<Announcement>> inboxFor(String email, {String? restoId}) async {
    final rows = await _client
        .from('app_announcements')
        .select()
        .order('created_at', ascending: false);

    final states = await _client
        .from('inbox_states')
        .select()
        .eq('email', email);

    final deleted = <String>{};
    final read = <String>{};
    for (final s in states) {
      final id = s['announcement_id'] as String;
      if (s['deleted_at'] != null) deleted.add(id);
      if (s['read_at'] != null) read.add(id);
    }

    return rows
        .where((r) => !deleted.contains(r['id'] as String))
        .map((r) => Announcement.fromMap(r, read: read.contains(r['id'] as String)))
        .where((a) => a.visibleTo(restoId))
        .toList();
  }

  /// Pengumuman terbaru, tanpa perlu login — dipakai layar tamu untuk
  /// memberi tahu bahwa ada versi yang lebih baru.
  Future<Announcement?> latest() async {
    final rows = await _client
        .from('app_announcements')
        .select()
        .eq('category', 'update')
        .isFilter('resto_id', null)
        .not('version', 'is', null)
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Announcement.fromMap(rows.first);
  }

  /// Pengumuman umum milik satu resto, terbaru di atas.
  ///
  /// Dipakai halaman menu pelanggan. Tanpa keadaan dibaca/dihapus:
  /// pelanggan tamu tidak punya identitas yang bisa dipakai menyimpannya,
  /// dan yang perlu mereka tahu cuma isi pengumumannya.
  ///
  /// Yang dari Super Admin sengaja tidak ikut — pemberitahuan versi
  /// aplikasi urusan yang mengelola aplikasinya, bukan orang yang sedang
  /// memilih makan siang.
  Future<List<Announcement>> generalForResto(String restoId) async {
    final rows = await _client
        .from('app_announcements')
        .select()
        .eq('category', 'general')
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .limit(5);
    return rows.map((r) => Announcement.fromMap(r)).toList();
  }

  Future<void> markRead(String email, String announcementId) async {
    await _client.from('inbox_states').upsert({
      'email': email,
      'announcement_id': announcementId,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'email,announcement_id');
  }

  /// Menandai banyak pesan sekaligus sudah dibaca.
  ///
  /// Ditulis dalam satu perintah, bukan satu per satu: menandai dua
  /// puluh pesan berarti dua puluh perjalanan bolak-balik ke server, dan
  /// yang menekan "tandai semua" justru sedang membereskan tumpukan yang
  /// banyak.
  Future<void> markManyRead(String email, List<String> announcementIds) async {
    if (announcementIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('inbox_states').upsert([
      for (final id in announcementIds)
        {'email': email, 'announcement_id': id, 'read_at': now},
    ], onConflict: 'email,announcement_id');
  }

  Future<void> deleteForUser(String email, List<String> announcementIds) async {
    if (announcementIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('inbox_states').upsert([
      for (final id in announcementIds)
        {'email': email, 'announcement_id': id, 'read_at': now, 'deleted_at': now},
    ], onConflict: 'email,announcement_id');
  }

  /// Menerbitkan pengumuman.
  ///
  /// Pemberitahuan versi hanya boleh dari Super Admin; pengumuman umum
  /// boleh juga dari Admin resto untuk restonya sendiri. Keduanya
  /// ditegakkan RLS, bukan di sini — layar cuma menyembunyikan
  /// tombolnya.
  Future<void> publish({
    required String title,
    required String body,
    required AnnouncementCategory category,
    String? version,
    String? downloadUrl,
    String? restoId,
    String? imageBase64,
    required String createdBy,
  }) async {
    await _client.from('app_announcements').insert({
      'title': title,
      'body': body,
      'category': category.dbValue,
      if (version != null) 'version': version,
      if (downloadUrl != null) 'download_url': downloadUrl,
      if (restoId != null) 'resto_id': restoId,
      if (imageBase64 != null) 'image_base64': imageBase64,
      'created_by': createdBy,
    });
  }
}
