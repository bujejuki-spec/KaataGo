# Catatan Rilis KaataGo

Yang dibacakan ke kotak masuk tiap rilis. Ditulis tangan, bukan
dibangkitkan dari daftar commit — daftar yang ditulis mesin berisi hal
yang tidak dimengerti pembacanya, dan pengumuman yang tidak dimengerti
berhenti dibaca pada rilis berikutnya.

## Dua aturan yang berbeda

**Fitur baru disebut satu per satu.** Poin besar saja, ditulis dari
sudut pandang yang memakai — bukan "menambahkan RPC report_menu_sales",
tapi "laporan menu terlaris untuk Owner dan Admin". Orang berhenti
membaca pengumuman yang tidak memberi tahu apa yang sekarang bisa dia
lakukan.

**Perbaikan bug dirangkum jadi satu baris**, tanpa dirinci:

```
- Perbaikan bug dan penyempurnaan tampilan
```

Merinci bug berarti mengumumkan ke semua orang — termasuk yang tidak
berkepentingan baik — apa saja yang pernah bisa ditembus, dilewati, atau
dibuat berhenti bekerja di aplikasi ini. "Tombol Batal dulu membuat
dialog tidak bisa ditutup" terbaca sebagai keterbukaan; yang dibacanya
adalah peta.

Yang tetap dirinci: perubahan perilaku yang sudah terlanjur dipakai
orang. Kalau sebuah angka sekarang dihitung berbeda, atau sebuah tombol
pindah tempat, itu bukan perbaikan yang disembunyikan — itu hal yang
akan membingungkan kalau tidak diberitahukan.

Rinciannya tetap ditulis lengkap di pesan commit dan di TSD. Yang
dibatasi pengumumannya, bukan catatannya.

Formatnya dibaca `scripts/release.sh`: judul `## <versi>`, lalu
poin-poinnya. Versi yang tidak punya bagiannya di sini tetap terbit,
hanya pengumumannya memakai kalimat umum.

## 3.5.0

- Isi pengumuman di Kotak Masuk kini ditampilkan sebagai daftar berbutir
  yang rapi, tidak lagi patah di tengah kalimat
- Tindakan di List Merchant berkumpul di satu tombol; aktif/nonaktif
  merchant pindah ke dalam form Ubah, berikut konfirmasinya
- Bagian Setoran ke Bank, Pengeluaran Perusahaan, dan Setoran Modal di
  menu Saldo Perusahaan bisa dilipat, dengan tombolnya di ujung judul
- Layar Bayar dengan Transfer menampilkan rekening utama saja
- Kartu Rekening Bank di Saldo & Pengeluaran kini membaca daftar Rekening
  Perusahaan — sebelumnya menampilkan rekening lama yang sudah tidak
  dipakai
- Daftar fitur di Tentang KaataGo disegarkan
- Perbaikan bug dan penyempurnaan tampilan

## 3.4.0

- Setor tunai yang disetujui kini mendarat di Saldo Bank Perusahaan, dan
  cash pickup di Saldo Cash Perusahaan — keduanya berhenti dihitung
  sebagai Saldo Non Cash merchant, supaya uang yang sama tidak muncul di
  dua layar
- Selisih kasir yang dilunasi lewat transfer ikut masuk Saldo Bank
- Top Up Modal pindah ke menu Saldo Perusahaan, tetap memilih masuk ke
  Saldo Cash atau Saldo Bank
- Menu Saldo Perusahaan bisa mencatat pengeluaran yang dibayar dari uang
  perusahaan, dengan akun GL Pengeluaran yang dipilih sendiri; pencatatan
  di Saldo & Pengeluaran kembali khusus Petty Cash
- Selisih lebih yang diakui sebagai pendapatan kini muncul di menu
  Pemasukan, pada tanggal saat diakuinya
- Kartu Penghasilan di Saldo & Pengeluaran dilepas — angkanya sudah
  terbaca dari Saldo Cash dan Saldo Non Cash di atasnya
- Perbaikan bug dan penyempurnaan tampilan

## 3.3.0

- Penjualan QRIS, QRIS Statis, dan Transfer kini masuk ke Saldo Bank
  setiap jam 5 pagi WIB, bukan seketika — mengikuti kenyataan bahwa
  uangnya baru cair belakangan dari penyedia pembayaran
