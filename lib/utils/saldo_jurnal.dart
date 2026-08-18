import '../models/gl_journal_entry.dart';

/// Menghitung saldo dari baris jurnal.
///
/// Ditaruh di satu berkas karena dua layar memakainya — Jurnal GL dan
/// Saldo & Pengeluaran. Dua perhitungan terpisah akan berpisah, dan
/// yang terlihat adalah dua layar yang menyebut angka berbeda untuk
/// uang yang sama (TSD §11.1b).

/// Pasangan pembatalan: baris pembatal dan baris yang dibatalkannya
/// sama-sama berhenti dihitung.
String _kunciPasangan(GlJournalEntry e) =>
    '${e.referenceType}|${e.referenceId}|${e.glCode}';

/// Baris yang masih berlaku — bukan pembatalan, dan bukan yang dibatalkan.
List<GlJournalEntry> barisBerlaku(List<GlJournalEntry> semua) {
  final dibatalkan =
      semua.where((e) => e.isReversal).map(_kunciPasangan).toSet();
  return semua
      .where((e) => !e.isReversal && !dibatalkan.contains(_kunciPasangan(e)))
      .toList();
}

/// Saldo pembukuan KaataGo sendiri.
///
/// Dihitung dari pergerakan **akun GL Total Saldo**, bukan dari daftar
/// jenis transaksi. Tiap fitur baru yang memindahkan uang selalu lewat
/// akun itu — langganan, diskon langganan, voucher, pengeluaran — jadi
/// aturannya tidak perlu ditambahi tiap kali ada fitur baru.
///
/// Daftar jenis transaksi pernah dipakai di sini, dan itu yang membuat
/// saldo KaataGo berbunyi Rp 0 saat voucher terbit: jenisnya belum ada
/// di daftar, jadi pergerakannya tidak terhitung sama sekali. Kesalahan
/// semacam itu tidak mengeluh — angkanya cuma salah, dan tetap terlihat
/// masuk akal.
///
/// Kredit menambah, debit mengurangi: uang masuk dikredit ke akun ini,
/// uang keluar didebit darinya.
int saldoPlatform(List<GlJournalEntry> semua, String kodeTotalSaldo) {
  final berlaku = barisBerlaku(semua);
  var saldo = 0;
  for (final e in berlaku) {
    if (e.glCode != kodeTotalSaldo) continue;
    saldo += e.entryType == JournalEntryType.credit ? e.amount : -e.amount;
  }
  return saldo;
}

/// Uang masuk ke pembukuan KaataGo — kredit ke GL Total Saldo.
int pemasukanPlatform(List<GlJournalEntry> semua, String kodeTotalSaldo) =>
    barisBerlaku(semua)
        .where((e) =>
            e.glCode == kodeTotalSaldo &&
            e.entryType == JournalEntryType.credit)
        .fold(0, (jumlah, e) => jumlah + e.amount);

/// Uang keluar dari pembukuan KaataGo — debit dari GL Total Saldo.
int pengeluaranPlatform(List<GlJournalEntry> semua, String kodeTotalSaldo) =>
    barisBerlaku(semua)
        .where((e) =>
            e.glCode == kodeTotalSaldo &&
            e.entryType == JournalEntryType.debit)
        .fold(0, (jumlah, e) => jumlah + e.amount);
