import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/screens/faq_screen.dart';

void main() {
  final faq = File('lib/screens/faq_screen.dart').readAsStringSync();
  final tentang = File('lib/screens/about_screen.dart').readAsStringSync();
  final web = File('../KaataGo Web/index.html').readAsStringSync();

  group('alamat surel', () {
    // Alasannya sama dengan nomor WhatsApp: dua alamat terpisah akan
    // berpisah suatu saat, dan yang menemukannya adalah orang yang
    // menulis ke alamat yang sudah tidak dibaca.
    test('sama dengan yang di landing page', () {
      expect(kEmailKaataGo, 'kaatago.app@gmail.com');
      expect(web, contains('mailto:$kEmailKaataGo'));
    });

    test('membuka mailto berikut subjeknya', () {
      expect(faq, contains("scheme: 'mailto'"));
      expect(faq, contains('subject='));
    });

    test('kegagalannya dikatakan, bukan didiamkan', () {
      final fungsi = faq.substring(faq.indexOf('bukaEmailKaataGo'));
      expect(fungsi, contains('Tidak ada aplikasi surel yang terpasang.'));
    });

    test('tampil di layar Tentang KaataGo', () {
      expect(tentang, contains('bukaEmailKaataGo(context)'));
      expect(tentang, contains('kEmailKaataGo'));
    });

    // Yang membaca FAQ lalu tidak menemukan jawabannya justru orang yang
    // paling perlu tahu ke mana harus bertanya.
    test('tampil di FAQ landing page, bukan cuma di footer', () {
      final faqWeb = web.substring(web.indexOf('id="faq"'));
      expect(faqWeb.substring(0, faqWeb.indexOf('<footer>')),
          contains(kEmailKaataGo));
    });
  });

  group('nomor WhatsApp', () {
    test('sama dengan yang di landing page', () {
      // Dua nomor terpisah akan berpisah suatu saat, dan yang
      // menemukannya adalah orang yang mengirim pesan ke nomor yang
      // sudah tidak dipakai.
      expect(kWhatsAppKaataGo, '6281316090867');
      expect(web, contains('wa.me/$kWhatsAppKaataGo'));
    });

    test('membuka wa.me, langsung ke percakapannya', () {
      expect(faq, contains('https://wa.me/\$kWhatsAppKaataGo?text='));
      expect(faq, contains('LaunchMode.externalApplication'));
    });

    test('kegagalannya dikatakan, bukan didiamkan', () {
      expect(faq, contains('Tidak bisa membuka WhatsApp.'));
    });

    test('tombolnya ada di FAQ maupun Tentang', () {
      expect(faq, contains('Chat KaataGo Admin'));
      expect(tentang, contains('bukaWhatsAppKaataGo(context)'));
    });
  });

  group('isi FAQ', () {
    test('pertanyaannya sama dengan landing page', () {
      for (final t in [
        'Apakah customer perlu install aplikasi juga?',
        'Kenapa customer perlu install KaataGo?',
        'Bagaimana kalau internet mati?',
        'Apakah pembayaran QRIS diproses oleh KaataGo?',
        'Tarif PPN dan biaya service bisa diatur?',
        'Berapa biaya langganan per bulannya?',
      ]) {
        expect(faq, contains(t), reason: t);
        expect(web, contains(t), reason: 'hilang di web: $t');
      }
    });

    test('disalin, bukan diambil dari webnya', () {
      // Halaman yang gagal dimuat karena sinyal buruk berarti jawaban
      // yang paling dibutuhkan saat sedang bermasalah tidak terbaca.
      expect(faq, isNot(contains('http://')));
      expect(faq, contains("const _faq = <(String, String)>["));
    });

    test('memakai kata merchant, bukan resto', () {
      final isi = faq.substring(faq.indexOf('const _faq'));
      expect(isi, isNot(contains(' resto ')));
    });
  });

  group('Tentang KaataGo', () {
    test('punya tombol FAQ mengambang', () {
      expect(tentang, contains('floatingActionButton: FloatingActionButton.extended'));
      expect(tentang, contains('const FaqScreen()'));
    });

    test('menyisakan ruang supaya baris terakhir tidak tertutup', () {
      expect(tentang, contains('SizedBox(height: 72)'));
    });

    test('fitur barunya ikut disebut', () {
      for (final f in [
        'Voucher KaataGo',
        'Nomor pesanan',
        'Merchant terdekat',
        'Layar pelanggan',
        'Cari menu',
        'Topping & level',
        'Fasilitas tempat',
        'Setoran modal',
        'Tagihan langganan',
      ]) {
        expect(tentang, contains(f), reason: f);
      }
    });
  });

  group('nama peran', () {
    test('Super Admin sudah jadi KaataGo Admin di teks', () {
      final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
      expect(auth, contains("EmployeeRole.superAdmin: 'KaataGo Admin'"));
    });

    test('nilai di basis data tidak ikut berubah', () {
      // 'super_admin' dipakai RLS dan kolom employees; menggantinya
      // berarti tiap kebijakan harus ikut diubah.
      final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
      expect(auth, contains("EmployeeRole.superAdmin: 'super_admin'"));
    });
  });
}