- Top up modal di merchant memilih kantongnya: masuk ke Saldo Cash atau
  Saldo Bank, sesuai cara uangnya diserahkan
- GL Setoran Modal tidak lagi dipetakan di merchant; setoran modal
  langsung mendarat di salah satu saldo perusahaan
- Saldo Non Cash berhenti menghitung pelunasan selisih kasir lama setiap
  hari; yang dihitung kini hanya pelunasan pada hari yang dilihat
- Menu atau kelompok menu yang disembunyikan tidak lagi meninggalkan
  jarak kosong di beranda
- Perbaikan bug dan penyempurnaan tampilan

## 3.2.0

- Menu baru Saldo Perusahaan untuk Finance dan Owner: uang tunai yang
  dipegang dan uang di rekening, masing-masing dengan saldonya sendiri,
  berikut tombol setor dari kas ke bank
- Pengeluaran kini menyebut sumber dananya — Petty Cash, Saldo Cash, atau
  Saldo Bank — dan kantong yang dipilih itu yang berkurang
- Saldo & Pengeluaran kini menampilkan hari ini untuk semua peran; angka
  perusahaan seluruhnya pindah ke menu Saldo Perusahaan
- Jurnal GL kini punya pilihan periode, dan yang dicetak mengikuti
  periode yang sedang dilihat
- Periode Jurnal GL dan Laporan Transaksi dibatasi satu bulan sekali
  ambil, supaya datanya tidak keberatan
- Di Billing Merchant, merchant yang punya tagihan belum dibayar ditandai
  angka merah
- GL Saldo Bank Perusahaan bisa dipetakan sendiri di Mapping GL Account
- Perbaikan bug dan penyempurnaan tampilan

## 3.1.0

- Rekening KaataGo kini punya menunya sendiri di KaataGo Admin — rekening
  tujuan transfer tagihan langganan merchant bisa ditambah dan diubah di
  sana, dan merchant yang ditagih lewat transfer benar-benar melihat
  nomornya
- GL Cash Pickup dan GL Saldo Cash Perusahaan bisa dipetakan sendiri di
  Mapping GL Account
- Arah debit dan kredit pada jurnal cash pickup diperbaiki, dan pickup
  yang ditolak kini dikembalikan dari GL Cash Pickup — bukan dari GL
  Suspense Setoran, yang tidak pernah menerima uang itu
- Setoran tunai kembali singgah di GL Suspense Setoran sampai Finance
  menyetujuinya
- Cash pickup tidak lagi dikonfirmasi atau ditolak dari layar Setor Saldo
  Cash; serah terimanya hanya di menu Terima Cash Pickup
- Menu Terima Cash Pickup menampilkan bukti yang diunggah kasir, dan
  kolom jumlah diterima dikosongkan supaya diisi dari uang yang
  benar-benar dihitung
- Perbaikan bug dan penyempurnaan tampilan

## 2.40.0

- Akses Menu (UAM) di KaataGo Admin: menu yang muncul dan yang boleh
  diubah kini diatur per merchant dan per peran — Tidak Ada, Lihat, atau
  Lihat & Ubah. Merchant yang belum diatur tidak berubah sama sekali
- Kelompok menu yang seluruh isinya dicabut ikut hilang, bukan
  meninggalkan pintu menuju halaman kosong
- Layar Pelanggan kini menampilkan rincian pesanan untuk semua cara
  bayar: tunai menampilkan ringkasan dan totalnya, QRIS Statis
  menampilkan QR merchant untuk dipindai, dan transfer menampilkan
  rekening tujuannya
- Kasir hanya melihat shift dan selisih atas namanya sendiri; shift orang
  lain tidak lagi terbaca dari perangkatnya
- Laci yang sedang dipegang orang lain terbaca sebagai aturan di kartu
  shift, bukan sebagai galat setelah tombol Buka Shift ditekan
- Tutup Buku kini bisa diakses Admin
- Terima Cash Pickup untuk Finance dan Owner: uang yang dijemput petugas
  singgah di GL Cash Pickup sampai serah terimanya selesai, lalu masuk ke
  GL Saldo Cash Perusahaan. Nomor segel, jumlah yang diterima, nama
  petugas, dan bukti terimanya dicatat
