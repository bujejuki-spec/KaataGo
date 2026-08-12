import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement.dart';

class AnnouncementRepository {
  final _client = Supabase.instance.client;

  /// Inbox seseorang: seluruh pengumuman yang belum dia hapus.
  ///
  /// Penghapusan dicatat per orang, bukan dengan membuang pengumumannya —
  /// satu orang membersihkan inbox-nya tidak boleh menghilangkan
  /// pengumuman itu dari orang lain.
  Future<List<Announcement>> inboxFor(String email) async {
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
        .toList();
  }

  /// Pengumuman terbaru, tanpa perlu login — dipakai layar tamu untuk
  /// memberi tahu bahwa ada versi yang lebih baru.
  Future<Announcement?> latest() async {
    final rows = await _client
        .from('app_announcements')
        .select()
        .not('version', 'is', null)
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Announcement.fromMap(rows.first);
  }

  Future<void> markRead(String email, String announcementId) async {
    await _client.from('inbox_states').upsert({
      'email': email,
      'announcement_id': announcementId,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'email,announcement_id');
  }

  Future<void> deleteForUser(String email, List<String> announcementIds) async {
    if (announcementIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('inbox_states').upsert([
      for (final id in announcementIds)
        {'email': email, 'announcement_id': id, 'read_at': now, 'deleted_at': now},
    ], onConflict: 'email,announcement_id');
  }

  /// Menerbitkan pengumuman. Hanya super_admin yang diizinkan RLS.
  Future<void> publish({
    required String title,
    required String body,
    String? version,
    String? downloadUrl,
    required String createdBy,
  }) async {
    await _client.from('app_announcements').insert({
      'title': title,
      'body': body,
      if (version != null) 'version': version,
      if (downloadUrl != null) 'download_url': downloadUrl,
      'created_by': createdBy,
    });
  }
}
