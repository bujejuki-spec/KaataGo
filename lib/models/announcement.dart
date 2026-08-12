/// Pengumuman dari KaataGo — untuk sekarang: pemberitahuan versi baru.
///
/// Disimpan sekali, bukan disalin ke tiap penerima. Menyalin berarti
/// orang yang mendaftar besok tidak akan pernah melihat pengumuman hari
/// ini, dan setiap blast menambah ribuan baris kembar. Yang disimpan per
/// orang hanyalah keadaannya — sudah dibaca, atau sudah dihapus.
class Announcement {
  final String id;
  final String title;
  final String body;

  /// Versi aplikasi yang diumumkan, mis. "1.32.0". Dipakai layar tamu
  /// untuk tahu apakah aplikasi yang terpasang sudah tertinggal, tanpa
  /// perlu punya akun.
  final String? version;

  final String? downloadUrl;
  final DateTime createdAt;

  /// Keadaan pembacanya, hasil gabungan dengan tabel inbox_states.
  final bool read;

  Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.version,
    this.downloadUrl,
    required this.createdAt,
    this.read = false,
  });

  Announcement copyWith({bool? read}) => Announcement(
        id: id,
        title: title,
        body: body,
        version: version,
        downloadUrl: downloadUrl,
        createdAt: createdAt,
        read: read ?? this.read,
      );

  factory Announcement.fromMap(Map<String, dynamic> map, {bool read = false}) {
    return Announcement(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Pengumuman',
      body: map['body'] as String? ?? '',
      version: map['version'] as String?,
      downloadUrl: map['download_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      read: read,
    );
  }
}

/// Membandingkan dua versi bergaya "1.32.0".
///
/// Perbandingan teks biasa salah di tempat yang justru sering terjadi:
/// "1.9.0" lebih besar dari "1.10.0" kalau diadu sebagai string, padahal
/// 1.10.0 yang lebih baru.
///
/// Nomor build setelah "+" diabaikan. `pubspec.yaml` menulis versi
/// sebagai "1.32.0+68", dan menghitung 68 sebagai bagian keempat akan
/// membuat "1.32.0+68" terlihat lebih baru daripada "1.32.0" — dua
/// penulisan untuk rilis yang sama persis.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('+')
      .first
      .split(RegExp(r'[^0-9]+'))
      .where((p) => p.isNotEmpty)
      .map(int.parse)
      .toList();

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
