// Lint ini menjaga aplikasi yang salah memakai pustaka web di kode
// bersama. Di sini justru itu tugasnya: berkas ini hanya pernah
// dikompilasi untuk web, lewat impor bersyarat di notifikasi_web.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Menampilkan notifikasi peramban.
///
/// Izinnya sudah diminta lebih dulu oleh Firebase Messaging saat token
/// diambil; kalau ditolak, `permission` bukan 'granted' dan panggilan
/// ini diam saja. Melemparkan galat di sini tidak ada gunanya — orang
/// yang menolak izin notifikasi sedang menyatakan pilihannya, bukan
/// mengalami kerusakan.
void tampilkanNotifWeb({
  required String judul,
  required String isi,
  String? tag,
}) {
  if (html.Notification.permission != 'granted') return;
  // `tag` membuat pesan yang sama tidak berbaris dua kali: yang baru
  // menimpa yang lama alih-alih menumpuk.
  html.Notification(judul, body: isi, tag: tag);
}
