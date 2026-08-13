import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifikasi KaataGo: banner di layar HP lengkap dengan nada dering
/// sendiri, seperti pesan masuk yang lain.
///
/// Nada deringnya dibuat khusus (`res/raw/kaata_notif.wav`) — tiga nada
/// naik D5–A5–D6 bertimbre marimba. Nada bawaan Android terdengar sama
/// dengan puluhan aplikasi lain di HP yang sama, jadi tidak ada yang
/// menoleh; yang ini cukup berbeda untuk dikenali tanpa harus melihat
/// layar, tapi tidak seperti bel error yang bikin panik.
///
/// Catatan penting: ini notifikasi *lokal*. Ia muncul selama aplikasinya
/// masih hidup — di depan layar maupun baru saja dilatarbelakangkan.
/// Kalau aplikasinya benar-benar ditutup, Android menghentikan koneksi
/// realtime-nya dan tidak ada yang bisa memicu notifikasi. Untuk itu
/// perlu push notification (FCM) dengan server pengirim — pekerjaan
/// tersendiri yang belum ada di sini.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Dipisah per jenis supaya pemakainya bisa mematikan salah satunya
  /// lewat setelan Android tanpa ikut mematikan yang lain — dapur mungkin
  /// ingin bunyi terus, sementara kasir cukup yang pesanannya sendiri.
  static const _channels = [
    (
      id: 'kaata_order_status',
      name: 'Status Pesanan',
      description: 'Pemberitahuan saat pesanan mulai dimasak atau siap',
    ),
    (
      id: 'kaata_new_order',
      name: 'Pesanan Baru',
      description: 'Pemberitahuan untuk dapur saat ada pesanan masuk',
    ),
  ];

  static const _sound = RawResourceAndroidNotificationSound('kaata_notif');

  /// Turun jadi false kalau perangkat menolak nada dering khususnya.
  bool _customSoundWorks = true;

  /// Dicatat saat penyiapan gagal, supaya layar tes bisa menyebut
  /// sebabnya alih-alih diam.
  String? initError;

  Future<void> init() async {
    if (_ready) return;

    // 'ic_notification', bukan '@mipmap/ic_launcher'. Plugin mencari
    // ikonnya dengan getIdentifier(name, "drawable", package) — hanya di
    // folder drawable, dan tanpa memahami awalan '@mipmap/'. Nama yang
    // tidak ketemu menghasilkan id 0, Android menolak notifikasi tanpa
    // ikon kecil yang sah, dan kegagalannya tidak terlihat di mana pun
    // kecuali log. Itulah sebabnya notifikasi sebelumnya diam total.
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Channel dibuat lebih dulu: di Android 8+ suara dan tingkat
    // kepentingan melekat pada channel-nya, bukan pada tiap notifikasi.
    // Setelah channel terbentuk, keduanya tidak bisa diubah lagi dari
    // kode — pemakainya yang berkuasa lewat Setelan.
    for (final c in _channels) {
      try {
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            c.id,
            c.name,
            description: c.description,
            importance: Importance.high, // banner + bunyi
            sound: _sound,
            playSound: true,
            enableVibration: true,
          ),
        );
      } catch (e) {
        // Nada dering khusus yang tidak bisa dibaca perangkat tidak boleh
        // ikut menjatuhkan notifikasinya. Lebih baik berbunyi dengan nada
        // bawaan daripada tidak muncul sama sekali.
        debugPrint('[Notif] channel ${c.id} gagal dengan nada khusus: $e');
        initError = '$e';
        _customSoundWorks = false;
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            c.id,
            c.name,
            description: c.description,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    }

    _ready = true;
    initError = null;
  }

  /// Android 13+ mewajibkan izin ini; tanpa itu notifikasinya terkirim
  /// tapi tidak terlihat sama sekali. Ditolak bukan alasan untuk gagal —
  /// aplikasinya tetap jalan, hanya diam.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> showOrderStatus({
    required int id,
    required String title,
    required String body,
  }) =>
      _show(channel: _channels[0], id: id, title: title, body: body);

  Future<void> showNewOrder({
    required int id,
    required String title,
    required String body,
  }) =>
      _show(channel: _channels[1], id: id, title: title, body: body);

  Future<void> _show({
    required ({String id, String name, String description}) channel,
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
            sound: _customSoundWorks ? _sound : null,
            // Isi pesan bisa lebih panjang dari satu baris — tanpa ini
            // Android memotongnya diam-diam.
            styleInformation: BigTextStyleInformation(body),
            ticker: title,
          ),
          iOS: const DarwinNotificationDetails(sound: 'kaata_notif.wav'),
        ),
      );
      lastError = null;
    } catch (e) {
      // Notifikasi tidak pernah cukup penting untuk menjatuhkan alur yang
      // sedang berjalan — pesanannya sendiri sudah tersimpan. Tapi
      // penyebabnya disimpan, supaya layar Tes Notifikasi bisa
      // menyebutkannya alih-alih membiarkan orang menebak.
      lastError = '$e';
      debugPrint('[Notif] gagal menampilkan: $e');
    }
  }

  /// Alasan kegagalan terakhir, atau null kalau yang terakhir berhasil.
  String? lastError;

  /// Mengirim satu notifikasi contoh dan melaporkan hasilnya.
  ///
  /// Notifikasi gagal secara diam-diam karena banyak sebab di luar
  /// aplikasi — izin ditolak, channel dibisukan pemakainya, mode fokus.
  /// Tanpa cara mengujinya, "notifikasi tidak jalan" tidak bisa
  /// dibedakan dari "belum ada pesanan baru".
  Future<String> sendTest() async {
    try {
      await init();
    } catch (e) {
      return 'Sistem notifikasi gagal disiapkan: $e';
    }

    bool granted;
    try {
      granted = await requestPermission();
    } catch (e) {
      return 'Gagal meminta izin notifikasi: $e';
    }

    if (!granted) {
      return 'Izin notifikasi belum diberikan. Aktifkan lewat Setelan HP > '
          'Aplikasi > KaataGo > Notifikasi.';
    }

    lastError = null;
    await showNewOrder(
      id: 999999,
      title: 'Tes Notifikasi KaataGo',
      body: 'Kalau kamu melihat dan mendengar ini, notifikasi sudah aktif.',
    );

    if (lastError != null) return 'Gagal menampilkan notifikasi: $lastError';
    if (!_customSoundWorks) {
      return 'Notifikasi terkirim, tapi memakai nada bawaan HP — nada khas '
          'KaataGo ditolak perangkat ini.';
    }
    return 'Notifikasi terkirim. Cek layar HP kamu — kalau tidak muncul, '
        'periksa Setelan HP > Aplikasi > KaataGo > Notifikasi.';
  }
}
