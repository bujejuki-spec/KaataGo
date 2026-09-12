import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/cash_deposit.dart';

void main() {
  CashDeposit buat({
    String method = 'setor',
    String? pickedUpBy,
    String? sealNumber,
    String? bankAccountId,
  }) =>
      CashDeposit(
        id: 'd1',
        restoId: 'r1',
        amount: 500000,
        proofBase64: 'AAA',
        method: method,
        pickedUpBy: pickedUpBy,
        sealNumber: sealNumber,
        bankAccountId: bankAccountId,
        createdBy: 'kasir@contoh.com',
        createdAt: DateTime(2026, 9, 12),
      );

  // Pickup dan setoran satu tabel karena yang terjadi pada uangnya sama
  // persis: lembarannya keluar dari laci, dan cashOnHand sudah tahu cara
  // menghitung itu. Tabel terpisah berarti Saldo Cash harus diajari
  // sumber kedua — dan selama belum diajari, uang yang sudah dibawa
  // pergi masih dihitung ada di laci.
  group('pickup lewat jalur yang sama dengan setoran', () {
    test('penandanya terbaca', () {
      expect(buat().isPickup, isFalse);
      expect(buat(method: 'pickup', pickedUpBy: 'Budi').isPickup, isTrue);
    });

    test('bawaan sebuah setoran adalah setor', () {
      expect(buat().method, 'setor');
    });

    test('keterangan pickup ikut tersimpan', () {
      final map = buat(
        method: 'pickup',
        pickedUpBy: 'Budi',
        sealNumber: 'SG-0091',
      ).toMap();
      expect(map['method'], 'pickup');
      expect(map['picked_up_by'], 'Budi');
      expect(map['seal_number'], 'SG-0091');
    });

    // Sebagian jasa penjemputan memakai segel, sebagian tidak.
    // Mewajibkannya berarti menahan kasir yang jasanya memang tidak
    // memberi segel.
    test('nomor segel boleh kosong', () {
      final map = buat(method: 'pickup', pickedUpBy: 'Budi').toMap();
      expect(map.containsKey('seal_number'), isFalse);
    });

    test('setoran menyebut rekening tujuannya', () {
      expect(buat(bankAccountId: 'acc-1').toMap()['bank_account_id'], 'acc-1');
    });
  });

  group('aturannya ditegakkan basis data', () {
    final sql = File('supabase/setor_dan_pickup.sql').readAsStringSync();

    // Uang yang keluar laci tanpa nama penerima adalah uang yang tidak
    // bisa ditanyakan ke siapa pun besok pagi.
    test('pickup wajib menyebut penjemputnya', () {
      expect(sql, contains('cash_deposits_pickup_check'));
      expect(sql, contains("method <> 'pickup'"));
    });

    // Bukti wajib untuk yang baru saja. NOT NULL akan menolak tabelnya
    // diubah sampai seseorang mengarang bukti untuk setoran tahun lalu.
    test('bukti wajib lewat pemicu, bukan NOT NULL', () {
      expect(sql, contains('create trigger wajib_bukti_setoran'));
      expect(sql, contains('before insert on cash_deposits'));
      expect(sql, isNot(contains('alter column proof_base64 set not null')));
    });

    // Menebak setoran lama masuk ke rekening mana berarti membuat data
    // yang terlihat pasti padahal karangan.
    test('rekening tujuan tidak ditebak mundur', () {
      expect(sql, isNot(contains('update cash_deposits')));
    });
  });

  test('bukti wajib ditegakkan layarnya juga', () {
    final layar =
        File('lib/screens/cash_deposit_screen.dart').readAsStringSync();
    expect(layar, contains('bool get _siap => _accountReady && _proof != null;'));
    expect(layar, contains('bool get _siap => _bukti != null;'));
  });
}