- Nomor rekening di dialog Setor Bank bisa disalin sekali ketuk
- Rekening merchant tidak lagi tampil dua kali di Info Pembayaran dan
  Pengaturan Pembayaran; semuanya membaca daftar Rekening Perusahaan
- Pesanan yang belum dibayar hangus setelah 10 menit, bukan 30 — stok
  yang dipesan kembali bisa dijual jauh lebih cepat
- Perbaikan bug dan penyempurnaan tampilan

## 2.39.0

- Owner dan Finance kini benar-benar bisa menambah rekening perusahaan;
  sebelumnya penyimpanannya ditolak dan hanya berhasil untuk Super Admin
- Nomor rekening yang sudah terdaftar dikenali dan dipakai ulang, bukan
  ditolak sebagai duplikat tanpa penjelasan
- Saldo & Pengeluaran untuk Kasir dan Admin kini menampilkan hari ini
  saja. Saldo Cash dan sisa Petty Cash tetap dihitung utuh — keduanya
  uang yang sedang dipegang, dan isinya tidak ikut berganti hari
- Perbaikan bug dan penyempurnaan tampilan

## 2.38.0

- Tutup buku harian: satu hari dikunci angkanya setelah diperiksa, dan
  koreksi yang datang belakangan terlihat sebagai selisih, bukan
  diam-diam mengubah angka yang sudah ditandatangani
- Rekonsiliasi mutasi bank: setoran dan pembayaran yang belum punya
  pasangan di rekening ditampilkan sendiri, dan bisa dicocokkan atau
  dilepas lagi kalau keliru
- Rekening perusahaan jadi data tersendiri — satu rekening bisa dipakai
  beberapa resto, dan nama banknya dipilih dari daftar, bukan diketik
- Setor bank kini dimulai dari nomor rekening; nama pemilik dan banknya
  mengikuti sendiri, dan bukti transfernya wajib dilampirkan
- Cash Pickup: nominal, catatan, nama yang menjemput, bukti, dan nomor
  seal kalau ada
- Penagihan langganan bisa diatur per merchant dari KaataGo Admin —
  Virtual Account atau transfer ke rekening KaataGo, yang nomornya
  tampil dan bisa disalin saat merchant membayar
- Pengingat tagihan lewat WhatsApp dan surel kini menyebut nominalnya
  berikut nomor VA atau nomor rekening tujuannya
- Bukti pembayaran tagihan wajib diunggah sebelum tagihannya diperiksa
- Perbaikan bug dan penyempurnaan tampilan

## 2.37.0

- QRIS Statis kini bisa dipilih juga saat melunasi pesanan di Pending
  Payment, bukan hanya di kasir
- Nama merchant, rekening, dan info pembayaran lain diambil dari data
  merchantnya — perangkat baru tidak lagi menampilkan "Toko Kamu" di
  layar QRIS dan Transfer
- Perbaikan bug dan penyempurnaan tampilan

## 2.36.0

- Metode pembayaran kini bisa dipilih merchant di Info Pembayaran —
  Tunai, QRIS Dinamis, QRIS Statis, dan Transfer. Yang dimatikan tidak
  lagi ditawarkan, baik di kasir maupun di HP pelanggan
- QRIS Statis: unggah QR cetak milik merchant sendiri, dan kasir
  menunjukkannya ke pelanggan. Gambarnya diperiksa dulu — yang bukan
  QRIS ditolak, dan nama merchant di dalamnya ditunjukkan sebelum
  dipasang
- Pesanan pelanggan yang memilih QRIS Statis masuk ke Pending Payment
  dan dilunasi di kasir, sama seperti tunai — QR statis tidak membawa
  nominal, jadi jumlahnya perlu dicocokkan
- QRIS lama kini bernama QRIS Dinamis, dan punya akun GL sendiri
  terpisah dari QRIS Statis. Yang statis tidak pernah masuk hitungan
  pencairan gateway karena uangnya langsung ke rekening merchant
- Kotak pencarian di List Merchant, Kelola Karyawan, dan kedua tab
  Billing
