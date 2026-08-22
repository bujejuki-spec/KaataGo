# Catatan Rilis KaataGo

Yang dibacakan ke kotak masuk tiap rilis. Ditulis tangan, bukan
dibangkitkan dari daftar commit — daftar yang ditulis mesin berisi hal
yang tidak dimengerti pembacanya, dan pengumuman yang tidak dimengerti
berhenti dibaca pada rilis berikutnya.

Aturannya: poin besar saja, ditulis dari sudut pandang yang memakai.
Bukan "memperbaiki PageStorageKey pada ExpansionTile", tapi "menu tidak
lagi berkedip saat digulir".

Formatnya dibaca `scripts/release.sh`: judul `## <versi>`, lalu
poin-poinnya. Versi yang tidak punya bagiannya di sini tetap terbit,
hanya pengumumannya memakai kalimat umum.

## 2.10.0

- Menu bisa diberi label BARU, TERLARIS, dan REKOMENDASI lewat Kelola
  Produk — labelnya tampil di layar kasir maupun di HP pelanggan
- Label DISKON muncul sendiri selama promonya berjalan, dan hilang
  sendiri saat promonya habis
- Pelanggan bisa menilai tiap menu yang pernah dipesannya, lewat tombol
  Nilai Menu di Riwayat Saya
- Bintang dan angka terjual tiap menu tampil di kartu menunya
- Ulasan menu bisa dibaca di Info Merchant, dikelompokkan per menu
- Menu baru Shift Kasir: buka shift dengan modal awal laci, tutup shift
  dengan menghitung uangnya, dan selisihnya langsung ketahuan hari itu
- Formulir Diskon Baru ditata ulang — daftar menu pindah ke halaman
  sendiri yang bisa dicari
- Nama merchant di kartu QR meja tidak lagi samar di mode gelap

## 2.9.4

- Voucher, diskon langganan, dan Voucher Saya dipisah antara yang masih
  berlaku dan yang sudah lewat
- Fasilitas merchant tampil sampai tepi kartu, sisanya di balik "+N"
- Merchant yang tutup tidak lagi muncul di saran terdekat
- Foto ulasan bisa dilihat selayar penuh
- Logo KaataGo di invoice langganan
- KaataGo tidak lagi muncul dua kali di Recent Apps

## 2.9.3

- Bintang merchant muncul langsung di daftar pilih merchant
- Fasilitas ditampilkan menyamping — tiga terlihat, sisanya di balik
  "+N" yang bisa diketuk

## 2.9.2

- Pesanan yang dibatalkan tidak lagi berstatus "Sedang Dimasak" atau
  "Menunggu Diproses", termasuk di Riwayat Pesanan

## 2.9.1

- Foto di ulasan bisa diketuk untuk dilihat selayar penuh
- Layar pelanggan menampilkan logo merchant dan tanda powered by KaataGo

## 2.9.0

- Kasih ulasan untuk merchant: bintang, komentar, dan foto — muncul di
  daftar pilih merchant dan di halaman Info Merchant
- Info Merchant baru: alamat, nomor telepon, fasilitas, jam buka, dan
  apa kata pelanggan lain
- Jam buka per hari, diatur merchant sendiri — yang sedang tutup
  ditandai dan turun ke bawah daftar
- Sejam sesudah bayar, KaataGo mengajak kamu menilai tempatnya
- Merchant bisa membaca seluruh penilaian yang masuk

## 2.8.1

- Jarak tombol Keluar di menu utama disamakan dengan tombol lainnya

## 2.8.0

- Kata "resto" diganti "merchant" — KaataGo tidak lagi hanya untuk
  rumah makan
- Nomor pesanan harian di tiap merchant, mulai dari 1 tiap hari — muncul
  sejak pesanan dibuat, bahkan saat pembayarannya masih menunggu
- Cari menu di halaman pesan, untuk kasir maupun pelanggan
- Fasilitas merchant (AC, Smoking Area, Live Music, dan lainnya) tampil
  saat pelanggan memilih tempat
- Halaman FAQ dan tombol chat langsung ke KaataGo Admin di Tentang
  KaataGo
- Peran Super Admin kini bernama KaataGo Admin
- Layar Pelanggan: buka KaataGo di perangkat kedua yang menghadap
  pelanggan, QR dan totalnya tampil di sana
- Notifikasi yang diketuk langsung membuka halaman yang dimaksud
- Menu tidak lagi berkedip, dan kategori yang dilipat tidak membuka
  sendiri
- Banner promo mengikuti ukuran gambarnya, tanpa pita di tepinya
- Banner yang masa berlakunya habis berhenti tampil ke pelanggan, tapi
  tetap ada di pengelolanya untuk dihapus sendiri

## 2.7.0

- Super Admin dan Owner yang belum memilih cabang kini menerima
  notifikasi
- Pengumuman untuk pelanggan tidak lagi membangunkan karyawan, dan
  sebaliknya

## 2.6.3

- Menu pelanggan tidak lagi memuat selamanya sesudah ditutup dan dibuka
  lagi

## 2.6.0

- Keranjang tampil sebagai panel di samping menu pada tablet
- Popup menu tidak lagi menutupi keranjang
- Halaman pembayaran bisa digulir penuh di layar pendek
- Tagihan langganan bisa diunduh sebagai invoice PDF
