import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'notification_router.dart';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

/// Mendaftarkan perangkat ini supaya bisa dikirimi notifikasi walau
/// aplikasinya sedang tertutup.
///
/// Notifikasi yang sudah ada dibangkitkan aplikasinya sendiri dari aliran
/// realtime — dan itu hanya bekerja selama prosesnya hidup. Begitu
/// aplikasinya ditutup dari daftar aplikasi terkini, atau HP-nya
/// dinyalakan ulang, atau penghemat baterainya turun tangan, tidak ada
/// lagi yang mendengarkan.
///
/// Push membalik arahnya: server yang mengetuk HP-nya. Yang perlu
/// disimpan cuma satu hal — token perangkat, berikut keterangan siapa
/// yang sedang memakainya, supaya server tahu pesan mana pantas dikirim
/// ke mana.
///
/// Notifikasi pesanan yang datang saat aplikasinya terbuka sengaja
/// **tidak** ditampilkan dari sini: aliran realtime sudah
/// menampilkannya, dan keduanya sekaligus berarti satu kejadian
/// berbunyi dua kali.
///
/// Pengumuman adalah kekecualiannya — lihat [_foregroundEvents].
class PushService {
  PushService._();
  static final instance = PushService._();

  final _client = Supabase.instance.client;

  bool _ready = false;
  String? _token;

  /// Penanda pendaftaran terakhir. Menulis ulang baris yang sama setiap
  /// kali layar dibangun ulang hanya membebani jaringan tanpa mengubah
  /// apa pun.
  String? _lastRegistration;

  /// Dicatat kalau penyiapannya gagal, supaya layar tes bisa menyebut
  /// sebabnya alih-alih diam — kegagalan push nyaris selalu tak terlihat
  /// sampai ada yang menunggu notifikasi yang tidak pernah datang.
  ///
  /// Disertai tahapnya, karena dua kegagalan yang sangat berbeda
  /// bersembunyi di balik gejala yang sama persis ("tidak ada notifikasi
  /// masuk"): Firebase yang gagal memberi token, dan token yang didapat
  /// tapi gagal disimpan ke server. Yang pertama urusan setelan
  /// perangkat, yang kedua urusan izin di database — dan tanpa
  /// menyebutkan yang mana, keduanya akan dicari di tempat yang salah.
  String? lastError;