- Tab Tagihan dikelompokkan per merchant; yang punya tagihan menunggu
  diperiksa berada di atas
- Perbaikan bug dan penyempurnaan tampilan

## 2.35.0

- Email merchant kini bisa diisi Owner dan Admin lewat Info Merchant,
  tidak lagi hanya oleh KaataGo Admin
- Nomor HP wajib juga di Info Merchant, sama seperti di sisi KaataGo
  Admin
- List Merchant dirapikan: nama, alamat, dan ikon WhatsApp saja
- Perbaikan bug dan penyempurnaan tampilan

## 2.34.0

- Owner dan Admin merchant kini bisa menambah, mengubah, dan
  menonaktifkan karyawan sendiri — terbatas pada merchant yang dipetakan
  ke mereka, dan tidak bisa mengangkat KaataGo Admin
- Kelola Produk punya kotak pencarian dan dikelompokkan per kategori
- Ukuran foto di daftar menu kini seragam, tidak lagi ikut memendek pada
  menu yang keterangannya lebih panjang
- Nomor HP jadi wajib di Info Merchant — dipakai KaataGo untuk
  menghubungi merchant soal tagihan dan kendala
- Analisa Pasar: merchant yang belum ada penghasilan bisa langsung
  dihubungi lewat WhatsApp
- Tagihan yang belum jatuh tempo otomatis dibatalkan kalau tanggal
  tagihnya diubah, jadi nomornya tidak menggantung terbuka. Tunggakan
  yang sudah lewat jatuh tempo tidak ikut dibatalkan
- Topping yang dipilih kini terlihat di keranjang, lembar varian, dan
  checkout — bukan cuma ikut terhitung di harganya
- Perbaikan bug dan penyempurnaan tampilan

## 2.33.0

- KaataGo Admin bisa menghubungi merchant lewat WhatsApp langsung dari
  List Merchant — tombolnya muncul kalau nomornya sudah diisi
- Email merchant kini bisa disimpan dan tampil di List Merchant, di
  sebelah nomor HP-nya
- Tagihan langganan yang belum dibayar bisa dikirim ke merchant lewat
  WhatsApp atau email, lengkap dengan nama resto, periode, nominal, dan
  jatuh temponya
- Pemindahan foto menu kini menampilkan kemajuannya sambil berjalan,
  berikut notifikasi seperti unduhan pembaruan — jadi tidak perlu
  ditunggui di layar
- Perbaikan bug dan penyempurnaan tampilan

## 2.32.0

- Pesanan QRIS yang tidak dibayar dalam 30 menit kini ikut dibatalkan
  sendiri, sama seperti pesanan bayar-di-kasir. Stoknya kembali bisa
  dijual
- Pelanggan diberi tahu sisa waktunya di layar pembayaran — baik QRIS
  maupun bayar di kasir — berikut keterangan bahwa pesanannya akan
  dibatalkan kalau lewat
- Pembayaran yang terlanjur masuk setelah pesanannya hangus tidak lagi
  hilang begitu saja; pesanannya dibangkitkan kembali jadi lunas
- Perbaikan bug dan penyempurnaan tampilan

## 2.31.0

- Melampirkan foto kini jalan juga dari konsol web — bukti setoran, nota
  pengeluaran, banner promo dan voucher, foto pengaduan dan chat
  Support, gambar pengumuman, ulasan merchant, bukti bayar tagihan, dan
  foto menu. Sebelumnya semuanya hanya bisa dari HP
- Perbaikan bug dan penyempurnaan tampilan

## 2.30.0

- Buka dan tutup shift kini dibandingkan dengan Saldo Cash merchant,
  bukan lagi dengan tutup shift sebelumnya. Angka yang dipakai sama
  persis dengan yang tampil di Saldo & Pengeluaran
- Modal awal yang diketik tidak lagi jadi dasar perhitungan shift-shift
  berikutnya, jadi satu salah ketik tidak lagi terbawa terus
- Angka yang seharusnya tetap tidak ditampilkan sebelum kasir selesai
  menghitung, dan masih bisa diperbaiki sebelum shift disimpan
- Perbaikan bug dan penyempurnaan tampilan

## 2.29.0

