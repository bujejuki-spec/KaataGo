import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/voucher.dart';

Voucher _batch({
  int total = 1000000,
  int quantity = 10,
  int amount = 100000,
  int claimed = 0,
  DateTime? expiresOn,
  bool active = true,
}) =>
    Voucher(
      id: 'VC-1',
      code: 'HEMAT100',
      name: 'Promo Pengguna Baru',
      totalAmount: total,
      quantity: quantity,
      amount: amount,
      expiresOn: expiresOn ?? DateTime.now().add(const Duration(days: 30)),
      active: active,
      createdAt: DateTime(2026, 8, 1),
      claimed: claimed,
    );

VoucherClaim _claim({
  VoucherClaimStatus status = VoucherClaimStatus.claimed,
  DateTime? expiresOn,
  int minPurchase = 0,
  List<String> restoIds = const [],
  int amount = 100000,
}) =>
    VoucherClaim(
      id: 'VCL-1',
      voucherId: 'VC-1',
      customerLabel: 'orang@contoh.com',
      amount: amount,
      status: status,
      createdAt: DateTime(2026, 8, 10),
      code: 'HEMAT100',
      name: 'Promo Pengguna Baru',
      expiresOn: expiresOn ?? DateTime.now().add(const Duration(days: 30)),
      minPurchase: minPurchase,
      restoIds: restoIds,
    );

