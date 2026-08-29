import '../models/cash_deposit.dart';
import '../models/cash_variance.dart';
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
  List<CashVariance> selisih = const [],
}) {
  return cashIncome -
      depositedFromDrawer(deposits) -
      pettyCashFromDrawer(pettyCash) -
      selisihBelumDibayar(selisih) +
      selisihLebihDiLaci(selisih);
}

/// Selisih lebih yang uangnya masih ada di laci.
///
/// Ditambahkan karena uangnya memang ADA — itulah artinya berlebih.
/// Kasir menutup shift dengan menghitung uang fisik, jadi kelebihannya
/// nyata di tangan, bukan angka di kertas. Mengabaikannya membuat Saldo
/// Cash menyebut jumlah yang lebih kecil daripada yang bisa dihitung
/// tangan, dan setoran seluruh isi laci jadi melebihi saldonya.
///
/// Yang menentukan bukan "sudah diselesaikan atau belum", melainkan
/// **bagaimana** diselesaikannya — dan ini bagian yang mudah salah:
///
/// - Belum diselesaikan: uangnya di laci, dihitung.
/// - Diakui pendapatan lain-lain: uangnya **tetap di laci**. Yang
///   berubah cuma pengakuannya di pembukuan; tidak ada pesanan yang
///   masuk, jadi tidak ada pemasukan tunai yang menggantikannya. Kalau
///   berhenti dihitung di sini, uang yang benar-benar ada lenyap dari
///   Saldo Cash.
/// - Penjualannya sudah diinput: berhenti dihitung. Pesanan yang
///   barusan dimasukkan sudah membawa uangnya lewat pemasukan tunai,
///   dan menghitungnya lagi di sini berarti uang yang sama dua kali.
///
/// Keduanya keluar dari laci nanti lewat setoran, seperti uang tunai
/// lainnya.
int selisihLebihDiLaci(List<CashVariance> selisih) => selisih
    .where((s) => s.lebih && s.resolution != 'input_penjualan')
    .fold(0, (sum, s) => sum + s.amount);

/// Selisih kurang yang uangnya tidak ada di laci.
///
/// Dikurangkan karena uangnya memang tidak ada di laci. Selama ini
/// angka Saldo Cash menyebut jumlah yang lebih besar daripada yang
/// benar-benar bisa dihitung tangan, dan selisihnya menumpuk diam-diam
/// tanpa satu pun layar yang menyebutkannya.
///
/// Yang sudah dilunasi tidak dikurangkan lagi: uangnya sudah kembali ke
/// laci, dan mengurangkannya dua kali berarti menghukum kasir yang
/// justru sudah membayar.
/// Yang dibayar transfer tetap dikurangkan — selamanya.
///
/// Uang yang hilang dari laci tidak pernah kembali ke laci; yang
/// bertambah rekening merchant, dan itu urusan Saldo Non Cash.
/// Berhenti mengurangkannya di sini berarti Saldo Cash mengaku punya
/// lembaran yang tidak ada di laci mana pun.
int selisihBelumDibayar(List<CashVariance> selisih) => selisih
    .where((s) => !s.lebih && !(s.lunas && !s.dibayarTransfer))
    .fold(0, (sum, s) => sum + s.amount);

/// Selisih kurang yang dilunasi lewat transfer.
///
/// Uangnya mendarat di rekening, jadi ia menambah Saldo Non Cash —
/// sama seperti setoran tunai yang sudah diserahkan ke bank.
int selisihDibayarTransfer(List<CashVariance> selisih) => selisih
    .where((s) => !s.lebih && s.lunas && s.dibayarTransfer)
    .fold(0, (sum, s) => sum + s.amount);

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
