/// Sisi bukan-web: tidak melakukan apa pun.
///
/// Ada supaya berkas yang memanggilnya tetap bisa dibangun untuk
/// Android tanpa satu pun percabangan `kIsWeb` di tempat pemakaiannya.
void tampilkanNotifWeb({
  required String judul,
  required String isi,
  String? tag,
}) {}
