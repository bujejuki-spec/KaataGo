import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
/// Notifikasi yang datang saat aplikasinya terbuka sengaja **tidak**
/// ditampilkan dari sini: aliran realtime sudah menampilkannya, dan
/// keduanya sekaligus berarti satu kejadian berbunyi dua kali.
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

      _ready = true;
      lastError = null;
    } catch (e) {
      lastError = 'Firebase gagal menyiapkan token — $e';
      debugPrint('[Push] gagal disiapkan: $e');
    }
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
