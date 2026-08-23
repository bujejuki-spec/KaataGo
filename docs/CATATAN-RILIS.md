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

## 2.14.0

- Modal awal saat buka shift ikut diperiksa — kalau tidak cocok dengan
  yang ditinggalkan shift sebelumnya, nominalnya masih bisa diperbaiki
- Shift yang selisihnya sudah dibayar berbunyi "Pas", lengkap dengan
  rincian nominal, selisih, dan siapa yang membayarnya
- GL Selisih Kasir bisa dipetakan sendiri di Mapping GL Account
- Tombol simpan banner promo tidak lagi berputar selamanya saat
  tanggalnya ditolak
- Jarak tombol Shift Kasir di beranda Owner disamakan dengan lainnya

## 2.13.0

- Laporan Penjualan untuk Owner dan Admin: menu terlaris, menu yang
  tidak laku sama sekali, jam ramai, dan ringkasan omzetnya
- Selisih shift kasir sekarang masuk pembukuan lewat GL Selisih Kasir,
  dan jadi tagihan terbuka sampai dilunasi
- Menu Bayar Selisih untuk Owner, Finance, dan Admin — kasir bisa
  melihat tagihannya sendiri, tapi tidak menutupnya
- Saldo Cash ikut dikurangi selisih yang belum dibayar, supaya angkanya
  sama dengan uang yang benar-benar bisa dihitung tangan
- Alamat surel KaataGo ada di Tentang KaataGo dan di landing page

## 2.12.0

- Menu yang dipesan lagi bisa dinilai lagi — penilaian menempel pada
  pesanannya, bukan pada menunya
- Ajakan menilai hilang setelah seluruh menu di pesanan itu dinilai
- Bintang menu langsung muncul di kartu menu setelah dinilai
- Tombol Batal di semua dialog tidak lagi memunculkan pesan galat
- Saat menutup shift, selisihnya ditunjukkan lebih dulu dan nominalnya
  masih bisa diperbaiki sebelum disimpan

## 2.11.0

- Foto menu tidak lagi hilang setelah pesanan masuk
- Satu menu bisa didiskon di beberapa bagian sekaligus — centang topping
  dan tambahan ukuran mana saja yang ikut dipotong
- Pilihan baru "Harga menu utama": memotong harga menunya saja, tanpa
  ikut memotong topping yang ditambahkan pemesan
- Menu berlabel DISKON, saat diketuk, menjelaskan promonya — berapa
  potongannya, syaratnya, dan menu apa saja yang harus dibeli bersama
- Shift Kasir naik ke halaman utama, tidak lagi di dalam grup Keuangan

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
