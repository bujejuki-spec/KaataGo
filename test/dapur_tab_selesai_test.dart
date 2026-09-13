import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tab "Selesai" di layar dapur menampilkan satu tanggal, bawaannya hari
/// ini.
///
/// Sebelumnya ia menampilkan seluruh yang pernah selesai sekaligus:
/// dapur yang ingin memastikan satu pesanan barusan sudah keluar harus
/// melewati daftar berminggu-minggu lebih dulu.
void main() {
  final layar = File('lib/screens/chef_home_screen.dart').readAsStringSync();
  final repo = File('lib/db/order_repository.dart').readAsStringSync();

  test('bawaannya hari ini', () {
    expect(layar, contains('DateTime _tanggal = _hariIni()'));
    expect(layar, contains('bool get _iniHariIni'));
  });

  test('tanggal lain bisa dipilih lewat kalender', () {
    expect(layar, contains('showDatePicker('));
    expect(layar, contains("helpText: 'Lihat pesanan selesai tanggal'"));
  });

  // Hari yang belum terjadi tidak punya pesanan untuk ditampilkan.
  test('tidak bisa memilih hari yang belum terjadi', () {
    final blok = layar.substring(layar.indexOf('showDatePicker('));
    expect(blok.substring(0, 400), contains('lastDate: _hariIni()'));
  });

  // Tanpa jalan pulang, kembali ke antrean hari ini berarti menebak
  // tanggal hari ini sendiri di dalam pemilih tanggal.
  test('ada jalan kembali ke hari ini tanpa membuka kalender', () {
    expect(layar, contains('onKembaliKeHariIni'));
  });

  // Aliran realtime-nya dipotong 300 baris terakhir. Pada merchant
  // ramai, hari kemarin sudah terdorong keluar dari 300 itu — yang
  // tampil bukan hari yang sepi melainkan hari yang tidak lengkap,
  // tanpa satu pun tanda ada yang hilang.
  test('tanggal lampau dibaca ulang dari server', () {
    expect(layar, contains('_repo.padaTanggal(widget.restoId'));
    expect(repo, contains('Future<List<CustomerOrder>> padaTanggal('));
  });

  // Pesanan jam sebelas malam tercatat hari itu juga, bukan besok.
  test('batas harinya WIB, bukan UTC', () {
    final blok = repo.substring(repo.indexOf('padaTanggal('));
    expect(blok, contains('subtract(const Duration(hours: 7))'));
    expect(blok, contains("gte('created_at'"));
    expect(blok, contains("lt('created_at'"));
  });

  // Hari ini tetap ikut aliran realtime supaya pesanan yang baru ditutup
  // dapur langsung muncul — tapi aliran itu membawa 300 pesanan
  // terakhir, bukan pesanan hari ini.
  test('hari ini ikut realtime, dan tetap disaring ke tanggalnya', () {
    expect(layar, contains('widget.hariIni.where(_hariIniSaja)'));
  });

  // Tiga tab lainnya adalah antrean kerja yang harus terbaca sekaligus.
  test('tab lain tidak ikut diberi tanggal', () {
    expect(layar, contains('if (tab.\$1 == KitchenStatus.done) {'));
    // Sekali dipasang, dan hanya di dalam _TabSelesai — sisanya cuma
    // pendeklarasian kelasnya sendiri.
    final dipakai = '_PemilihTanggal('.allMatches(layar).length -
        'const _PemilihTanggal('.allMatches(layar).length;
    expect(dipakai, 1);
  });

  // Yang batal dan yang belum dibayar bukan pekerjaan dapur yang
  // selesai — saringannya harus sama untuk hari ini dan hari lampau.
  test('saringan tanggal lampau sama dengan hari ini', () {
    final blok = layar.substring(layar.indexOf('class _TabSelesaiState'));
    expect(blok, contains('o.kitchenStatus == KitchenStatus.done'));
    expect(blok, contains('!o.isVoid'));
    expect(blok, contains('!o.isAwaitingPayment'));
    expect(blok, contains('!o.dibatalkan'));
  });
}
