import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_app/widgets/order_card.dart';
import 'package:pos_app/db/order_repository.dart';
import 'package:pos_app/models/customer_order.dart';
import 'package:pos_app/models/order_type.dart';

/// Alur pesanan sesudah peran dapur berubah jadi Waiters.
///
/// Yang memakai layar itu sekarang mengantar makanan, bukan memutuskan
/// mana yang mulai dikerjakan — keputusan itu pindah ke kasir, di
/// tempat pesanannya diterima.
void main() {
  // OrderCard memformat tanggal dengan lokal id_ID, dan lokal itu harus
  // disiapkan dulu di lingkungan tes — tanpa ini kartunya melempar
  // LocaleDataException saat dibangun, dan yang terlihat cuma "tidak
  // ada teks yang cocok".
  setUpAll(() => initializeDateFormatting('id_ID'));

  String baca(String jalur) => File(jalur).readAsStringSync();

  group('nomor antrean yang sedang disiapkan', () {
    CustomerOrder pesanan({
      required int? nomor,
      required KitchenStatus status,
      required DateTime dibuat,
    }) =>
        CustomerOrder(
          id: 'id-$nomor-${dibuat.millisecondsSinceEpoch}',
          orderNo: nomor,
          createdAt: dibuat,
          items: const [],
          total: 10000,
          paymentStatus: OrderPaymentStatus.paid,
          customerLabel: 'Tamu',
          source: OrderSource.customer,
          kitchenStatus: status,
          restoId: 'r1',
          orderType: OrderType.dineIn,
        );

    // WIB = UTC+7. Dibuat sebagai UTC lalu dibaca sebagai WIB oleh
    // fungsinya, sama seperti baris yang datang dari server.
    final kini = DateTime.utc(2026, 11, 27, 5); // 12:00 WIB
    final hariIni = DateTime.utc(2026, 11, 27, 3); // 10:00 WIB
    final kemarin = DateTime.utc(2026, 11, 26, 3);

    test('hanya yang sedang diproses', () {
      final hasil = OrderRepository.nomorDisiapkan([
        pesanan(nomor: 1, status: KitchenStatus.waiting, dibuat: hariIni),
        pesanan(nomor: 2, status: KitchenStatus.onProgress, dibuat: hariIni),
        pesanan(nomor: 3, status: KitchenStatus.done, dibuat: hariIni),
      ], kini.toLocal());

      expect(hasil, [2]);
    });

    test('pesanan kemarin yang tertinggal tidak ikut', () {
      // Nomor antrean diulang tiap hari. Pesanan kemarin yang tidak
      // pernah ditandai selesai sebelum tutup akan tampil sebagai
      // antrean yang sedang dikerjakan sekarang — dan pelanggan yang
      // memegang nomor itu berdiri menghampiri kasir untuk pesanan
      // milik hari kemarin.
      final hasil = OrderRepository.nomorDisiapkan([
        pesanan(nomor: 3, status: KitchenStatus.onProgress, dibuat: kemarin),
        pesanan(nomor: 7, status: KitchenStatus.onProgress, dibuat: hariIni),
      ], kini.toLocal());

      expect(hasil, [7]);
    });

    test('diurutkan, dan yang tanpa nomor dilewati', () {
      final hasil = OrderRepository.nomorDisiapkan([
        pesanan(nomor: 9, status: KitchenStatus.onProgress, dibuat: hariIni),
        pesanan(nomor: null, status: KitchenStatus.onProgress, dibuat: hariIni),
        pesanan(nomor: 4, status: KitchenStatus.onProgress, dibuat: hariIni),
      ], kini.toLocal());

      expect(hasil, [4, 9]);
    });

    test('tidak ada yang diproses berarti daftar kosong', () {
      expect(
        OrderRepository.nomorDisiapkan([
          pesanan(nomor: 1, status: KitchenStatus.done, dibuat: hariIni),
        ], kini.toLocal()),
        isEmpty,
      );
    });
  });

  group('Status Pesanan tinggal dua tab', () {
    final layar = baca('lib/screens/chef_home_screen.dart');

    test('Diproses dan Selesai saja', () {
      final blok = layar.substring(
          layar.indexOf('static const _tabs'), layar.indexOf('];',
              layar.indexOf('static const _tabs')));
      expect(blok, contains("'Diproses'"));
      expect(blok, contains("'Selesai'"));
      expect(blok, isNot(contains("'Menunggu Bayar'")));
      expect(blok, isNot(contains("'Baru'")));
    });

    test('tabnya tidak bisa digeser lagi', () {
      // Dua tab muat dibagi rata. Tab yang bisa digeser padahal isinya
      // muat membuat orang mencari-cari tab ketiga yang tidak ada.
      final bar = layar.substring(layar.indexOf('bottom: TabBar('));
      expect(bar.substring(0, 200), isNot(contains('isScrollable: true')));
    });
  });

  group('lunas berarti langsung disiapkan', () {
    // Yang menyatakan sebuah pesanan mulai dikerjakan sekarang
    // pembayarannya sendiri, bukan ketukan siapa pun.
    //
    // ⚠ BATAS PENGUJIAN INI
    //
    // Pemicunya hidup di Postgres, dan tes Dart tidak bisa
    // menjalankannya. Yang diperiksa di bawah TEKS SQL-nya — jadi ia
    // menangkap klausa yang terhapus, tapi tidak membuktikan pemicunya
    // benar-benar menyala di basis data. Yang membuktikan itu query
    // pemeriksa di kaki berkas SQL-nya.
    final sql = baca('supabase/lunas_langsung_disiapkan.sql');

    test('dipicu saat payment_status berubah, dan saat pesanan lahir', () {
      // INSERT ikut, karena penjualan kasir LAHIR sudah lunas
      // (cart_provider.dart: paymentStatus: OrderPaymentStatus.paid).
      // Pemicu yang cuma mendengar UPDATE akan melewatkan seluruh
      // penjualan kasir.
      expect(sql, contains('before insert or update of payment_status'));
    });

    test('hanya dari waiting, supaya yang selesai tidak kembali ke antrean', () {
      // Pesanan yang sudah ditandai selesai lalu cara bayarnya
      // diperbaiki kasir tidak boleh muncul lagi di Diproses.
      expect(sql, contains("= 'waiting' then"));
      expect(sql, contains("new.kitchen_status := 'onProgress'"));
    });

    test('kitchen_status tidak masuk daftar kolom pemicunya', () {
      // Kalau ikut, tombol "kembalikan ke Menunggu" yang ditambahkan
      // nanti akan tampak tidak bekerja: statusnya dilontarkan balik di
      // dalam transaksi yang sama, tanpa jejak.
      final baris = sql
          .split('\n')
          .firstWhere((b) => b.startsWith('  before insert or update of'));
      expect(baris, isNot(contains('kitchen_status')));
    });

    test('backfill-nya hanya hari ini', () {
      // `watchAktif` tidak menyaring tanggal. Mendorong seluruh pesanan
      // lunas-tapi-menunggu sejak hari pertama berarti membangkitkan
      // pesanan berbulan lalu ke antrean waiter hari ini.
      final blok = sql.substring(sql.indexOf('update orders'));
      expect(blok, contains("date_trunc('day', now() at time zone 'Asia/Jakarta')"));
    });

    test('tidak ada lagi tombol Mulai Disiapkan di mana pun', () {
      // Tombol yang tidak pernah bisa muncul lebih buruk daripada
      // tombol yang tidak ada: ia tetap dibaca, diuji, dan dipelihara
      // oleh orang yang mengira ia bekerja.
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(f.readAsStringSync(), isNot(contains("'Mulai Disiapkan'")),
            reason: f.path);
      }
    });

    test('kasir punya akses Status Pesanan', () {
      final katalog = baca('lib/utils/katalog_menu.dart');
      final blok = katalog.substring(
          katalog.indexOf("'kasir': ["), katalog.indexOf("'admin': ["));
      expect(blok, contains("'Status Pesanan'"));
      expect(baca('lib/screens/kasir_home_screen.dart'),
          contains("title: 'Status Pesanan'"));
    });
  });

  group('kepala antrean di Status Pesanan', () {
    CustomerOrder contoh({
      int menitLalu = 0,
      int siap = 0,
      int jumlahItem = 2,
    }) =>
        CustomerOrder(
          // Sepanjang uuid: kartunya memotong delapan karakter
          // pertama sebagai nomor rujukan.
          id: '3f8c1a94-7b2d-4e51-9a60-5c7d2e1f8b43',
          orderNo: 7,
          createdAt: DateTime.now().subtract(Duration(minutes: menitLalu)),
          items: [
            for (var i = 0; i < jumlahItem; i++)
              CustomerOrderItem(
                productId: 'p$i',
                productName: 'Menu $i',
                price: 10000,
                quantity: 1,
              ),
          ],
          total: 10000 * jumlahItem,
          paymentStatus: OrderPaymentStatus.paid,
          customerLabel: 'Tamu',
          source: OrderSource.customer,
          kitchenStatus: KitchenStatus.onProgress,
          itemsDone: {for (var i = 0; i < siap; i++) i},
          restoId: 'r1',
          orderType: OrderType.dineIn,
        );

    Future<void> pasang(WidgetTester tester, Widget kartu) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ListView(children: [kartu])),
        ));

    testWidgets('nomor, lama, dan kemajuan tampil', (tester) async {
      await pasang(tester,
          OrderCard(order: contoh(menitLalu: 12, siap: 1), nomorBesar: true));

      expect(find.text('ANTREAN'), findsOneWidget);
      expect(find.text('12 menit'), findsOneWidget);
      expect(find.text('1/2 siap'), findsOneWidget);
    });

    testWidgets('mati secara bawaan, supaya layar lain tidak ikut berubah',
        (tester) async {
      await pasang(tester, OrderCard(order: contoh()));
      expect(find.text('ANTREAN'), findsNothing);
    });

    testWidgets('yang baru masuk tidak disebut nol menit', (tester) async {
      // "0 menit" terbaca seperti angka yang gagal dihitung.
      await pasang(tester, OrderCard(order: contoh(), nomorBesar: true));
      expect(find.text('Baru saja'), findsOneWidget);
    });
  });

  group('peran dapur berganti nama, bukan berganti nilai', () {
    test('labelnya Waiters', () {
      expect(baca('lib/providers/auth_provider.dart'),
          contains("EmployeeRole.chef: 'Waiters'"));
      expect(baca('lib/utils/katalog_menu.dart'),
          contains("'chef': 'Waiters'"));
    });

    test("nilainya di basis data tetap 'chef'", () {
      // Nilai itu disebut puluhan kali di kebijakan RLS. Menggantinya
      // berarti menyentuh seluruhnya sekaligus memigrasikan baris
      // karyawan yang ada — risiko nyata, tanpa satu pun yang terlihat
      // oleh orang yang memakainya.
      expect(baca('lib/providers/auth_provider.dart'),
          contains("EmployeeRole.chef: 'chef'"));
    });

    test('tidak ada lagi menu bernama Layar Dapur', () {
      for (final jalur in [
        'lib/utils/katalog_menu.dart',
        'lib/screens/owner_home_screen.dart',
        'lib/screens/kasir_home_screen.dart',
      ]) {
        expect(baca(jalur), isNot(contains("'Layar Dapur'")), reason: jalur);
      }
    });
  });

  group('kartu antrean menyebut siapa pesanannya', () {
    CustomerOrder milik({
      String? nama,
      String? meja,
      OrderType tipe = OrderType.dineIn,
    }) =>
        CustomerOrder(
          id: '3f8c1a94-7b2d-4e51-9a60-5c7d2e1f8b43',
          orderNo: 7,
          createdAt: DateTime.now(),
          items: const [],
          total: 10000,
          paymentStatus: OrderPaymentStatus.paid,
          customerLabel: 'orang@contoh.com',
          customerName: nama,
          tableNumber: meja,
          source: OrderSource.customer,
          kitchenStatus: KitchenStatus.onProgress,
          restoId: 'r1',
          orderType: tipe,
        );

    Future<void> pasang(WidgetTester t, Widget k) => t.pumpWidget(
        MaterialApp(home: Scaffold(body: ListView(children: [k]))));

    testWidgets('namanya tampil berikut tempatnya', (tester) async {
      await pasang(tester,
          OrderCard(order: milik(nama: 'Budi', meja: '4'), nomorBesar: true));
      expect(find.text('Budi · Meja 4'), findsOneWidget);
    });

    testWidgets('tanpa nama, tempatnya berdiri sendiri', (tester) async {
      // "Tamu · Meja 4" cuma menambah satu kata yang tidak memberi tahu
      // apa pun.
      await pasang(
          tester, OrderCard(order: milik(meja: '4'), nomorBesar: true));
      expect(find.text('Meja 4'), findsOneWidget);
    });

    testWidgets('email pemesan tidak pernah tampil', (tester) async {
      // `customerLabel` berisi email atau kata "Tamu". Layar ini dibaca
      // sambil lalu oleh siapa pun yang lewat.
      await pasang(tester,
          OrderCard(order: milik(meja: '4'), nomorBesar: true));
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('take away disebut take away', (tester) async {
      await pasang(
          tester,
          OrderCard(
              order: milik(nama: 'Sari', tipe: OrderType.takeAway),
              nomorBesar: true));
      expect(find.text('Sari · Take Away'), findsOneWidget);
    });

    testWidgets('nomornya tidak disebut dua kali', (tester) async {
      // Kepala antrean sudah memuat nomornya, besar. Chip kecil tepat
      // di bawahnya membuat satu pesanan menyebut nomornya dua kali
      // dengan ukuran berbeda.
      await pasang(tester,
          OrderCard(order: milik(nama: 'Budi', meja: '4'), nomorBesar: true));
      // Nomornya tiga digit: '#007' di chip, '007' di kepala besar.
      expect(find.text('007'), findsOneWidget);
      expect(find.text('#007'), findsNothing);
      // Dan mejanya juga tidak, karena sudah di barisnya.
      expect(find.text('Meja 4'), findsNothing);
    });

    testWidgets('di luar Status Pesanan, chip kecilnya tetap ada',
        (tester) async {
      await pasang(tester, OrderCard(order: milik(nama: 'Budi', meja: '4')));
      expect(find.text('#007'), findsOneWidget);
      expect(find.text('Meja 4'), findsOneWidget);
    });
  });

  group('antrean diurutkan yang masuk duluan', () {
    test('daftarnya dibalik, berikut tanggalnya', () {
      // Membalik isi tiap tanggal saja tidak cukup: pesanan kemarin
      // yang tidak pernah ditutup justru tersembunyi di bawah seluruh
      // pesanan hari ini, padahal dialah yang paling lama menunggu.
      final sumber = baca('lib/widgets/grouped_order_list.dart');
      final blok = sumber.substring(sumber.indexOf('final sorted ='));
      expect(blok.substring(0, 400), contains('terlamaDulu'));
      final kunci = sumber.substring(sumber.indexOf('final dateKeys'));
      expect(kunci.substring(0, 160), contains('terlamaDulu'));
    });

    test('dipakai tab Diproses, bukan tab lain', () {
      final layar = baca('lib/screens/chef_home_screen.dart');
      expect(layar, contains('terlamaDulu: tab.\$1 == KitchenStatus.onProgress'));
    });
  });

  group('penanda merah Status Pesanan', () {
    CustomerOrder o({
      required KitchenStatus dapur,
      OrderPaymentStatus bayar = OrderPaymentStatus.paid,
      OrderSource dari = OrderSource.customer,
    }) =>
        CustomerOrder(
          id: 'id-${dapur.name}-${bayar.name}-${dari.name}',
          orderNo: 1,
          createdAt: DateTime.now(),
          items: const [],
          total: 1000,
          paymentStatus: bayar,
          customerLabel: 'Tamu',
          source: dari,
          kitchenStatus: dapur,
          restoId: 'r1',
          orderType: OrderType.dineIn,
        );

    test('yang sedang diproses dan sudah lunas ikut dihitung', () {
      expect(o(dapur: KitchenStatus.onProgress).sedangDisiapkan, isTrue);
    });

    test('yang belum diproses atau sudah selesai tidak ikut', () {
      expect(o(dapur: KitchenStatus.waiting).sedangDisiapkan, isFalse);
      expect(o(dapur: KitchenStatus.done).sedangDisiapkan, isFalse);
    });

    test('yang hangus atau dibatalkan tidak ikut', () {
      // Kolom kitchen_status-nya berhenti di nilai terakhirnya —
      // riwayat butuh itu — tapi dapur tidak lagi mengerjakannya.
      for (final b in [
        OrderPaymentStatus.cancelled,
        OrderPaymentStatus.expired,
      ]) {
        expect(o(dapur: KitchenStatus.onProgress, bayar: b).sedangDisiapkan,
            isFalse,
            reason: b.name);
      }
    });

    test('pesanan pelanggan yang belum dibayar tidak ikut', () {
      expect(
          o(
            dapur: KitchenStatus.onProgress,
            bayar: OrderPaymentStatus.pending,
          ).sedangDisiapkan,
          isFalse);
    });

    test('tapi pesanan kasir yang belum dilunasi tetap ikut', () {
      // `isAwaitingPayment` hanya berlaku untuk pesanan dari pelanggan.
      // Pesanan yang diinput kasir sudah di tangan dapur apa pun status
      // bayarnya.
      expect(
          o(
            dapur: KitchenStatus.onProgress,
            bayar: OrderPaymentStatus.pending,
            dari: OrderSource.kasir,
          ).sedangDisiapkan,
          isTrue);
    });

    test('daftar dan penanda menanyakan hal yang sama', () {
      // Penanda yang berkata "2" di atas daftar berisi 5 lebih buruk
      // daripada tidak ada penanda: yang memercayainya tidak pernah
      // tahu ada tiga yang tidak terhitung. Itu sudah terjadi sekali
      // pada penanda Pending Payment.
      expect(baca('lib/screens/chef_home_screen.dart'),
          contains('o.sedangDisiapkan'));

      final repo = baca('lib/db/order_repository.dart');
      final blok = repo.substring(repo.indexOf('countSedangDisiapkan'));
      final fungsi = blok.substring(0, blok.indexOf('}'));
      expect(fungsi, contains("eq('kitchen_status', 'onProgress')"));
      expect(fungsi, contains('cancelled'));
      expect(fungsi, contains('expired'));
      expect(fungsi, contains('source.neq.customer'));
      expect(fungsi, contains('payment_status.neq.pending'));
    });

    test('kartunya berpenanda di SETIAP beranda yang punya menunya', () {
      // Penanda yang cuma ada di satu beranda berarti kasir yang
      // membuka aplikasinya sepanjang hari justru yang tidak pernah
      // melihat antrean tertinggal — padahal dialah yang paling dekat
      // dengan dapurnya.
      //
      // Daftarnya diambil dari katalog, bukan ditulis tangan: beranda
      // yang ditambahkan nanti ikut terjaring sendiri.
      final katalog = baca('lib/utils/katalog_menu.dart');
      final punya = <String>{};
      for (final m in RegExp(r"'(\w+)': \[(.*?)\n  \]", dotAll: true)
          .allMatches(katalog)) {
        if (m.group(2)!.contains("'Status Pesanan'")) punya.add(m.group(1)!);
      }
      // Chef TIDAK ikut: layarnya sendiri yang bernama Status Pesanan,
      // jadi tidak ada kartu menuju ke sana.
      punya.remove('chef');
      expect(punya, isNotEmpty);

      for (final peran in punya) {
        final hub = baca('lib/screens/${peran}_home_screen.dart');
        final i = hub.indexOf("title: 'Status Pesanan'");
        expect(i, greaterThan(0), reason: peran);
        // Dari pembuka kartunya sampai penutupnya, bukan jendela
        // sejumlah karakter: panjang komentar di atas tiap kartu
        // berbeda-beda, dan jendela tetap akan memotong kartu yang
        // komentarnya panjang tepat sebelum bagian yang diperiksa.
        // Nama kelasnya utuh: pola 'HubTile(' saja ikut cocok dengan
        // EKOR 'BadgedHubTile(', jadi bloknya dimulai sesudah kata
        // 'Badged' dan pemeriksaan di bawah selalu gagal.
        final buka = hub.lastIndexOf(RegExp(r'\b\w*HubTile\('), i);
        final tutup = hub.indexOf('\n                    ),', i);
        expect(buka, greaterThan(0), reason: peran);
        expect(tutup, greaterThan(i), reason: peran);
        final blok = hub.substring(buka, tutup);
        expect(blok, contains('BadgedHubTile'), reason: peran);
        expect(blok, contains('countSedangDisiapkan'), reason: peran);
      }
    });
  });
}