void main() {
  group('batch voucher', () {
    test('sisa kuota berkurang seiring penebusan', () {
      expect(_batch(claimed: 3).sisa, 7);
      expect(_batch(claimed: 10).sisa, 0);
      expect(_batch(claimed: 10).habis, isTrue);
    });

    test('yang habis tidak bisa ditebus lagi', () {
      // Orang ke-11 harus ditolak, dan itu inti dari kuotanya.
      expect(_batch(claimed: 10).bisaDitebus, isFalse);
      expect(_batch(claimed: 9).bisaDitebus, isTrue);
    });

    test('yang kedaluwarsa tidak bisa ditebus', () {
      final lewat =
          _batch(expiresOn: DateTime.now().subtract(const Duration(days: 1)));
      expect(lewat.kedaluwarsa, isTrue);
      expect(lewat.bisaDitebus, isFalse);
    });

    test('yang ditutup tidak bisa ditebus walau kuotanya ada', () {
      expect(_batch(active: false).bisaDitebus, isFalse);
    });

    test('nilai yang menggantung di tangan pelanggan', () {
      // Sudah keluar dari saldo bebas, belum jadi apa pun.
      expect(_batch(claimed: 4, amount: 100000).nilaiTertebus, 400000);
    });

    test('kosongnya daftar resto berarti semua resto', () {
      expect(_batch().berlakuDiSemuaResto, isTrue);
    });
  });

  group('voucher milik pelanggan', () {
    test('yang baru ditebus siap dipakai', () {
      expect(_claim().siapDipakai, isTrue);
    });

    test('yang sudah dipakai tidak bisa dipakai lagi', () {
      expect(_claim(status: VoucherClaimStatus.used).siapDipakai, isFalse);
    });

    test('yang kedaluwarsa tidak siap dipakai walau statusnya masih claimed',
        () {
      // Penjadwal berjalan sekali sehari; di antara dua jalannya, status
      // di database masih 'claimed' padahal tanggalnya sudah lewat.
      // Layar tidak boleh menawarkan yang sudah hangus.
      final lewat =
          _claim(expiresOn: DateTime.now().subtract(const Duration(days: 1)));
      expect(lewat.siapDipakai, isFalse);
    });

    test('minimum belanja ditegakkan', () {
      final v = _claim(minPurchase: 50000);
      expect(v.bisaDipakaiDi('r1', 30000), isFalse);
      expect(v.bisaDipakaiDi('r1', 50000), isTrue);
    });

    test('resto yang tidak terdaftar ditolak', () {
      final v = _claim(restoIds: const ['r1']);
      expect(v.bisaDipakaiDi('r2', 100000), isFalse);
      expect(v.bisaDipakaiDi('r1', 100000), isTrue);
    });

    test('setiap penolakan punya kalimatnya', () {
      // Voucher yang tampil tapi tidak bisa dipilih tanpa penjelasan
      // membuat orang mengira aplikasinya rusak.
      expect(_claim(status: VoucherClaimStatus.used).alasanTidakBisa('r1', 1),
          'Sudah dipakai');
      expect(_claim(minPurchase: 50000).alasanTidakBisa('r1', 1),
          'Belanja belum mencapai minimum');
      expect(_claim(restoIds: const ['r1']).alasanTidakBisa('r2', 999999),
          'Tidak berlaku di resto ini');
      expect(_claim().alasanTidakBisa('r1', 999999), isNull);
    });

    test('tiap status punya labelnya sendiri', () {
      final semua =
          VoucherClaimStatus.values.map((s) => kVoucherClaimLabels[s]).toSet();
      expect(semua.length, VoucherClaimStatus.values.length);
    });

    test('terbaca dari baris database berikut batch-nya', () {
      final v = VoucherClaim.fromMap({
        'id': 'VCL-1',
        'voucher_id': 'VC-1',
        'customer_label': 'a@b.com',
        'amount': 100000,
        'status': 'claimed',
        'created_at': '2026-08-10T10:00:00Z',
        'vouchers': {
          'code': 'HEMAT100',
          'name': 'Promo',
          'expires_on': '2026-12-31',
          'min_purchase': 25000,
          'resto_ids': ['r1'],
        },
      });
      expect(v.code, 'HEMAT100');
      expect(v.minPurchase, 25000);
      expect(v.restoIds, ['r1']);
    });
  });

  group('pencairan sungguhan ke resto', () {
    final sql = File('supabase/voucher_payouts.sql').readAsStringSync();
    final fn =
        File('supabase/functions/settle-voucher-payouts/index.ts').readAsStringSync();

    test('pemicunya mengantre, bukan memanggil Xendit', () {
      // Panggilan penyedia di dalam transaksi pesanan berarti pesanan
      // pelanggan gagal tersimpan tiap kali penyedianya lambat.
      expect(sql, contains('insert into voucher_payouts'));
      expect(sql, isNot(contains('net.http_post(\n    url := \'https://api.xendit')));
    });

    test('satu klaim satu pencairan, dijaga basis data', () {
      expect(sql, contains('claim_id text not null unique'));
      expect(sql, contains('on conflict (claim_id) do nothing'));
    });

    test('yang sudah terkirim tidak bisa dibatalkan', () {
      expect(sql, contains("and status <> 'sent'"));
    });

    test('barisnya tidak pernah dihapus', () {
      expect(sql, isNot(contains('delete from voucher_payouts')));
    });

    test('tipe claim_id mengikuti voucher_claims, bukan menebak', () {
      // voucher_claims.id bertipe text; kunci asing bertipe uuid
      // ditolak Postgres saat dipasang, bukan saat dipakai.
      final vc = File('supabase/vouchers.sql').readAsStringSync();
      expect(vc, contains('id text primary key'));
      expect(sql, isNot(contains('claim_id uuid')));
    });

    test('hanya resto bersub-akun aktif yang diangkut', () {
      expect(sql, contains('a.active and a.account_id'));
    });

    test('klaim yang sudah terlanjur dipakai ikut diantre', () {
      // Tanggal pemasangan bukan garis pemisah antara utang dan bukan.
      expect(sql, contains("from voucher_claims c\nwhere c.status = 'used'"));
    });

    test('fungsi pencairannya memakai Transfers, bukan Disbursements', () {
      // Disbursement menuntut nomor rekening resto — yang sengaja
      // tidak kita simpan.
      expect(fn, contains('https://api.xendit.co/transfers'));
      expect(fn, isNot(contains('/disbursements')));
    });

    test('id klaim jadi reference sekaligus kunci idempotensi', () {
      expect(fn, contains('"X-IDEMPOTENCY-KEY": p.claim_id'));
      expect(fn, contains('reference: p.claim_id'));
    });

    test('duplikat dihitung berhasil, bukan gagal', () {
      // Menandainya gagal membuat barisnya dicoba ulang selamanya.
      expect(fn, contains('DUPLICATE_TRANSFER_ERROR'));
      expect(fn, contains('jawab.ok || sudahPernah'));
    });

    test('satu resto bermasalah tidak menghentikan yang lain', () {
      expect(fn, contains('} catch (e) {'));
      expect(fn, contains('p_ok: false'));
    });

    test('nominalnya dibaca server, tidak pernah dikirim pemanggil', () {
      expect(fn, contains('amount: p.amount'));
      expect(fn, isNot(contains('body.amount')));
    });

    test('menolak jalan tanpa pengenal akun sumber', () {
      // Transfer tanpa sumber yang jelas adalah uang yang diambil dari
      // akun yang tidak kita maksud.
      expect(fn, contains('XENDIT_ACCOUNT_ID belum diisi'));
    });

    test('penjadwalnya diam selama belum dikonfigurasi', () {
      expect(sql, contains('if v_cfg.function_url is null'));
      expect(sql, contains("cron.schedule('settle-voucher-payouts'"));
    });

    test('tabel konfigurasinya tidak terbaca peran mana pun', () {
      expect(sql, contains('alter table voucher_payout_config enable row level security'));
      expect(sql, isNot(contains('"voucher_payout_config: read"')));
    });
  });

  group('alur uangnya di SQL', () {
    final sql = File('supabase/vouchers.sql').readAsStringSync();

    test('terbit: saldo bebas keluar, kantong voucher terisi', () {
      expect(sql, contains("perform _jurnal_kaatago('total_balance'"));
      expect(sql, contains("perform _jurnal_kaatago('voucher', v_id"));
    });

    test('ditebus: pindah dari GL Voucher ke GL Voucher Redeem', () {
      final blok = sql.substring(sql.indexOf('function claim_voucher'));
      expect(blok, contains("_jurnal_kaatago('voucher', v_id, v.amount,\n    'debit'"));
      expect(blok, contains("_jurnal_kaatago('voucher_redeem'"));
    });

    test('dipakai: keluar dari Redeem, masuk ke GL resto', () {
      final blok = sql.substring(sql.indexOf('function log_voucher_use'));
      expect(blok, contains("_jurnal_kaatago('voucher_redeem'"));
      expect(blok, contains("_gl_account_for(new.resto_id, 'transfer')"));
      expect(blok, contains("'credit'"));
    });

    test('hangus: dananya pulang ke GL Total Saldo', () {
      final blok = sql.substring(sql.indexOf('function expire_vouchers'));
      expect(blok, contains("_jurnal_kaatago('total_balance'"));
      expect(blok, contains("'credit'"));
    });

    test('sisa yang tak pernah ditebus dihitung sekali saja', () {
      // `settled_at` yang menjaganya, bukan ingatan penjadwal.
      expect(sql, contains('settled_at is null'));
      expect(sql, contains('update vouchers set settled_at = now()'));
    });

    test('nomor akunnya sederet dengan GL Diskon', () {
      expect(sql, contains("'voucher',        '1100073'"));
      expect(sql, contains("'voucher_redeem', '1100074'"));
    });

    test('satu orang satu voucher per batch', () {
      // Tanpa ini, orang pertama yang membaca pengumumannya bisa
      // menebus kesepuluhnya sekaligus.
      expect(sql, contains('unique (voucher_id, customer_label)'));
    });

    test('kuota ditegakkan server, bukan aplikasi', () {
      expect(sql, contains('if v_terpakai >= v.quantity then'));
      expect(sql, contains('Voucher ini sudah habis'));
    });

    test('tiap penolakan penebusan menyebut alasannya', () {
      for (final alasan in [
        'Kode voucher tidak ditemukan',
        'Voucher ini sudah ditutup',
        'Voucher ini sudah kedaluwarsa',
        'Voucher ini sudah kamu tebus',
        'Voucher ini sudah habis',
      ]) {
        expect(sql, contains(alasan), reason: alasan);
      }
    });

    test('nominal per voucher dihitung server saat terbit', () {
      expect(sql, contains('v_amount := p_total / p_quantity'));
    });

    test('yang dicatat keluar hanya yang benar-benar bisa ditebus', () {
      // Sisa pembagian tidak pernah jadi voucher; mencatatnya sebagai
      // uang keluar berarti saldo berkurang untuk sesuatu yang tidak ada.
      expect(sql, contains('v_amount * p_quantity'));
    });

    test('hanya Super Admin yang menerbitkan', () {
      expect(sql, contains('Hanya Super Admin yang dapat menerbitkan voucher'));
    });

    test('tidak ada kebijakan tulis untuk siapa pun di tabel penebusan', () {
      // Menebus lewat RPC, memakai lewat pemicu — tangan yang bisa
      // menulis langsung ke sini adalah tangan yang bisa membuat voucher
      // dari udara.
      expect(sql, isNot(contains('"voucher_claims: write"')));
      expect(sql, contains('Tidak ada kebijakan tulis untuk siapa pun'));
    });

    test('pemakaian dicatat pemicu pada pesanan', () {
      expect(sql, contains('after insert on orders'));
      expect(sql, contains('function log_voucher_use'));
    });

    test('kedaluwarsa dijalankan penjadwal harian', () {
      expect(sql, contains("cron.schedule('expire-vouchers'"));
    });
  });
}
