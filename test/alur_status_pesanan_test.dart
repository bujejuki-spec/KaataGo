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
}
