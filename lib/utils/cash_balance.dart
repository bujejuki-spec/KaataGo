import '../models/cash_deposit.dart';
import '../models/petty_cash_entry.dart';

/// Uang tunai yang seharusnya masih ada di laci kasir.
///
/// Satu perhitungan, dipakai dua layar — Saldo & Pengeluaran dan Setor
/// Saldo Cash. Sebelumnya masing-masing menghitung sendiri, dan keduanya
/// sempat berbeda: yang satu membuang pengajuan petty cash yang ditolak,
/// yang satu lagi tidak. Selisihnya persis sebesar pengajuan yang
/// ditolak, muncul di dua layar yang sama-sama mengaku menyebut "tunai
/// di laci", dan tidak ada cara menebak yang mana yang benar dari
/// layarnya saja.
///
/// Angka yang sama harus lahir dari kode yang sama. Selama dua tempat
/// menghitungnya masing-masing, keduanya akan berpisah lagi pada
/// perubahan berikutnya.
int cashOnHand({
  required int cashIncome,
  required List<CashDeposit> deposits,
  required List<PettyCashEntry> pettyCash,
}) {
  return cashIncome - depositedFromDrawer(deposits) - pettyCashFromDrawer(pettyCash);
}

/// Setoran yang sudah keluar dari laci.
///
/// Yang masih menunggu persetujuan ikut dihitung — fisik uangnya memang
/// sudah tidak ada di laci sejak diserahkan. Yang ditolak tidak:
/// uangnya dikembalikan menjadi tanggung jawab laci lagi.
int depositedFromDrawer(List<CashDeposit> deposits) => deposits
    .where((d) => d.status != DepositStatus.rejected)
    .fold(0, (sum, d) => sum + d.amount);

/// Tunai yang berpindah dari laci ke petty cash.
///
/// Aturan statusnya sama persis dengan setoran, dan karena alasan yang
/// sama.
int pettyCashFromDrawer(List<PettyCashEntry> entries) => entries
    .where((e) =>
        e.source == PettyCashSource.cashWithdrawal &&
        e.status != PettyCashStatus.rejected)
    .fold(0, (sum, e) => sum + e.amount);