- Stok sekarang benar-benar menahan pesanan: kalau sisa satu dan dua
  orang memesan bersamaan, yang tercepat berhasil dan yang lain ditolak
  dengan menyebut nama barangnya. Produk yang stoknya menyentuh nol
  otomatis ditandai habis
- Produk yang stoknya tidak diisi tidak terpengaruh sama sekali dan
  tidak pernah ditolak
- Pesanan yang dibatalkan atau hangus mengembalikan stoknya
- Aplikasi jadi jauh lebih ringan dibuka: layar Pesanan Masuk, dapur,
  dan notifikasi tidak lagi mengunduh seluruh riwayat pesanan merchant
  tiap kali dibuka
- Riwayat Kasir kini dimuat bertahap dengan tombol "Muat transaksi
  lebih lama" — tidak ada transaksi yang hilang, hanya diambil saat
  diminta
- Foto menu pindah ke penyimpanan berkas, lewat tombol baru
  "Pindahkan foto menu" di Kelola Produk. Menu jadi lebih cepat terbuka
  buat pelanggan
- Perbaikan bug dan penyempurnaan tampilan

## 2.28.0

- Unduhan pembaruan kini berjalan di layanan latar: ia terus jalan saat
  layar dikunci atau kamu pindah ke aplikasi lain, dan aplikasi yang
  dibuka lagi menyambung kemajuannya
- Tombol Jeda kembali ada, dan sekarang benar-benar melanjutkan dari
  byte terakhir alih-alih mengulang dari nol
- Notifikasi unduhan bisa diketuk untuk langsung membuka layar pemasang
  begitu berkasnya selesai
- Perbaikan bug dan penyempurnaan tampilan

## 2.27.0

- Unduhan pembaruan sekarang berjalan terus meskipun aplikasinya
  ditutup atau HP-nya dikunci, dan menyambung sendiri saat sinyal putus
  lalu kembali. Kemajuannya terlihat di notifikasi, dan mengetuknya
  membuka layar pemasang
- Tombol Jeda tidak lagi ada di Android: unduhannya kini dipegang
  sistem, yang tidak menyediakan cara menjeda — tapi juga tidak lagi
  menghanguskan unduhan saat kamu berpindah aplikasi
- Tunai di Laci di Setor Saldo Cash kini memakai perhitungan yang sama
  persis dengan Saldo Cash, termasuk selisih shift kasir. Sebelumnya
  kedua layar bisa menampilkan angka berbeda
- Perbaikan bug dan penyempurnaan tampilan

## 2.26.0

- Kasir yang masih punya selisih kurang belum bisa membuka shift baru
  sebelum melunasinya — alasannya tertulis di kartu Shift Kasir, bukan
  muncul sebagai galat setelah tombolnya ditekan
- Selisih lebih tidak menahan siapa pun; uangnya ada di laci dan yang
  menelusurinya Finance
- Membuka shift sekarang khusus Kasir, Admin, dan Owner. Finance tetap
  membaca riwayat dan menutup selisih, tapi tidak lagi memegang laci
- Perbaikan bug dan penyempurnaan tampilan

## 2.25.0

- Selisih lebih saat tutup shift kini jadi pekerjaan yang bisa
  diselesaikan, bukan cuma angka yang lewat — Owner dan Finance memilih
  "penjualannya sudah diinput" atau "akui pendapatan lain-lain"
- Uang kelebihan di laci ikut dihitung Saldo Cash, supaya angkanya sama
  dengan yang benar-benar bisa dihitung tangan
- Bayar selisih kurang bisa tunai atau transfer — yang transfer masuk
  ke Saldo Non Cash, bukan kembali ke laci
- Setoran tunai sekarang terlihat di Saldo Non Cash, jadi Saldo Cash
  dan Non Cash berjumlah sama dengan Penghasilan
- Akun baru GL Pendapatan Lain-lain di Mapping GL Account
- Perbaikan bug dan penyempurnaan tampilan

## 2.24.0

- QR Meja untuk banyak meja sekaligus bisa dimulai dari nomor berapa
  pun, bukan selalu dari 1 — berguna saat menambah meja di lantai dua
- Perbaikan bug dan penyempurnaan tampilan

