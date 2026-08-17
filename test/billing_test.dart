import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/billing.dart';

BillingState _state({
  bool locked = false,
  int? daysLeft,
  InvoiceStatus? status = InvoiceStatus.unpaid,
  int price = 150000,
  bool active = true,
  String? invoiceId = 'INV-ABC',
}) =>
    BillingState(
      locked: locked,
      daysLeft: daysLeft,
      invoiceStatus: status,
      monthlyPrice: price,
      active: active,
      invoiceId: invoiceId,
      amount: price,
      dueDate: DateTime(2026, 9, 1),
    );

void main() {
  group('pengingat tagihan', () {
    test('muncul tepat H-3, tidak lebih awal', () {
      expect(_state(daysLeft: 4).perluDiingatkan, isFalse);
      expect(_state(daysLeft: 3).perluDiingatkan, isTrue);
    });

    test('masih muncul pada hari jatuh tempo', () {
      expect(_state(daysLeft: 0).perluDiingatkan, isTrue);
    });

    test('tetap muncul sesudah lewat tempo', () {
      // Justru di sinilah pengingatnya paling dibutuhkan — berhenti
      // mengingatkan tepat saat keadaannya memburuk adalah kebalikan
      // dari yang dimaksud.
      final lewat = _state(daysLeft: -2);
      expect(lewat.perluDiingatkan, isTrue);
      expect(lewat.lewatTempo, isTrue);
    });

    test('tidak muncul kalau tagihannya sudah lunas', () {
      expect(_state(daysLeft: 1, status: InvoiceStatus.paid).perluDiingatkan,
          isFalse);
    });

    test('tidak muncul kalau dibebaskan', () {
      expect(_state(daysLeft: 1, status: InvoiceStatus.waived).perluDiingatkan,
          isFalse);
    });

    test('resto gratis tidak pernah diingatkan', () {
      expect(_state(daysLeft: 0, price: 0).perluDiingatkan, isFalse);
    });

    test('langganan yang dimatikan tidak pernah diingatkan', () {
      expect(_state(daysLeft: 0, active: false).perluDiingatkan, isFalse);
    });

    test('tanpa tagihan terbuka, tidak ada yang diingatkan', () {
      expect(_state(daysLeft: 0, invoiceId: null).perluDiingatkan, isFalse);
    });

    test('keadaan tenang tidak mengingatkan apa pun', () {
      expect(BillingState.tenang.perluDiingatkan, isFalse);
      expect(BillingState.tenang.locked, isFalse);
    });
  });

  group('bentuk data', () {
    test('status yang tidak dikenal jatuh ke belum dibayar', () {
      final inv = BillingInvoice.fromMap({
        'id': 'INV-1',
        'resto_id': 'r1',
        'period_start': '2026-08-01',
        'period_end': '2026-08-31',
        'due_date': '2026-09-01',
        'amount': 150000,
        'status': 'entah-apa',
      });
      expect(inv.status, InvoiceStatus.unpaid);
      expect(inv.open, isTrue);
    });

    test('tiap status punya labelnya sendiri', () {
      final semua = InvoiceStatus.values.map((s) => kInvoiceStatusLabels[s]);
      expect(semua.toSet().length, InvoiceStatus.values.length);
    });

    test('hanya belum dibayar dan menunggu verifikasi yang terhitung terbuka',
        () {
      BillingInvoice inv(InvoiceStatus s) => BillingInvoice(
            id: 'x',
            restoId: 'r1',
            periodStart: DateTime(2026, 8, 1),
            periodEnd: DateTime(2026, 8, 31),
            dueDate: DateTime(2026, 9, 1),
            amount: 1,
            status: s,
          );
      expect(
        [for (final s in InvoiceStatus.values) if (inv(s).open) s],
        [InvoiceStatus.unpaid, InvoiceStatus.review],
      );
    });

    test('setelan bawaan resto baru adalah gratis', () {
      const s = RestoBilling(restoId: 'r1');
      expect(s.gratis, isTrue);
      expect(s.billingDay, 1);
      expect(s.graceDays, 1);
    });
  });

  group('aturan penguncian di SQL', () {
    // Penguncian yang sebenarnya hidup di database, bukan di Dart —
    // layar yang terkunci hanyalah layar. Yang diperiksa di sini adalah
    // berkas SQL-nya sendiri.
    final sql = File('supabase/billing.sql').readAsStringSync();

    test('penguncian dipasang sebagai kebijakan RESTRICTIVE', () {
      // Kebijakan permissive digabung dengan OR — menambah satu lagi
      // justru MELONGGARKAN aksesnya, dan kunci yang dipasang begitu
      // tidak mengunci apa pun.
      expect(sql, contains('as restrictive for insert'));
      expect(sql, contains('as restrictive for update'));
    });

    test('pesanan dan katalog sama-sama dikunci', () {
      expect(sql, contains('"orders: billing lock"'));
      expect(sql, contains('"products: billing lock"'));
    });

    test('Super Admin tidak pernah terkunci', () {
      expect(sql, contains('when is_super_admin() then false'));
    });

    test('yang sudah mengunggah bukti tidak dikunci', () {
      // Mengunci orang yang sudah membayar adalah kesalahan yang paling
      // mahal di seluruh fitur ini.
      expect(sql, contains("t.status = 'unpaid'"));
    });

    test('resto gratis tidak pernah dikunci', () {
      expect(sql, contains('s.monthly_price > 0'));
    });

    test('penguncian menghormati tenggang', () {
      expect(sql, contains('current_date > t.due_date + s.grace_days'));
    });

    test('tanggal tagih dibatasi 1-28', () {
      // "Tanggal 31" tidak ada di Februari, dan menggesernya diam-diam
      // membuat tagihan datang di hari yang tidak dijanjikan.
      expect(sql, contains('billing_day between 1 and 28'));
    });

    test('satu tagihan per resto per periode', () {
      expect(sql, contains('unique (resto_id, period_start)'));
    });

    test('resto tidak bisa menyatakan dirinya lunas', () {
      // submit_billing_payment hanya boleh menaikkan ke 'review'.
      final fungsi = sql.substring(sql.indexOf('function submit_billing_payment'),
          sql.indexOf('function review_billing_payment'));
      expect(fungsi, contains("status = 'review'"));
      expect(fungsi, isNot(contains("status = 'paid'")));
    });

    test('hanya Super Admin yang memutuskan lunas', () {
      final fungsi = sql.substring(sql.indexOf('function review_billing_payment'));
      expect(fungsi, contains('if not is_super_admin() then'));
    });

    test('resto baru langsung punya barisnya, dan gratis', () {
      expect(sql, contains('after insert on restaurants'));
      expect(sql, contains('values (new.id, 0, 1)'));
    });
  });
}