  Future<void> init() async {
    if (_ready) return;
    // Notifikasi dorong tidak ada di web.
    //
    // Bukan sekadar tidak didukung: konsol web dibuka di depan layar
    // yang sedang ditatap orangnya, dan yang dikabarkan notifikasi
    // justru hal yang terjadi saat aplikasinya TIDAK dibuka.
    if (kIsWeb) {
      _ready = true;
      return;
    }
    try {
      await Firebase.initializeApp();
      _token = await FirebaseMessaging.instance.getToken();

      // Token bisa berganti sendiri — setelah aplikasi dipasang ulang,
      // data aplikasinya dibersihkan, atau Google memutar ulang token
      // yang sudah lama. Token lama yang tidak diperbarui berarti
      // notifikasi terkirim ke ketiadaan, tanpa galat apa pun.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        _lastRegistration = null;
        final last = _lastOwner;
        if (last != null) register(email: last.$1, restoId: last.$2, role: last.$3);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);

      // Ketukan pada notifikasi yang ditampilkan Android sendiri —
      // saat aplikasinya di latar belakang.
      FirebaseMessaging.onMessageOpenedApp.listen(_onTap);

      // Dan saat aplikasinya sedang tertutup sama sekali: pesannya
      // menunggu di sini, sekali. Tanpa ini, notifikasi yang diketuk
      // dari layar kunci cuma membuka aplikasi di halaman terakhir —
      // dan yang paling sering diketuk dari layar kunci justru yang
      // paling mendesak.
      final awal = await FirebaseMessaging.instance.getInitialMessage();
      if (awal != null) {
        // Ditunda satu frame: saat ini navigator-nya belum terpasang,
        // dan mendorong halaman ke navigator yang belum ada tidak
        // melakukan apa-apa selain menghilangkan niat orangnya.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _onTap(awal));
      }

      _ready = true;
      lastError = null;
    } catch (e) {
      lastError = 'Firebase gagal menyiapkan token — $e';
      debugPrint('[Push] gagal disiapkan: $e');
    }
  }

  /// Kejadian yang tetap ditampilkan walau aplikasinya sedang terbuka.
  ///
  /// Android tidak pernah menampilkan sendiri notifikasi yang tiba saat
  /// aplikasinya di depan — pesannya diserahkan ke aplikasi, dan kalau
  /// aplikasinya diam, tidak ada apa pun yang muncul. Untuk pesanan itu
  /// benar: aliran realtime sudah membunyikannya sendiri, dan
  /// menampilkan keduanya berarti satu pesanan berbunyi dua kali.
  ///
  /// Pengumuman tidak punya aliran realtime yang menampilkannya. Tanpa
  /// daftar ini, pengumuman yang tiba selagi orangnya memandangi
  /// layarnya adalah satu-satunya yang tidak pernah dia dengar.
  ///
  /// Ajakan menilai ikut di sini dengan alasan yang sama: ia tidak
  /// punya aliran realtime yang menampilkannya, dan yang tiba selagi
  /// orangnya memandangi layar akan hilang tanpa pernah terlihat.
  /// Pesan KaataGo Support ikut, dan alasannya sama sekali lain dari
  /// pesanan.
  ///
  /// Pesanan punya aliran realtime yang menampilkannya di layar mana pun
  /// pegawainya berada. Percakapan support tidak: alirannya hanya hidup
  /// selama layar percakapan ITU terbuka. KaataGo Admin yang sedang
  /// membuka daftar, membuka percakapan lain, atau membuka menu lain
  /// sama sekali tidak akan pernah tahu ada pesan masuk — persis
  /// keadaan yang paling sering terjadi.
  static const _foregroundEvents = {
    'announcement',
    'review_prompt',
    'support_message',
  };

  /// Percakapan support yang sedang dibuka orangnya.
  ///
  /// Notifikasi untuk percakapan yang sedang dipandangi tidak
  /// ditampilkan — pesannya sudah muncul di layar detik itu juga, dan
  /// membunyikannya lagi cuma mengagetkan orang yang sedang membacanya.
  static String? tiketSupportTerbuka;

  /// Membuka halaman yang dimaksud notifikasinya.
  ///
  /// Ketukan adalah pernyataan niat: orangnya ingin melihat hal itu,
  /// sekarang. Membuangnya ke halaman terakhir berarti dia harus
  /// mengingat sendiri apa yang barusan dikabarkan lalu mencarinya lewat
  /// tiga ketukan lagi.
  void _onTap(RemoteMessage message) {
    // Seluruh datanya ikut: sebagian tujuan butuh lebih dari nama
    // kejadiannya — ajakan menilai perlu tahu merchant mana.
    NotificationRouter.buka(
      message.data['event'] as String?,
      data: Map<String, dynamic>.from(message.data),
    );
  }

  void _onForeground(RemoteMessage message) {
    final event = message.data['event'] as String?;
    if (event == null || !_foregroundEvents.contains(event)) return;

    final notification = message.notification;
    if (notification == null) return;

    if (event == 'support_message' &&
        message.data['ticket_id'] == tiketSupportTerbuka) {
      return;
    }

    NotificationService.instance.showAnnouncement(
      event: event,
      restoId: message.data['resto_id'] as String?,
      // Dari hashCode pesannya, bukan penghitung yang naik terus:
      // pengumuman yang sama yang tiba dua kali menimpa dirinya
      // sendiri alih-alih berbaris dua kali di panel notifikasi.
      id: (message.messageId ?? notification.title ?? '').hashCode & 0x7fffffff,
      title: notification.title ?? 'Pengumuman',
      body: notification.body ?? '',
    );
  }

  (String?, String?, String?)? _lastOwner;

  /// Menautkan perangkat ini ke orang yang sedang memakainya.
  ///
  /// [email] null berarti pelanggan yang belum login; [sessionId] yang
  /// mewakilinya. Tamu adalah sebagian besar pelanggan resto, dan
  /// mengabaikan mereka berarti fitur ini hanya bekerja untuk yang
  /// paling jarang membutuhkannya.
  Future<void> register({
    String? email,
    String? restoId,
    String? role,
    String? sessionId,
  }) async {
    await init();
    final token = _token;
    if (token == null) {
      lastError ??= 'Firebase tidak memberi token untuk perangkat ini.';
      return;
    }

    final signature = '$token|$email|$restoId|$role|$sessionId';
    if (signature == _lastRegistration) return;
    _lastOwner = (email, restoId, role);

    try {
      // Lewat fungsi, bukan menulis langsung ke tabelnya.
      //
      // Menulis langsung berarti aplikasi butuh hak baca atas
      // device_tokens — upsert mengharuskan Postgres membaca baris yang
      // bentrok lebih dulu — dan hak baca itu membuka seluruh daftar
      // token berikut email karyawan dan restonya kepada siapa pun yang
      // punya anon key, yang memang tertanam di dalam APK.
      //
      // Dengan fungsi ini, tabelnya tertutup rapat: aplikasi tidak bisa
      // membaca, mengubah, atau menghapus baris mana pun — hanya bisa
      // menitipkan tokennya sendiri.
      await _client.rpc('register_device_token', params: {
        'p_token': token,
        'p_email': email,
        'p_resto_id': restoId,
        'p_role': role,
        'p_session_id': sessionId,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      });
      _lastRegistration = signature;
      lastError = null;
    } catch (e) {
      lastError = 'Token didapat, tapi gagal disimpan ke server — $e';
      debugPrint('[Push] gagal mendaftarkan token: $e');
    }
  }

  /// Melepas perangkat ini saat orangnya keluar.
  ///
  /// Tanpa ini, kasir yang logout di HP bersama tetap menerima kabar
  /// setoran rekannya — dan kabar soal uang yang bukan urusannya adalah
  /// hal pertama yang membuat orang mematikan notifikasi seluruhnya.
  Future<void> unregister() async {
    final token = _token;
    _lastRegistration = null;
    _lastOwner = null;
    if (token == null) return;
    try {
      await _client.rpc('unregister_device_token', params: {'p_token': token});
    } catch (e) {
      debugPrint('[Push] gagal melepas token: $e');
    }
  }

  /// Untuk layar Tes Notifikasi: token perangkat ini, dipendekkan.
  String? get tokenPreview {
    final t = _token;
    if (t == null) return null;
    return t.length <= 16 ? t : '${t.substring(0, 8)}…${t.substring(t.length - 6)}';
  }
}
