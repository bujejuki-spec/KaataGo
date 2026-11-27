import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_order.dart';
import '../utils/gambar_unggah.dart';
import '../utils/id_time.dart';
import 'guest_order_store.dart';

/// Supabase-backed repository for orders. This is the bridge between
/// Kasir/Customer (who place orders) and Chef (who tracks kitchen status)
/// — an order written here shows up live everywhere it's watched, via
/// Postgres realtime subscriptions.
class OrderRepository {
  final _client = Supabase.instance.client;

  Future<String> create(CustomerOrder order) async {
    final row = await _client.from('orders').insert(order.toMap()).select().single();
    return row['id'] as String;
  }

  /// Membuat pesanan dan mengembalikan nomor antreannya.
  ///
  /// Nomornya diberikan pemicu di basis data, jadi baru diketahui
  /// sesudah barisnya benar-benar tersimpan — tidak bisa ditebak di
  /// aplikasi tanpa mengulangi pencacahannya, dan pencacah kedua adalah
  /// nomor kembar saat dua kasir menutup transaksi bersamaan.
  Future<int?> createReturningNo(CustomerOrder order) async {
    final row = await _client.from('orders').insert(order.toMap()).select().single();
    return (row['order_no'] as num?)?.toInt();
  }

  /// Confirms the customer's (dummy) QRIS payment. Goes through the
  /// `mark_order_paid` RPC (SECURITY DEFINER) instead of a direct table
  /// UPDATE — a guest customer has no employee RLS privileges to update
  /// `orders` directly, and the RPC's own guardrails (source='customer',
  /// pending→paid only) keep this safe without reopening that up.
  Future<void> markPaid(String orderId) async {
    await _client.rpc('mark_order_paid', params: {'p_order_id': orderId});
  }

  /// Pesanan mandiri yang pelanggannya memilih bayar tunai di kasir dan
  /// belum dilunasi — isi layar Pending Payment.
  ///
  /// Sengaja dibatasi ke `source = customer`: pesanan yang diinput kasir
  /// sudah dibayar di tempat begitu dicatat, jadi kalau ada yang masih
  /// pending di sana itu bukan antrean pembayaran melainkan data
  /// setengah jadi yang tidak boleh ikut ditagihkan di sini.
  Stream<List<CustomerOrder>> watchPendingCashPayments(String restoId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .limit(batasAliran)
        .map((rows) => rows
            .map((r) => CustomerOrder.fromMap(r))
            .where((o) => o.isPendingCashPayment)
            .toList());
  }

  /// Berapa pesanan yang menunggu dibayar di kasir — isi penanda merah
  /// di kartu menunya.
  /// Berapa pesanan yang sedang disiapkan — isi tab "Diproses".
  ///
  /// Harus menjawab pertanyaan yang sama dengan
  /// [CustomerOrder.sedangDisiapkan], yang menyaring daftarnya di Dart.
  /// Dua saringan untuk satu pertanyaan berarti penanda merah yang
  /// berkata "2" di atas daftar berisi 5 — dan itu sudah pernah terjadi
  /// pada penanda Pending Payment.
  ///
  /// `kitchen_status` di basis data bernilai 'onProgress', camelCase:
  /// yang ditulis `KitchenStatus.name`, bukan snake_case seperti kolom
  /// di sekitarnya.
  Future<int> countSedangDisiapkan(String restoId) async {
    return await _client
        .from('orders')
        .count(CountOption.exact)
        .eq('resto_id', restoId)
        .eq('kitchen_status', 'onProgress')
        // isVoid — hangus atau dibatalkan.
        .not('payment_status', 'in', '("cancelled","expired")')
        // isAwaitingPayment — NOT(dari pelanggan DAN belum dibayar).
        .or('source.neq.customer,payment_status.neq.pending');
  }