## 2.23.0

- Tombol lokasi merchant langsung membuka aplikasi peta di HP, tidak
  lagi lewat halaman peramban yang sering terbuka kosong
- Perbaikan bug dan penyempurnaan tampilan

## 2.22.0

- Alamat email karyawan boleh sampai 40 karakter — yang panjang tidak
  lagi ditolak saat didaftarkan di Kelola Karyawan
- Perbaikan bug dan penyempurnaan tampilan

## 2.21.0

- QR meja sekarang berisi tautan, jadi pelanggan bisa memindainya
  dengan kamera bawaan HP dan langsung memesan lewat web — tanpa
  memasang aplikasi. Cetak ulang QR mejamu dari menu QR Meja — yang
  lama tetap bisa dipindai dari dalam aplikasi, tapi tidak membuka web
- Konsol web KaataGo untuk Owner, Admin, Finance, dan KaataGo Admin:
  menunya di sidebar kiri, dibuka dari peramban di PC
- Kelola Produk dan Kategori tampil sebagai kartu, seperti Level
- Tombol Batal di dialog Top Up Saldo, hapus voucher, kirim bukti
  bayar, dan kelola karyawan pindah ke bawah tombol utamanya
- Tombol Simpan di Saldo & Pengeluaran memakai warna yang sama dengan
  tombol simpan lainnya
- Keterangan di Kirim Pengumuman dan Banner Promo terbaca di tema gelap
- Di tablet, popup tidak lagi melebar hampir selebar layar
- Perbaikan bug dan penyempurnaan tampilan

## 2.20.0

- Pesanan yang dibatalkan atau hangus tidak lagi menampilkan struk —
  tidak ada pembayaran yang bisa dibuktikan di sana
- Perbaikan bug dan penyempurnaan tampilan

## 2.19.0

- Notifikasi KaataGo Support kini muncul juga saat aplikasinya sedang
  dibuka — kecuali untuk percakapan yang sedang kamu baca
- Penanda pesan baru dipisah: chat punya angkanya sendiri, pengaduan
  punya angkanya sendiri
- Notifikasi chat tidak lagi berjudul "pengaduan"
- Perbaikan bug dan penyempurnaan tampilan

## 2.18.0

- Chat KaataGo Admin dipisah tegas dari pengaduan — tanpa status, tanpa
  penutupan otomatis, dan punya tabnya sendiri di sisi KaataGo Admin
- Penanda unduhan pembaruan bisa diketuk lagi, dan popupnya punya Jeda,
  Batalkan, dan Tutup
- Unduhan yang dijeda dilanjutkan dari titik terakhir, bukan diulang
  dari nol
- Perbaikan bug dan penyempurnaan tampilan

## 2.17.0

- Pengaduan dan chat baru langsung dibalas sapaan, supaya jelas
  pesannya sampai dan sedang menunggu giliran
- Percakapan KaataGo Support urut seperti aplikasi chat pada umumnya —
  yang terbaru di paling bawah
- Perbaikan bug dan penyempurnaan tampilan

## 2.16.0

- Chat KaataGo Admin: pilihan baru di KaataGo Support untuk sekadar
  bertanya, tanpa harus membuat pengaduan
- Balasan KaataGo Admin menyebut nama penjawabnya
- KaataGo Admin bisa melihat pengaduan ini datang dari pelanggan atau
  dari merchant mana
- Tombol KaataGo Support jadi lebih kecil dan tidak lagi menutupi menu
- Perbaikan bug dan penyempurnaan tampilan

## 2.15.0

- KaataGo Support: tombol mengambang untuk mengadu langsung ke KaataGo,
  lengkap dengan tiket, status, dan percakapannya
- Status pengaduan Open, On Progress, Confirm Customer, dan Close —
  pengadu bisa menutup sendiri kalau masalahnya sudah selesai
- Pengaduan yang menunggu tanggapan lebih dari 24 jam ditutup sendiri
- Menu Customer Service untuk KaataGo Admin, berisi seluruh percakapan
  yang masuk
- Notifikasi saat pengaduan dibalas atau statusnya bergerak, dan diketuk
  langsung membuka percakapannya
- Perbaikan bug dan penyempurnaan tampilan

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