  Future<int> pendingCashPaymentCount(String restoId) async {
    return await _client
        .from('orders')
        .count(CountOption.exact)
        .eq('resto_id', restoId)
        .eq('source', 'customer')
        .eq('payment_status', 'pending')
        // Keduanya, sama seperti daftar yang dibukanya.
        //
        // Penyaringan daftarnya terjadi di Dart lewat
        // [CustomerOrder.isPendingCashPayment], yang sudah menyertakan
        // QRIS Statis — sementara hitungan ini menyaring di SQL dan
        // hanya menghitung tunai. Akibatnya penanda merah berkata "2"
        // di atas daftar berisi 5, dan yang memercayai angkanya tidak
        // pernah tahu ada tiga pembayaran yang menunggu.
        .inFilter('payment_method', const ['cash', 'qris_static']);
  }

  /// Melunasi pesanan tunai di meja kasir.
  ///
  /// Uang yang diterima ikut disimpan supaya struk yang dicetak ulang
  /// nanti tetap bisa menyebut kembaliannya. Kembaliannya sendiri tidak
  /// disimpan — selalu bisa dihitung ulang, dan dua angka yang saling
  /// terikat hanya membuka peluang keduanya tidak lagi cocok.
  Future<void> settleCashPayment(
    String orderId, {
    required int cashReceived,
    String? settledBy,
  }) async {
    await _client.from('orders').update({
      'payment_status': OrderPaymentStatus.paid.name,
      'cash_received': cashReceived,
      'settled_by': settledBy ?? 'kasir',
      'settled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Melunasi pesanan dengan cara bayar selain yang dipilih pelanggan.
  ///
  /// Pelanggan memilih "bayar tunai di kasir" dari HP-nya, lalu sampai
  /// di kasir dan ternyata uangnya kurang, atau memang lebih suka
  /// membayar dengan QRIS. Tanpa ini, satu-satunya jalan keluarnya
  /// adalah membatalkan pesanan lalu mengetiknya ulang dari awal —
  /// pesanan yang sudah dimasak dapur, dengan nomor yang sudah
  /// disebutkan pelanggannya.
  ///
  /// [method] ditulis juga ke kolom cara bayarnya, bukan hanya status
  /// lunasnya: pemicu di database membaca kolom itu untuk menentukan GL
  /// mana yang dikredit. Uang QRIS yang tercatat di GL Kas berarti laci
  /// yang tidak pernah cocok, dan mutasi bank yang tidak pernah
  /// ditemukan pasangannya.
  /// Melampirkan bukti bayar QRIS Statis milik pelanggan.
  ///
  /// Disimpan sebagai base64 di baris pesanannya, bukan sebagai berkas
  /// di Storage. Pemeriksaan format dan ukurannya terjadi sebelum ini
  /// ([GambarUnggah.siapkan]) — yang sampai ke sini sudah JPG yang
  /// dikecilkan.
  ///
  /// Tetap lewat fungsi, bukan update biasa: pelanggan — apalagi tamu
  /// yang tidak login — tidak punya hak mengubah baris pesanan, dan
  /// memang tidak boleh punya. Baris itu juga memuat status dapur,
  /// total, dan diskonnya.
  Future<void> lampirkanBuktiBayar({
    required String orderId,
    required Uint8List bytes,
  }) async {
    // Bukti transfer dibiarkan lebih besar daripada foto menu: angkanya
    // harus tetap terbaca oleh mata orang yang memutuskan uangnya sudah
    // masuk atau belum.
    final base64 = GambarUnggah.siapkan(bytes, sisiMaks: 1600, mutu: 82);
    await _client.rpc('lampirkan_bukti_bayar', params: {
      'p_order_id': orderId,
      'p_jalur': base64,
    });
  }

  Future<void> settlePayment(
    String orderId, {
    required String method,
    int? cashReceived,
    String? settledBy,
  }) async {
    await _client.from('orders').update({
      'payment_status': OrderPaymentStatus.paid.name,
      'payment_method': method,
      if (cashReceived != null) 'cash_received': cashReceived,
      // Ditulis apa pun cara bayarnya. Inilah yang menentukan pesanan
      // ini masuk Riwayat Kasir — bukan lagi cara bayarnya, yang justru
      // baru saja diganti di layar ini.
      'settled_by': settledBy ?? 'kasir',
      'settled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Membatalkan pesanan atas permintaan pelanggannya sendiri.
  ///
  /// Mengembalikan null kalau berhasil, atau alasan penolakannya dalam
  /// kalimat yang layak dibaca orang. Aturannya ditegakkan di database,
  /// bukan di sini: layar ini bisa saja memakai data yang sudah basi —
  /// dapur mungkin mulai memasak tepat saat tombolnya ditekan.
  Future<String?> cancelMyOrder(
    String orderId, {
    String? sessionId,
    String? email,
  }) async {
    final result = await _client.rpc('cancel_my_order', params: {
      'p_order_id': orderId,
      'p_session_id': sessionId,
      'p_email': email,
    });
    return result as String?;
  }

  /// Aliran langsung satu pesanan.
  ///
  /// Dipakai layar pembayaran untuk mengetahui pesanannya sudah lunas
  /// tanpa perlu menanyakannya berulang. Dengan gateway sungguhan,
  /// yang menyatakan lunas adalah webhook penyedia — jadi HP-nya
  /// memang harus menunggu kabar, bukan memutuskan sendiri.
  Stream<CustomerOrder?> watchOne(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty ? null : CustomerOrder.fromMap(rows.first));
  }

  Future<void> updateKitchenStatus(String orderId, KitchenStatus status) async {
    await _client.from('orders').update({'kitchen_status': status.name}).eq('id', orderId);
  }

  /// Menyimpan menu mana saja yang sudah dicentang dapur, sekaligus
  /// status barunya.
  ///
  /// Keduanya ditulis dalam satu perintah supaya tidak pernah ada
  /// keadaan antara: pesanan yang sudah tercentang penuh tapi statusnya
  /// masih "dimasak" karena update kedua gagal di tengah jalan.
  Future<void> updateChecklist(
    String orderId, {
    required Set<int> itemsDone,
    required KitchenStatus status,
  }) async {
    await _client.from('orders').update({
      'items_done': itemsDone.toList()..sort(),
      'kitchen_status': status.name,
    }).eq('id', orderId);
  }

  /// Berapa pesanan terakhir yang dipegang aliran langsung.
  ///
  /// Bukan angka keramat, tapi bukan juga asal: layar Pesanan Masuk dan
  /// dapur menampilkan antrean hari ini, dan resto tersibuk pun tidak
  /// melewati angka ini dalam sehari. Yang lebih lama dari itu dibuka
  /// lewat Riwayat Transaksi, yang memuatnya bertahap.
  static const batasAliran = 300;

  /// Pesanan terbaru, hidup. Untuk layar Pesanan Masuk, dapur, dan
  /// notifikasi.
  ///
  /// Dibatasi, dan itu inti perubahannya. Sebelumnya aliran ini
  /// berlangganan SELURUH riwayat pesanan resto — tanpa batas jumlah
  /// maupun tanggal — sehingga tiap perangkat kasir dan dapur mengunduh
  /// ulang seluruh sejarahnya tiap kali aplikasinya dibuka. Beratnya
  /// tumbuh tiap hari selamanya, dan tidak seorang pun bisa menunjuk
  /// kapan ia mulai berat.
  ///
  /// Yang ditampilkan layar-layar itu cuma antrean hari ini. Berhenti
  /// mengunduh yang tidak ditampilkan tidak mengubah satu piksel pun.
  Stream<List<CustomerOrder>> watchAktif(String restoId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .limit(batasAliran)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }

  /// Seluruh pesanan resto, sekali baca, tanpa batas.
  ///
  /// Dipakai layar Finance yang menjumlahkan sejak awal: Saldo Cash,
  /// Penghasilan, laporan, dan pemasukan tunai di Setor Saldo Cash.
  /// Angka-angka itu HARUS melihat semuanya — Saldo Cash yang cuma
  /// menghitung sebulan terakhir tetap muncul, tetap terlihat wajar, dan
  /// salah tanpa satu pun pesan galat. Itu jenis kerusakan yang paling
  /// mahal.
  ///
  /// Bukan stream, dan itu disengaja: pemakainya dulu memanggil
  /// `watchAll(...).first` — membuka langganan realtime lalu langsung
  /// membuangnya setelah satu nilai. Sekali baca mengerjakan hal yang
  /// sama tanpa memakai satu pun kuota koneksi realtime.
  ///
  /// Catatan untuk nanti: menarik seluruh pesanan ke HP demi satu angka
  /// juga tidak akan bertahan selamanya. Jawaban akhirnya menjumlahkannya
  /// di server dan mengembalikan totalnya saja.
  Future<List<CustomerOrder>> semua(String restoId) async {
    final rows = await _client
        .from('orders')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => CustomerOrder.fromMap(r)).toList();
  }

  /// Satu halaman riwayat pesanan, terbaru lebih dulu.
  ///
  /// Riwayat dipotong per halaman, bukan per tanggal. Riwayat yang tidak
  /// bisa digulir ke belakang adalah data yang hilang dari sudut pandang
  /// yang memakainya, meskipun barisnya masih utuh di basis data.
  Future<List<CustomerOrder>> halaman(String restoId,
      {int lewati = 0, int ambil = 50}) async {
    final rows = await _client
        .from('orders')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .range(lewati, lewati + ambil - 1);
    return rows.map((r) => CustomerOrder.fromMap(r)).toList();
  }

  /// Pesanan sebuah tanggal, sekali baca.
  ///
  /// Dipakai tab "Selesai" di layar dapur saat yang dilihat bukan hari
  /// ini. Aliran realtime-nya dipotong 300 baris terakhir — cukup untuk
  /// antrean yang sedang berjalan, dan justru menyesatkan untuk tanggal
  /// lampau: pada merchant ramai, hari kemarin sudah terdorong keluar
  /// dari 300 itu, dan yang terlihat adalah hari yang seolah sepi.
  ///
  /// Batasnya WIB, bukan UTC: pesanan jam sebelas malam tercatat hari
  /// itu juga, bukan besok.
  Future<List<CustomerOrder>> padaTanggal(
    String restoId, {
    required DateTime tanggal,
  }) async {
    final awalWib = DateTime(tanggal.year, tanggal.month, tanggal.day);
    final mulai = awalWib.subtract(const Duration(hours: 7));
    final akhir = mulai.add(const Duration(days: 1));

    final rows = await _client
        .from('orders')
        .select()
        .eq('resto_id', restoId)
        .gte('created_at', mulai.toIso8601String())
        .lt('created_at', akhir.toIso8601String())
        .order('created_at', ascending: false);
    return rows.map((r) => CustomerOrder.fromMap(r)).toList();
  }

  /// Live stream of orders belonging to one customer session (the "parent"
  /// id assigned right after scanning a table QR) — used by the customer's
  /// own order-status screen so they can track progress without an account.
  Stream<List<CustomerOrder>> watchBySession(String sessionId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        // Satu sesi meja jarang melewati puluhan pesanan, tapi batasnya
        // tetap dipasang: yang tidak berbatas selalu jadi tidak berbatas
        // di tempat yang tidak diduga.
        .limit(100)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }

  /// Hands this device's guest orders over to the email that just logged
  /// in, and reports how many were taken. Returns 0 — claiming nothing —
  /// when that email already has orders of its own, which is how the two
  /// histories stay unmerged for a returning customer.
  ///
  /// Goes through the `claim_guest_orders` RPC because customers can't
  /// UPDATE `orders` directly under RLS; the RPC reads the target email
  /// from the caller's own session rather than trusting an argument.
  Future<int> claimGuestOrders(List<String> orderIds) async {
    if (orderIds.isEmpty) return 0;
    final result = await _client.rpc(
      'claim_guest_orders',
      params: {'p_order_ids': orderIds},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// One-shot fetch of specific orders by id, newest first — backs a
  /// guest's history, where the ids come from device-local storage (see
  /// [GuestOrderStore]) rather than an account. Not a stream: Supabase
  /// realtime only filters streams by equality, and this needs `in`.
  /// Pesanan milik tamu: dari sesinya, DITAMBAH yang tercatat di
  /// penyimpanan peramban.
  ///
  /// ── Kenapa tidak cukup sesinya saja ──────────────────────────────
  ///
  /// Sesi bisa berganti karena beberapa sebab yang tidak disadari
  /// pelanggan: sesinya diakhiri server setelah semua pesanan selesai,
  /// atau dia memindai QR meja yang berbeda. Begitu sesinya berganti,
  /// pesanan lamanya tetap utuh di server tapi berhenti terlihat —
  /// karena layarnya cuma bertanya "pesanan di sesi ini".
  ///
  /// Yang menunggu makanannya lalu kehilangan jejak pesanannya sendiri,
  /// dan tidak ada galat apa pun yang menjelaskan ke mana perginya.
  ///
  /// Id tiap pesanan sudah disimpan di perangkatnya sejak dibuat
  /// ([GuestOrderStore], yang di peramban mendarat di localStorage).
  /// Di sinilah catatan itu dipakai.
  Stream<List<CustomerOrder>> watchPesananTamu(String? sessionId) {
    final dasar = sessionId == null
        ? Stream<List<CustomerOrder>>.value(const [])
        : watchBySession(sessionId);

    return dasar.asyncMap((dariSesi) async {
      final ids = await GuestOrderStore().ids();
      final kurang =
          ids.where((id) => !dariSesi.any((o) => o.id == id)).toList();
      if (kurang.isEmpty) return dariSesi;

      // Yang dari sesi didahulukan: ia datang dari aliran langsung, jadi
      // statusnya yang paling baru. Yang dari catatan cuma menambah apa
      // yang tidak ada di sana.
      final tambahan = await getByIds(kurang);
      return [...dariSesi, ...tambahan]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  /// Nomor antrean yang sedang disiapkan di sebuah merchant, hari ini.
  ///
  /// Dipakai layar pelanggan untuk menjawab pertanyaan yang paling
  /// sering muncul sambil menunggu: "sudah sampai nomor berapa?".
  /// Tanpa itu, satu-satunya cara mengetahuinya adalah bertanya ke
  /// kasir — dan yang bertanya berdiri meninggalkan mejanya.
  ///
  /// Disaring di Dart, bukan di kueri: aliran Supabase cuma menerima
  /// satu penyaring kesamaan, dan yang dipakai sudah restonya.
  Stream<List<int>> watchAntreanDisiapkan(String restoId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .limit(batasAliran)
        .map((rows) => nomorDisiapkan(
              rows.map(CustomerOrder.fromMap).toList(),
              DateTime.now().toWib(),
            ));
  }

  /// Nomor antrean yang sedang disiapkan, disaring dari daftar pesanan.
  ///
  /// Berdiri sebagai fungsi murni supaya bisa diuji: di dalam pemetaan
  /// aliran, satu-satunya cara memeriksanya adalah punya Supabase yang
  /// berjalan — dan yang tidak bisa diuji di sini adalah yang halus.
  ///
  /// Yang halus di sini soal tanggal. Nomor antrean diulang tiap hari,
  /// jadi pesanan KEMARIN yang tertinggal di status "diproses" — tidak
  /// pernah ditandai selesai sebelum tutup — akan tampil sebagai
  /// antrean yang sedang dikerjakan sekarang. Pelanggan yang memegang
  /// nomor 3 melihat "sedang disiapkan #003" lalu berdiri menghampiri
  /// kasir, padahal itu nomor 3 milik hari kemarin.
  static List<int> nomorDisiapkan(List<CustomerOrder> pesanan, DateTime kini) {
    final nomor = <int>[];
    for (final o in pesanan) {
      if (o.kitchenStatus != KitchenStatus.onProgress) continue;
      if (o.orderNo == null) continue;
      final w = o.createdAt.toWib();
      if (w.year != kini.year || w.month != kini.month || w.day != kini.day) {
        continue;
      }
      nomor.add(o.orderNo!);
    }
    nomor.sort();
    return nomor;
  }

  Future<List<CustomerOrder>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('orders')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return rows.map((r) => CustomerOrder.fromMap(r)).toList();
  }

  /// Live stream of every order ever placed under this email — across
  /// every restaurant/table/session. Used by a logged-in customer's
  /// "Riwayat Saya" screen, since login (not device-local storage) is
  /// what lets their history follow them anywhere.
  Stream<List<CustomerOrder>> watchByCustomerEmail(String email) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('customer_label', email)
        .order('created_at', ascending: false)
        // Riwayat pelanggan lama bisa ratusan pesanan lintas resto, dan
        // yang dilihatnya di layar cuma yang teratas.
        .limit(100)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }
}
