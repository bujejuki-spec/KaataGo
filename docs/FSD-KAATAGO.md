# KaataGo — Functional Specification Document

**Versi Aplikasi:** 1.45.4 (build 92)
**Versi Dokumen:** 2.0
**Tanggal Terbit:** 16 Agustus 2026
**Status:** Rilis
**Jenis Dokumen:** FSD — sisi fungsional

Dokumen ini menjelaskan **apa** yang dilakukan KaataGo: siapa memakainya,
proses apa yang dijalankan, aturan apa yang berlaku, dan hasil apa yang
diharapkan. Sisi teknisnya — arsitektur, tabel, kebijakan keamanan baris
— ada di dokumen terpisah (`SPESIFIKASI-KAATAGO`).

Isinya diambil dari aplikasi yang berjalan, bukan dari rencana. Setiap
perbedaan antara dokumen ini dan aplikasinya adalah temuan yang layak
dilaporkan.

---

## Daftar Isi

1. Ruang Lingkup
2. Peran Pengguna
3. Proses Bisnis Utama
4. Kebutuhan Fungsional per Modul
5. Aturan Bisnis
6. Aturan Validasi Isian
7. Daftar Status
8. Notifikasi
9. Kriteria Penerimaan
10. Batasan yang Diketahui
11. Lampiran A — Tangkapan Layar

---

## 1. Ruang Lingkup

KaataGo adalah aplikasi kasir sekaligus pemesanan mandiri untuk rumah
makan di Indonesia. Satu aplikasi melayani dua kelompok yang sangat
berbeda: **pelanggan**, yang memesan dari HP sendiri, dan **karyawan
resto** — kasir, dapur, admin, keuangan, pemilik — yang masing-masing
melihat menu berbeda begitu masuk.

### 1.1 Yang termasuk

| Bidang | Cakupan |
|---|---|
| Pemesanan | Pesan mandiri dari HP pelanggan (scan QR meja atau pilih resto), dan input pesanan oleh kasir |
| Pembayaran | QRIS, Tunai, Transfer; pelanggan boleh memilih bayar tunai di kasir |
| Dapur | Antrean masak per status, centang per menu |
| Keuangan | Pemasukan, pengeluaran, petty cash, setoran tunai, jurnal GL otomatis |
| Katalog | Produk, kategori, level/varian, stok, banner promo |
| Organisasi | Karyawan, banyak resto per akun, QR meja |
| Komunikasi | Kotak masuk pengumuman bersasaran, notifikasi push |
| Promo | Diskon per menu, bundling, minimum belanja; banner promo bermasa berlaku |
| Tampilan | Mode terang, gelap, atau mengikuti setelan HP |

### 1.2 Yang tidak termasuk

| Hal | Keterangan |
|---|---|
| Bahasa Inggris | Mekanismenya sudah ada tapi terjemahannya belum lengkap, jadi pemilih bahasanya **dimatikan**. Seluruh antarmuka berbahasa Indonesia |
| Pencocokan mutasi bank | Transfer dan setoran dipastikan manual oleh Finance |
| Aplikasi iOS | Rilis saat ini hanya Android |
| Pengiriman/kurir | Take Away berarti diambil sendiri |

---

## 2. Peran Pengguna

Login karyawan **hanya lewat Google Sign-In**, dan alamatnya harus sudah
terdaftar. Pelanggan boleh memesan **tanpa akun sama sekali**.

| Peran | Tugas utamanya |
|---|---|
| **Customer** | Memesan dari HP sendiri, membayar, memantau status pesanannya |
| **Kasir** | Menerima pesanan di konter, menerima pembayaran, menyetor tunai |
| **Chef** | Menjalankan antrean dapur |
| **Admin** | Katalog, karyawan, pengaturan resto, QR meja, pengumuman resto |
| **Finance** | Memutuskan setoran & petty cash, pemetaan GL, laporan |
| **Owner** | Seluruh menu di restonya, dan berpindah antar cabang |
| **Super Admin** | Seluruh resto, dan pengumuman versi aplikasi |

### 2.1 Matriks akses menu

| Menu | Super Admin | Owner | Admin | Kasir | Chef | Finance | Customer |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Kasir / Input Pesanan | – | ✔ | ✔ | ✔ | – | – | – |
| Pesanan Masuk | – | ✔ | ✔ | – | – | – | – |
| Layar Dapur | – | ✔ | – | – | ✔ | – | – |
| Pending Payment | – | ✔ | ✔ | ✔ | – | – | – |
| Riwayat Transaksi | – | ✔ | ✔ | ✔ | – | – | – |
| Pemasukan | – | ✔ | – | – | – | ✔ | – |
| Saldo & Pengeluaran | – | ✔ | ✔ | ✔ | – | ✔ | – |
| Setor Saldo Cash | – | ✔ | ✔ | ✔ | – | ✔ | – |
| Mapping GL Account | – | ✔ | – | – | – | ✔ | – |
| Jurnal GL | – | ✔ | – | – | – | ✔ | – |
| Laporan Transaksi | – | ✔ | – | – | – | ✔ | – |
| Kelola Produk | – | ✔ | ✔ | – | – | – | – |
| Pengaturan Resto & QR Meja | – | ✔ | ✔ | – | – | – | – |
| Pengaturan Pembayaran | – | ✔ | – | – | – | ✔ | – |
| Kelola Karyawan | ✔ | ✔ | ✔ | – | – | – | – |
| List Resto | ✔ | – | – | – | – | – | – |
| Kirim Pengumuman | ✔ | ✔ | ✔ | – | – | – | – |
| Kotak Masuk | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | – |
| Pesan / Profil / Riwayat | – | – | – | – | – | – | ✔ |

### 2.2 Pemisahan wewenang

> **Yang mengajukan tidak boleh menyetujui.** Kasir dan Admin
> **mengajukan** setoran tunai dan top up petty cash. Finance dan Owner
> yang **memutuskan**. Aturan ini berlaku mutlak: tombolnya tidak muncul
> di aplikasi, dan permintaannya ditolak di sisi server sekalipun
> dipaksakan.

> **Pengumuman versi aplikasi hanya dari Super Admin.** Admin resto boleh
> mengirim pengumuman umum untuk restonya sendiri, tapi tidak
> pemberitahuan versi — dia tidak punya cara mengetahui versi mana yang
> sebenarnya sudah dirilis.

---

## 3. Proses Bisnis Utama

### 3.1 Pelanggan pesan sendiri — bayar QRIS

![Alur pesan sendiri — bayar QRIS](gambar/alur-01-qris.png)

### 3.2 Pelanggan pesan sendiri — bayar tunai di kasir

![Alur pesan sendiri — bayar tunai di kasir](gambar/alur-02-tunai-kasir.png)

Pesanannya **selesai dibuat saat itu juga** dan langsung diteruskan ke
dapur. Yang tertunda hanya uangnya. Pelanggan diberi nomor pesanan dan
diarahkan ke kasir; kasir menyelesaikannya lewat menu Pending Payment.

### 3.3 Setor saldo tunai

![Alur setor saldo tunai dan persetujuannya](gambar/alur-03-setor.png)

### 3.4 Top up petty cash

![Alur top up petty cash dan persetujuannya](gambar/alur-04-petty.png)

Perbedaannya dengan setoran tunai: perantaranya **GL Suspense Petty
Cash**, tombolnya berbunyi *Setuju*/*Tolak* (setoran: *Konfirmasi*/
*Tolak*), dan top up yang dibuat Finance sendiri langsung berstatus
selesai — tidak ada gunanya menyetujui permintaan sendiri.

### 3.5 Alur dapur

![Alur status dapur](gambar/alur-05-dapur.png)

---

## 4. Kebutuhan Fungsional per Modul

### 4.1 Pemesanan Mandiri (Customer)

| ID | Kebutuhan |
|---|---|
| F-CU-01 | Pelanggan dapat memesan tanpa akun (tamu) maupun dengan akun Google |
| F-CU-02 | Masuk ke menu resto lewat scan QR meja **atau** memilih resto dari daftar |
| F-CU-03 | Scan QR meja mengisi nomor mejanya otomatis dan menguncinya |
| F-CU-04 | Memilih level/varian dan menuliskan catatan per menu |
| F-CU-05 | Satu produk dengan varian berbeda menjadi **baris terpisah** di keranjang |
| F-CU-06 | Menu yang telanjur ditambahkan dapat dihapus atau diubah dari keranjang |
| F-CU-07 | Memilih **Dine In** atau **Take Away**; Take Away tidak meminta nomor meja |
| F-CU-08 | Nama pemesan wajib diisi pada kedua jenis |
| F-CU-09 | Memilih cara bayar: **QRIS** atau **Tunai** (bayar di kasir) |
| F-CU-10 | Ringkasan tagihan menampilkan subtotal, biaya service, PPN, dan total |
| F-CU-11 | Memantau status pesanannya secara langsung tanpa perlu menyegarkan |
| F-CU-12 | Melihat riwayat pesanan; tamu tetap melihat riwayat dari perangkatnya |
| F-CU-13 | Riwayat tamu berpindah ke akunnya saat pertama kali login |
| F-CU-14 | Mengatur nama, nomor HP, dan foto profil; foto dapat **dihapus** |
| F-CU-15 | Melihat lokasi resto dan membukanya di Google Maps |
| F-CU-16 | Melihat banner promo resto **utuh, tidak terpotong**, dan ikut tergulir bersama daftar menu |
| F-CU-17 | Diskon yang sedang berlaku ikut dihitung pada pesanan mandiri, berikut nama promonya |
| F-CU-18 | Pesanan yang belum dibayar dapat **dibatalkan sendiri** dari Pesanan Saya maupun Riwayat |
| F-CU-19 | Pesanan tunai yang tidak dilunasi dalam **30 menit** hangus otomatis, dengan hitungan mundur di layar |
| F-CU-20 | Kotak Masuk di menu utama berisi promo resto yang pernah dipesan, berikut **nama restonya** |
| F-CU-21 | Menu yang ditandai habis tetap tampil dengan tanda, tapi tidak bisa dipesan |
| F-CU-22 | Ketersediaan diperiksa **ulang saat hendak membayar**; menu yang keburu habis harus dihapus dulu |
| F-CU-23 | Pilihan Dine In / Take Away hanya muncul untuk cara makan yang dilayani resto itu |
| F-CU-24 | Mengatur tampilan terang, gelap, atau mengikuti setelan HP |

### 4.2 Kasir

| ID | Kebutuhan |
|---|---|
| F-KS-01 | Memilih produk dari daftar per kategori, dengan stok berkurang saat checkout |
| F-KS-02 | Menerima pembayaran Tunai, QRIS, atau Transfer |
| F-KS-03 | Pembayaran tunai menampilkan uang diterima, kembalian, dan saran nominal |
| F-KS-04 | Tombol terima pembayaran mati selama uang yang dimasukkan kurang dari total |
| F-KS-05 | Struk dapat disimpan ke galeri, dibagikan, dan dicetak |
| F-KS-06 | Struk transaksi lama dapat ditampilkan dan dicetak ulang dari riwayat |
| F-KS-07 | Riwayat Kasir dikelompokkan per hari berikut rincian per metode bayar |
| F-KS-08 | Nama pelanggan dapat diisi pada Dine In (opsional) maupun Take Away (wajib) |
| F-KS-09 | QRIS kasir dibangkitkan penyedia pembayaran sungguhan, dan lunas sendiri saat pembayarannya masuk |
| F-KS-10 | QR pembayaran dapat **dicetak** untuk diserahkan ke pelanggan, dengan bingkai yang sama seperti QR meja |
| F-KS-11 | Diskon yang berlaku ikut dihitung dan ditampilkan sebagai baris tersendiri sebelum pembayaran |
| F-KS-12 | Ketersediaan diperiksa ulang sebelum pembayaran diterima |
| F-KS-13 | Detail jurnal dari catatan yang tampil di layar Saldo dapat dibuka kasir |

### 4.3 Pending Payment

| ID | Kebutuhan |
|---|---|
| F-PP-01 | Menampilkan pesanan mandiri berstatus menunggu pembayaran dengan cara bayar tunai |
| F-PP-02 | Menampilkan jumlah pesanan dan total nominal yang menunggu |
| F-PP-03 | Rincian pesanan dapat dibuka: item, catatan, biaya service, PPN, total |
| F-PP-04 | Menerima pembayaran memakai dialog yang sama dengan checkout kasir |
| F-PP-05 | Satu pesanan tidak dapat dilunasi dua kali oleh ketukan beruntun |
| F-PP-06 | Pesanan yang lunas **hilang seketika** dari antrean tanpa perlu menyegarkan |
| F-PP-07 | Pesanan yang lunas **muncul di Riwayat Kasir** dan ikut dihitung pada total harian, **apa pun cara bayar yang dipakai saat pelunasan** |
| F-PP-08 | Kartu menunya membawa penanda merah berisi jumlah antrean |
| F-PP-09 | Cara bayar dapat **diganti** ke QRIS atau Transfer saat pelunasan |
| F-PP-10 | Sisa waktu pelunasan tampil di tiap kartu, berwarna pada 10 menit terakhir |

**Negatif:** pesanan QRIS yang belum dibayar dan pesanan yang diinput
kasir **tidak boleh** muncul di daftar ini.

### 4.4 Dapur

| ID | Kebutuhan |
|---|---|
| F-CH-01 | Empat tab: **Menunggu Bayar**, Baru, Diproses, Selesai |
| F-CH-02 | Mencentang menu satu per satu; sebagian tercentang → Diproses, seluruhnya → Selesai |
| F-CH-03 | Pesanan selesai dikelompokkan per tanggal, tertutup secara bawaan |
| F-CH-04 | Kotak masuk dapat dibuka dari layar dapur berikut penanda belum dibaca |
| F-CH-05 | Owner yang membuka layar dapur tidak melihat tombol Keluar, Kotak Masuk, Tes Notifikasi, dan Tampilan |
| F-CH-06 | Pesanan yang belum dibayar dikumpulkan di tab Menunggu Bayar, **tidak** bercampur di Baru |
| F-CH-07 | Pesanan yang belum dibayar **tidak punya tombol Mulai Masak**; yang tampil keterangan untuk menunggu kasir |
| F-CH-08 | Pesanan yang hangus atau dibatalkan tidak muncul di tab mana pun |

### 4.5 Keuangan

| ID | Kebutuhan |
|---|---|
| F-FN-01 | Saldo total = Penghasilan + Petty Cash + Setoran − Pengeluaran |
| F-FN-02 | Penghasilan dipisah **Cash** dan **Non Cash**; angka tunai harus cocok dengan isi laci |
| F-FN-03 | Mengajukan/menambah top up petty cash dari tiga sumber dana |
| F-FN-04 | Mencatat pengeluaran, selalu diambil dari petty cash, dibatasi saldo tersedia |
| F-FN-05 | Melampirkan foto nota pada pengeluaran |
| F-FN-06 | Riwayat dikelompokkan per tanggal, **tertutup secara bawaan** |
| F-FN-07 | Tanggal yang menyimpan pengajuan **terbuka sendiri** dan diberi penanda merah |
| F-FN-08 | Setiap baris dapat dibuka untuk melihat jurnal GL di baliknya |
| F-FN-09 | Memetakan nomor GL untuk tiap metode bayar, PPN, service, dan akun perantara |
| F-FN-10 | Mengatur tarif PPN dan biaya service |
| F-FN-11 | Mencetak/mengekspor laporan transaksi bergaya rekening koran |

### 4.6 Setor Saldo Cash

| ID | Kebutuhan |
|---|---|
| F-SD-01 | Mengajukan setoran: nominal, catatan, dan foto bukti transfer |
| F-SD-02 | Nama bank, nomor rekening, dan nama pemilik **hanya ditampilkan**, mengikuti Pengaturan Pembayaran |
| F-SD-03 | Tombol simpan mati bila rekening resto belum diatur |
| F-SD-04 | Popup konfirmasi mengingatkan agar nominalnya sesuai yang benar-benar ditransfer |
| F-SD-05 | Finance mengonfirmasi atau menolak; keputusannya mengembalikan atau meneruskan dananya |
| F-SD-06 | Foto bukti dapat dibuka besar |
| F-SD-07 | Kartu menunya membawa penanda merah berisi jumlah pengajuan menunggu |

### 4.7 Katalog & Pengaturan Resto

| ID | Kebutuhan |
|---|---|
| F-AD-01 | Menambah, mengubah, menonaktifkan produk berikut foto, deskripsi, harga, stok |
| F-AD-02 | Harga diisi sebagai **harga bersih**; harga jual dihitung otomatis |
| F-AD-03 | Menandai produk bebas PPN |
| F-AD-04 | Mengelola kategori |
| F-AD-09 | **Tab Level**: menyusun sendiri kelompok level/varian resto ini berikut pilihannya |
| F-AD-10 | Resto baru disemai lima kelompok bawaan (Level Pedas, Level Gula, Level Es, Suhu, Ukuran) |
| F-AD-11 | Kelompok level minimal punya **2 pilihan**; nama kelompok tidak boleh kembar dalam satu resto |
| F-AD-12 | Stok **opsional**; ketersediaan ditentukan penanda **Out of Stock**, bukan angka stok |
| F-AD-13 | Produk dapat ditandai habis langsung dari daftar, tanpa membuka formulirnya |
| F-AD-14 | Stok tidak ditampilkan ke pelanggan |
| F-AD-05 | Mengelola karyawan; **email dapat diubah** tanpa kehilangan riwayat |
| F-AD-06 | Mengatur info resto, termasuk mengambil titik lokasi sekali tekan |
| F-AD-15 | Lokasi resto punya **pratinjau peta**; titiknya dapat dipilih dengan menggeser pin di peta |
| F-AD-16 | Resto memilih melayani **Dine In**, **Take Away**, atau keduanya; minimal satu harus menyala |
| F-AD-07 | Mengunggah banner promo, mengaktifkan/menonaktifkan, dan mengurutkannya |
| F-AD-17 | Banner promo punya **masa berlaku**: mulai tidak boleh mundur, berakhir minimal besok |
| F-AD-08 | Akun dengan beberapa cabang dapat berpindah resto tanpa logout |

### 4.8 QR Meja

| ID | Kebutuhan |
|---|---|
| F-QR-01 | Membuat QR untuk satu meja dengan nomor bebas ("7", "A01", "VIP-2") |
| F-QR-02 | Membuat banyak meja sekaligus: **isi jumlah mejanya**, misal 10 → 10 QR bernomor 1–10. Maksimal **100** |
| F-QR-03 | Awalan opsional; diisi "A" menghasilkan A1, A2, A3, … |
| F-QR-07 | Nomor meja ditulis polos (`7`, bukan `07`) supaya sama dengan mode satu meja; urutan berkas di galeri dijaga lewat nama berkasnya |
| F-QR-04 | Kartunya bergaya KaataGo, memuat nama resto dan nomor meja |
| F-QR-05 | Menyimpan ke galeri satuan maupun **seluruhnya sekaligus**, dengan penghitung kemajuan |
| F-QR-06 | Membagikan dan mencetak, satu meja satu halaman |

### 4.9 Kotak Masuk & Pengumuman

| ID | Kebutuhan |
|---|---|
| F-IN-01 | Kotak masuk terbagi dua tab: **Update Aplikasi** dan **General** |
| F-IN-02 | Tiap tab menampilkan jumlah pesan belum dibaca sendiri-sendiri |
| F-IN-03 | Pesan dapat dihapus satuan maupun seluruhnya; hanya hilang dari kotak masuk orang itu |
| F-IN-04 | Pengumuman versi memuat tombol **Unduh Versi Terbaru** |
| F-IN-05 | Unduhan berjalan **di dalam aplikasi** berikut persen kemajuan, lalu membuka pemasangnya |
| F-IN-06 | Tersedia jalur cadangan mengunduh lewat browser |
| F-IN-07 | Super Admin mengirim pengumuman versi maupun umum ke seluruh resto |
| F-IN-08 | Admin/Owner mengirim pengumuman umum untuk restonya sendiri |
| F-IN-09 | Pengumuman umum dapat memuat **gambar promo** |
| F-IN-10 | Pengumuman milik sebuah resto tidak muncul di kotak masuk resto lain |
| F-IN-11 | Pengumuman resto memilih sasarannya: **Karyawan**, **Customer**, atau **Semua** |
| F-IN-12 | Pelanggan punya kotak masuknya sendiri di menu utama, berisi promo resto yang pernah dia pesan |
| F-IN-13 | Tiap promo di kotak masuk pelanggan menyebutkan **nama resto pengirimnya** |
| F-IN-14 | Pelanggan tamu ikut menerima; jangkauannya dari pesanan yang tersimpan di perangkatnya |
| F-IN-15 | Tandai-dibaca dan hapus massal hanya mengenai **tab yang sedang dibuka** |
| F-IN-16 | Unduhan tampil di **bar notifikasi HP** berikut persennya, dan tetap jalan saat aplikasi ditinggalkan |
| F-IN-17 | Selesai mengunduh memunculkan notifikasi **"ketuk untuk memasang"** |
| F-IN-18 | Popup unduhan menawarkan **Batalkan** atau **Lanjutkan** |
| F-IN-19 | Galat unduhan diringkas satu kalimat; pembatalan tidak ditampilkan sebagai galat |


### 4.10 Diskon

Menu ini ada di **Kasir, Admin, dan Owner**. Satu aturan diskon berlaku
untuk transaksi kasir maupun pesanan yang dibuat sendiri oleh pelanggan
— promo yang cuma berlaku kalau kasir yang mengetikkan pesanannya bukan
promo, melainkan janji yang gagal ditepati di depan orang yang
membacanya.

| ID | Kebutuhan |
|---|---|
| F-DS-01 | Diskon berbasis **menu tertentu**: satu menu, atau beberapa sekaligus untuk bundling |
| F-DS-02 | Diskon berbasis **minimum belanja** dengan indikator **≥** atau **>** yang dipilih sendiri |
| F-DS-10 | Tiap menu dalam promo membawa **syarat jumlahnya sendiri**, bukan satu angka untuk seluruh promo |
| F-DS-11 | Syarat jumlah berbentuk **Minimal** (lebih banyak tetap dapat) atau **Tepat** (kurang maupun lebih tidak dapat) |
| F-DS-12 | Pada bundling, **seluruh** menu yang disebut harus terpenuhi — kurang satu berarti promonya tidak berlaku sama sekali |
| F-DS-03 | Potongan berbentuk **persen** (1–100) atau **rupiah** |
| F-DS-04 | Masa berlaku: mulai tidak boleh mundur ke belakang, berakhir minimal besok |
| F-DS-05 | Lencana status: **Berjalan**, **Terjadwal**, **Sudah lewat**, **Nonaktif** |
| F-DS-06 | Dapat dinonaktifkan tanpa dihapus |
| F-DS-07 | Potongan tampil sebagai baris tersendiri berikut nama promonya, lalu nominal **DIBAYAR** |
| F-DS-08 | Diskon tercatat pada pesanannya, sehingga struk lama tetap menyebut potongan yang benar |
| F-DS-09 | Diskon punya **GL sendiri** sebagai pengurang pendapatan |

**Aturan pemilihan:**

| Aturan | Alasan |
|---|---|
| Hanya **satu** diskon dipakai — yang paling menguntungkan pelanggan | Menumpuk terdengar murah hati sampai dua promo berlaku bersamaan dan totalnya melebihi harga barangnya |
| Bundling menjumlahkan seluruh menu yang ikut, baru dipotong | Kalau dipotong per baris, diskon rupiah tetap terkalikan sebanyak menu yang ikut |
| Syarat jumlah menempel di **menunya**, bukan di promonya | Satu angka untuk seluruh promo membuat "Nasi Goreng + Es Teh, beli 2" lolos oleh keranjang berisi dua Nasi Goreng dan segelas kopi |
| Bundling menuntut **seluruh** menunya terpenuhi | Sebagian-cukup berarti paket yang dijanjikan tidak pernah benar-benar dibeli, tapi restonya tetap membayar potongannya |
| Menu di luar promo tidak ikut dipotong sekalipun ada di keranjang | Potongannya dihitung dari menu yang memang ikut promo |
| Potongan tidak pernah melebihi tagihannya | Kalau tidak, totalnya negatif — resto berutang kepada orang yang belum membayar apa pun |
| Diskon dihitung dari **total setelah service dan PPN** | Itulah angka yang dilihat dan dijanjikan ke pelanggan |

### 4.11 Pembayaran QRIS lewat Penyedia

| ID | Kebutuhan |
|---|---|
| F-PG-01 | QR pembayaran dibangkitkan penyedia pembayaran, bukan QR simulasi |
| F-PG-02 | Pesanan menjadi lunas saat penyedia mengabarkan pembayarannya masuk — bukan lewat ketukan di layar |
| F-PG-03 | Tiap resto punya sub-akun sendiri, sehingga dananya cair ke rekening masing-masing |
| F-PG-04 | Pengenal sub-akun hanya terlihat dan dapat diubah oleh **Super Admin** |
| F-PG-05 | Layar QRIS menampilkan hitungan mundur masa berlaku QR-nya |
| F-PG-06 | Resto yang belum punya sub-akun tetap dapat memakai QR simulasi berikut konfirmasi manual |
| F-PG-07 | Dengan penyedia aktif, tombol konfirmasi manual **dihilangkan** dari layar kasir |

### 4.12 Pembatalan Pesanan

| ID | Kebutuhan |
|---|---|
| F-CN-01 | Pelanggan dapat membatalkan pesanannya sendiri selama **belum dibayar** |
| F-CN-02 | Tombolnya tersedia di **Pesanan Saya** dan **Riwayat** |
| F-CN-03 | Pembatalan ditolak kalau dapur **sudah mulai memasak**; pesannya mengarahkan ke kasir |
| F-CN-04 | Pembatalan hanya berlaku untuk pesanannya sendiri — dikenali dari email atau sesi perangkatnya |
| F-CN-05 | Pesanan tunai yang tidak dilunasi dalam 30 menit **hangus otomatis** |
| F-CN-06 | Status **Dibatalkan** dibedakan dari **Hangus** |

### 4.13 Tampilan

| ID | Kebutuhan |
|---|---|
| F-TM-01 | Tiga pilihan: **Terang**, **Gelap**, **Ikuti HP** (bawaan) |
| F-TM-02 | Dapat diatur sebelum masuk, di halaman awal, maupun sesudah masuk dari tiap peran |
| F-TM-03 | Pilihannya tersimpan di perangkat dan bertahan setelah aplikasi ditutup |
| F-TM-04 | Pilihan tampilan menyusut jadi ikon saja saat ruangnya sempit |

---

## 5. Aturan Bisnis

### 5.1 Perhitungan tagihan

```
service = harga bersih × tarif service
ppn     = (harga bersih + service) × tarif PPN
total   = harga bersih + service + ppn
```

| Aturan | Keterangan |
|---|---|
| PPN dikenakan atas harga bersih **+ service** | Biaya service sendiri kena PPN. Menghitungnya dari harga bersih saja membuat laporan kurang beberapa ratus rupiah tiap nota |
| Harga di menu = harga bersih + PPN | Biaya service tidak dimasukkan, karena itu biaya per-nota yang hanya berlaku Dine In |
| Take Away | Tidak kena service, tetap kena PPN. Totalnya **sama persis** dengan harga yang tertera di menu |
| Produk bebas PPN | Ditandai per produk |

**Contoh:** harga bersih 55.000, service 5%, PPN 11% → service 2.750,
PPN 6.353, **total 64.103**. Ketiga komponennya selalu berjumlah persis
sama dengan totalnya.

### 5.2 Pengakuan uang

| Kejadian | Akibatnya |
|---|---|
| Pesanan lunas | Tercatat sebagai pemasukan pada GL sesuai cara bayarnya, terpisah dari PPN dan biaya service |
| Setoran diajukan | Uangnya **keluar dari Saldo Cash** dan mengendap di akun perantara |
| Setoran dikonfirmasi | Berpindah dari perantara ke saldo rekening resto |
| Setoran ditolak | **Kembali** ke Saldo Cash |
| Top up petty diajukan | Keluar dari sumbernya, mengendap di perantara petty cash |
| Top up disetujui / ditolak | Masuk ke petty cash / kembali ke sumbernya |
| Pengeluaran | Mengurangi petty cash |
| Diskon diberikan | Didebit ke GL Diskon sebagai **pengurang pendapatan**, bukan sebagai biaya — diskon bukan uang yang keluar, melainkan uang yang tidak pernah masuk |

Setiap perpindahan uang menghasilkan jurnal yang **seimbang**, dan
pembatalan selalu mengembalikan dananya ke asal — tidak boleh ada yang
tersangkut di akun perantara.

**Dua tahap, dua pasang baris.** Setoran dan top up petty cash tidak
berpindah sekali, tapi dua kali: dari sumbernya ke akun perantara saat
diajukan, lalu dari perantara ke tujuannya saat disetujui. Karena itu
total debit dan kreditnya **dua kali lipat** nilai transaksinya,
sementara saldo perantaranya kembali nol. Layar rincian jurnal
menyebutkan hal ini supaya angkanya tidak dikira salah hitung.

### 5.3 Isi Riwayat Kasir

Yang menentukan bukan siapa yang mengetik pesanannya, melainkan **apakah
uangnya diterima di meja kasir**.

| Pesanan | Masuk Riwayat Kasir? |
|---|:--:|
| Diinput Kasir/Admin/Owner, metode apa pun | ✔ |
| Pelanggan, dilunasi di kasir — **tunai, QRIS, maupun transfer** | ✔ |
| Pelanggan, belum dibayar | ✘ — masih di Pending Payment |
| Pelanggan, QRIS dibayar sendiri lewat HP | ✘ — tidak pernah lewat meja kasir |
| Pelanggan, dibatalkan atau hangus | ✘ — uangnya tidak pernah berpindah |

Penandanya adalah catatan **siapa yang menerima pembayarannya**, bukan
cara bayarnya. Sebelumnya cara bayar yang dipakai menebak, dan tebakan
itu runtuh begitu cara bayar boleh diganti saat pelunasan: uang masuk
laci, transaksinya lenyap dari riwayat.

### 5.4 Ketersediaan produk

| Aturan | Keterangan |
|---|---|
| Stok **tidak** menentukan ketersediaan | Angka stok jadi catatan biasa, boleh diisi boleh tidak |
| Yang menentukan cuma penanda **Out of Stock** | Dinyatakan sengaja oleh orang yang tahu keadaan dapurnya |
| Produk habis tetap tampil | Dengan tanda dan tidak bisa dipesan — pelanggan berhak tahu menunya ada tapi sedang kosong |
| Diperiksa ulang sebelum membayar | Keranjang bisa terisi berjam-jam sebelum dibayar |
| Pemeriksaan yang gagal karena jaringan **tidak** menahan pesanan | Menahan pesanan yang mungkin baik-baik saja merugikan lebih banyak orang |

### 5.5 Masa berlaku promo

| Aturan | Keterangan |
|---|---|
| Tanggal mulai tidak boleh mundur | Transaksi kemarin sudah dijurnal tanpa diskonnya |
| Tanggal berakhir minimal besok | Promo yang berakhir hari ini juga tidak pernah sempat dipakai |
| Hari terakhir berlaku **penuh** | "Sampai 31 Agustus" berarti sampai tutup toko tanggal 31 |
| Batasnya ditegakkan di kalendernya | Tanggal yang tidak sah tidak bisa dipilih, bukan ditolak setelah dipilih |

---

## 6. Aturan Validasi Isian

Berlaku sama di seluruh layar. Tiap aturan dipasang **dua lapis**: isian
menolak karakter terlarang saat diketik, dan diperiksa lagi saat
disimpan.

> **Wajib diuji dengan tempel (paste), bukan hanya diketik.** Lapis
> kedua ada justru untuk isian yang masuk lewat tempel atau papan ketik
> yang mengabaikan pembatasnya.

| Jenis | Maks | Diizinkan | Aturan tambahan |
|---|:--:|---|---|
| **Nama** (orang, resto, produk, bank) | **40** | Huruf, angka, spasi, `. , ' ( ) & / -` | Wajib, kecuali dinyatakan opsional |
| **Nomor HP** | **15** | Angka saja | Minimal 8 angka; tanda `+` tidak diizinkan |
| **Email** | **25** | Huruf, angka, `@ . _ -` | **Wajib `@gmail.com`** |
| **NIP** | **15** | Angka saja | Opsional |
| **Nomor rekening** | **20** | Angka saja | — |
| **Tarif persen** | **6** | Angka, `.` `,` | Rentang 0–100; koma dibaca desimal; kosong berarti 0 |
| **Harga & stok** | — | Angka | Wajib |
| **Awalan QR meja** | **6** | Bebas | Opsional |
| **Jumlah meja** | **3** digit | Angka | 1 sampai 100 |
| **Nama diskon** | **40** | Sama seperti nama | Wajib |
| **Persen diskon** | 3 | Angka | 1 sampai 100 |
| **Nominal diskon** | — | Angka | Harus lebih dari 0, tidak pernah melebihi tagihan |
| **Minimum belanja** | — | Angka | Harus lebih dari 0 |
| **Nama kelompok level** | **40** | Sama seperti nama | Tidak boleh kembar dalam satu resto |
| **Pilihan level** | — | Bebas | Minimal 2, tidak boleh kembar |
| **Stok** | — | Angka | **Opsional** — kosong berarti tidak dihitung |

### 6.1 Alasan aturan yang sering dikira bug

| Aturan | Alasan |
|---|---|
| Email wajib Gmail | Satu-satunya cara masuk adalah Login dengan Google. Alamat lain akan tersimpan rapi lalu gagal login tanpa penjelasan apa pun |
| Nomor HP tanpa `+` | Nomor Indonesia ditulis mulai `0` atau `62`. Mengizinkan `+` membuat nomor yang sama tersimpan dalam dua bentuk yang tidak bisa dicocokkan |
| Tarif menolak `11.` | Bentuk setengah jadi itu lolos begitu saja kalau hanya diperiksa sebagai angka |
| Emoji ditolak pada nama | Nama dipakai di struk dan PDF, yang fontnya tidak memuat emoji |
| Kelompok level minimal 2 pilihan | Satu pilihan bukan pilihan — cuma dropdown yang jawabannya sudah ditentukan, menambah satu ketukan di tiap pesanan tanpa menghasilkan keterangan apa pun |
| Tanggal mulai promo tidak bisa mundur | Pembukuan yang sudah ditutup tidak lagi cocok dengan daftar promonya |
| Stok boleh kosong | Nasi goreng tidak punya "sisa 7 porsi" — yang ada cuma "masih ada" atau "bahannya habis" |

### 6.2 Pesan galat

Pesan galat selalu tampil **di depan dialog isian**, tidak pernah
tertutup di belakangnya.

---

## 7. Daftar Status

### 7.1 Pembayaran pesanan

| Status | Arti |
|---|---|
| **Menunggu Pembayaran** | Pesanan sudah masuk, uangnya belum |
| **Sudah Dibayar** | Lunas dan tercatat sebagai pemasukan |
| **Dibatalkan** | Ditarik sendiri oleh pelanggannya sebelum dibayar |
| **Hangus, tidak dibayar** | Tidak dilunasi sampai 30 menit lewat; dibatalkan sistem, bukan orang |

### 7.2 Dapur

| Status | Dipicu oleh |
|---|---|
| **Menunggu Bayar** | Pesanan mandiri yang uangnya belum diterima |
| **Baru** | Pesanan masuk dan sudah dibayar |
| **Diproses** | Dapur mencentang sebagian menu |
| **Selesai** | Seluruh menu tercentang |

### 7.3 Setoran & top up

| Status | Setoran | Petty cash |
|---|---|---|
| Menunggu | Pending | Pending |
| Disetujui | **Completed** | **Completed** |
| Ditolak | Ditolak | Ditolak |

> Pada setoran, Finance tidak "menyetujui permintaan" — dia memastikan
> uangnya benar-benar masuk rekening. Karena itu istilahnya
> **konfirmasi**, dan hasilnya **Completed**.

---

## 8. Notifikasi

### 8.1 Siapa dikabari, kapan

| Peran | Dikabari saat |
|---|---|
| Pelanggan | Pesanannya mulai dimasak, dan saat siap |
| Dapur | Ada pesanan baru masuk |
| Kasir | Pesanan yang dia input sendiri mulai dimasak / siap |
| Kasir, Admin, Owner | Ada pesanan menunggu dibayar di kasir |
| Finance, Owner | Ada setoran atau top up yang menunggu keputusan |
| Kasir & Admin | Pengajuannya sendiri sudah diputus, berikut alasannya bila ditolak |
| Seluruh pengguna | Ada pengumuman baru — dari Super Admin maupun dari restonya |
| Sesuai sasaran | Pengumuman resto hanya membunyikan HP kelompok yang dituju: karyawan saja, pelanggan saja, atau keduanya |

**Tidak ada gema:** yang memutuskan tidak dikabari soal keputusannya
sendiri, dan yang membuat pesanan tidak dikabari soal pesanan yang baru
saja dia buat.

### 8.2 Sifatnya

| Sifat | Keterangan |
|---|---|
| Tetap sampai saat aplikasi tertutup | Notifikasi dikirim dari server, bukan dibangkitkan aplikasi yang sedang berjalan |
| Lima jenis terpisah | Status Pesanan, Pesanan Baru, Hasil Pengajuan, Pengumuman, Unduhan Pembaruan — masing-masing bisa dibisukan sendiri lewat Setelan Android |
| Pengumuman tetap berbunyi saat aplikasi terbuka | Berbeda dari kabar pesanan, yang sudah dibunyikan aliran langsungnya |
| Unduhan tidak berbunyi | Baris kemajuannya menemani, bukan memanggil |
| Nada dering khas | Nada KaataGo, bukan nada bawaan |
| Tidak menumpuk | Kabar baru untuk kejadian yang sama menimpa kabar lama — kecuali pengumuman, yang tiap kabarnya berdiri sendiri |
| Tidak membanjir saat dibuka | Membuka aplikasi setelah lama tertutup tidak memunculkan notifikasi beruntun untuk kejadian lama |

---

## 9. Kriteria Penerimaan

Rilis dianggap layak bila seluruh butir berikut terpenuhi.

| # | Kriteria |
|---|---|
| A-01 | Pelanggan tamu dapat menyelesaikan pesanan dari scan QR sampai pembayaran tanpa membuat akun |
| A-02 | Pesanan tunai dari HP pelanggan muncul di Pending Payment, dan setelah dilunasi berpindah ke Riwayat Kasir — tidak ada di keduanya, tidak hilang dari keduanya |
| A-03 | Total harian di Riwayat Kasir cocok dengan isi laci saat tutup shift |
| A-04 | Komponen tagihan (harga bersih + service + PPN) selalu berjumlah persis sama dengan totalnya |
| A-05 | Setoran atau top up yang ditolak mengembalikan dananya ke asal, tidak tersangkut di akun perantara |
| A-06 | Kasir tidak dapat menyetujui pengajuannya sendiri |
| A-07 | Pengajuan yang menunggu terlihat sebagai penanda merah tanpa perlu membuka layarnya |
| A-08 | Notifikasi sampai ke HP dalam keadaan aplikasi tidak terbuka |
| A-09 | Setiap kolom isian menolak masukan tidak sah, baik diketik maupun ditempel |
| A-10 | Data antar cabang tidak saling bocor saat akun berpindah resto |
| A-11 | Tombol aksi tidak pernah menutupi baris terakhir daftar mana pun |
| A-12 | Banner promo tampil utuh tanpa terpotong, dan ikut tergulir bersama menunya |
| A-13 | Pesanan yang dilunasi di kasir masuk Riwayat Kasir **apa pun cara bayar** yang dipilih saat pelunasan |
| A-14 | Diskon yang sama berlaku untuk transaksi kasir maupun pesanan mandiri pelanggan |
| A-15 | Hanya satu diskon dipakai per transaksi, dan potongannya tidak pernah melebihi tagihannya |
| A-16 | Pesanan yang belum dibayar tidak dapat dimasak dari layar dapur |
| A-17 | Pesanan yang dibatalkan atau hangus tidak muncul di dapur, Pending Payment, maupun Riwayat Kasir |
| A-18 | Seluruh layar terbaca pada mode terang maupun gelap — tidak ada tulisan yang hilang di latarnya |
| A-19 | Resto baru langsung punya bagan akun GL dan tarif pajak, sehingga transaksi hari pertamanya terjurnal |
| A-20 | Pengumuman internal resto tidak pernah sampai ke pelanggan |

---

## 10. Batasan yang Diketahui

Hal-hal berikut **disengaja atau sudah diketahui**, jadi tidak perlu
dilaporkan sebagai temuan.

| Batasan | Dampak |
|---|---|
| **QRIS simulasi untuk resto tanpa sub-akun** | Resto yang belum punya sub-akun penyedia tetap memakai QR simulasi berikut konfirmasi manual |
| **Bahasa Inggris belum lengkap** | Mekanismenya ada, terjemahannya baru sebagian, jadi pemilih bahasanya dimatikan |
| **Popup pemasang tidak menginterupsi sendiri** | Android melarang aplikasi di latar membuka layar sendiri. Selesai mengunduh memunculkan notifikasi yang harus diketuk |
| **Unduhan besar bisa terhenti** | Kalau sistem kehabisan memori saat aplikasi di latar, unduhannya ikut berhenti |
| **Ubin peta dari OpenStreetMap** | Gratis dan tanpa kunci API; kerapatan petanya di bawah Google Maps |
| **Notifikasi tertahan pada sebagian HP** | Di Xiaomi, Oppo, Vivo, Realme, dan sebagian Samsung, menggeser aplikasi dari daftar aplikasi terkini sama dengan menghentikannya paksa — notifikasi baru masuk saat aplikasi dibuka lagi. Perlu mengaktifkan *Autostart* dan menyetel baterainya *Tidak dibatasi* |
| **Penanda merah bukan waktu-nyata** | Angkanya dimuat saat layar dibuka dan saat kembali dari layarnya, bukan dipantau terus-menerus |
| **Penanda di kasir menghitung se-resto** | Termasuk pengajuan rekan seshift, bukan hanya miliknya sendiri |
| **Maksimal 100 QR sekali buat** | Batas yang disengaja |
| **Struk & QR butuh internet saat dibuat** | Dalam keadaan benar-benar luring, hurufnya jatuh ke font bawaan; bentuknya tetap benar |
| **Titik lokasi memakai layanan gratis** | Pengambilan lokasi beruntun dalam waktu singkat bisa ditolak sementara |

---

---

## 11. Lampiran A — Tangkapan Layar

Tangkapan layar berikut diambil dari aplikasi yang berjalan, disusun per
peran dan per mode tampilan. Urutannya mengikuti alur pemakaian
sebenarnya, dari layar pertama sampai layar terakhir yang dibuka.

Dua mode disertakan karena keduanya bukan sekadar pembalikan warna:
warna merek dinaikkan terangnya di mode gelap, bilah atas ikut gelap,
dan latar kartunya dibedakan dari latar halaman. Yang perlu dipastikan
saat memeriksanya cuma satu — tidak ada tulisan yang hilang di
latarnya.

### A.1 Pelanggan — tanpa akun (tamu)

Tamu memesan tanpa mendaftar apa pun. Yang dikorbankan cuma satu — jejak
pesanannya hanya tersimpan di HP itu sendiri, dan hilang bersama
aplikasinya kalau dihapus.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Halaman awal** | Memilih masuk sebagai Pelanggan atau Karyawan Resto; mengatur tema; membuka Tentang KaataGo |
| **Ajakan login** | Melewatinya lewat "Lewati, Pesan Tanpa Login" dan langsung memesan |
| **Layar pembuka tamu** | Tiga pintu saja: Scan QR Meja, Pilih Resto, dan Riwayat Pesanan Saya |
| **Pilih Resto** | Mencari resto; melihat yang terdekat berikut jaraknya begitu izin lokasi diberikan — sebelum itu hanya bagian Semua Resto yang tampil |
| **Menu resto** | Melihat banner promo, membuka kategori, menambah menu ke keranjang |
| **Dialog menu** | Memilih level/varian — minuman bisa punya tiga kelompok sekaligus (Gula, Es, Ukuran) — menulis catatan, mengatur jumlah |
| **Keranjang** | Memilih Dine In atau Take Away; Take Away tidak meminta nomor meja, tapi nama pemesan tetap wajib; memilih QRIS atau Tunai |
| **Bayar dengan QRIS** | Memindai QR berbingkai KaataGo, melihat masa berlakunya, menyimpannya ke galeri |
| **Pesanan diterima** | Membaca nomor pesanan untuk disebutkan di kasir, dan hitung mundur 30 menit sebelum pesanannya hangus |
| **Pesanan Saya** | Memantau status dapur dan pembayaran untuk sesi meja yang sedang berjalan |
| **Riwayat Saya** | Melihat pesanan sebelumnya — disertai peringatan bahwa riwayatnya hanya ada di HP ini |


**Mode Terang** — 13 tangkapan

!!ss[Halaman awal — pilih peran, pemilih tema, nomor versi](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215645.jpg)
!!ss[Tentang KaataGo — tautan situs dan ringkasan fitur tiap peran](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215651.jpg)
!!ss[Ajakan login; tamu memilih Lewati, Pesan Tanpa Login](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215655.jpg)
!!ss[Layar pembuka tamu — Scan QR Meja, Pilih Resto, dan Riwayat Pesanan Saya](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215700.jpg)
!!ss[Pilih Resto sebelum izin lokasi diberikan — hanya bagian Semua Resto](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215705.jpg)
!!ss[Layar yang sama setelah lokasi diketahui — bagian Terdekat muncul berikut jaraknya](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215711.jpg)
!!ss[Menu resto — banner promo, kategori terlipat, keranjang kosong](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215715.jpg)
!!ss[Dialog menu makanan — Level Pedas, catatan, jumlah, subtotal](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215723.jpg)
!!ss[Dialog menu minuman — tiga kelompok level: Gula, Es, dan Ukuran](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215730.jpg)
!!ss[Keranjang Take Away — nomor meja tidak diminta, nama pemesan wajib](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215807.jpg)
!!ss[Cara bayar Tunai dipilih — tombolnya berubah jadi Pesan & Bayar di Kasir](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215811.jpg)
!!ss[Pesanan diterima — nomor pesanan untuk disebutkan di kasir dan hitung mundur 30 menit](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215816.jpg)
!!ss[Riwayat Saya milik tamu — peringatan bahwa riwayatnya hanya tersimpan di HP ini](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215833.jpg)


**Mode Gelap** — 9 tangkapan

!!ss[Halaman awal dengan tema Gelap aktif](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213321.jpg)
!!ss[Layar pembuka tamu](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213329.jpg)
!!ss[Pilih Resto — Terdekat dan Semua Resto](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213335.jpg)
!!ss[Menu resto — banner promo dan kategori](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213341.jpg)
!!ss[Dialog menu — deskripsi produk ikut tampil di bawah harganya](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213349.jpg)
!!ss[Keranjang Dine In — nomor meja dan nama pemesan, rincian biaya service dan PPN](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213408.jpg)
!!ss[Bayar dengan QRIS — kartu QR berbingkai, masa berlaku, simpan ke galeri](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213417.jpg)
!!ss[Pembayaran berhasil berikut nomor pesanannya](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213425.jpg)
!!ss[Pesanan Saya — status dapur dan pembayaran untuk sesi meja ini](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213434.jpg)


### A.2 Pelanggan — dengan akun

Alur pada tangkapan layar berikut mengikuti satu sesi utuh: masuk dengan
akun Google, memilih resto, memesan, membayar, lalu memeriksa pesanan
dan riwayatnya.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Halaman awal** | Memilih masuk sebagai Pelanggan atau Karyawan Resto; mengatur tema sebelum masuk; membuka Tentang KaataGo |
| **Ajakan login** | Masuk dengan Gmail, atau melewatinya dan tetap memesan sebagai tamu |
| **Menu utama** | Tujuh pintu: Pesan, Profil, Riwayat, Kotak Masuk (berikut penanda belum dibaca), Tampilan, Tes Notifikasi, Keluar |
| **Mau Pesan Di Mana?** | Scan QR meja, atau memilih resto dari daftar |
| **Pilih Resto** | Mencari resto dari nama atau alamat; melihat yang terdekat berikut jaraknya; membuka lokasinya di peta |
| **Menu resto** | Melihat banner promo, membuka kategori, menambah menu ke keranjang; banner ikut tergulir bersama menunya |
| **Dialog menu** | Memilih level/varian, menulis catatan, mengatur jumlah, melihat subtotalnya berubah |
| **Keranjang** | Memilih Dine In atau Take Away, mengisi nomor meja dan nama, melihat rincian biaya service dan PPN, memilih QRIS atau Tunai |
| **Bayar dengan QRIS** | Memindai QR berbingkai KaataGo, melihat masa berlakunya, menyimpan QR ke galeri |
| **Pesanan diterima (tunai)** | Membaca nomor pesanan yang disebutkan di kasir, dan hitung mundur 30 menit sebelum pesanannya hangus |
| **Struk** | Melihat rincian menu, biaya, dan cara bayar; menyimpan atau membagikannya |
| **Pesanan Saya** | Memantau status dapur dan pembayaran; membatalkan pesanan yang belum dibayar |
| **Riwayat Saya** | Melihat seluruh pesanan lintas tanggal dan resto |
| **Profil** | Mengubah nama, nomor telepon, dan foto; email terkunci karena dari akun Google |
| **Kotak Masuk** | Membaca pemberitahuan versi baru dan promo dari resto yang pernah dipesan |
| **Tampilan** | Berganti mode terang, gelap, atau mengikuti setelan HP |


**Mode Terang** — 18 tangkapan

!!ss[Halaman awal — masuk sebagai Pelanggan](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215350.jpg)
!!ss[Ajakan login Gmail, dengan pilihan "Lewati, Pesan Tanpa Login"](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215354.jpg)
!!ss[Menyiapkan data setelah login](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215403.jpg)
!!ss[Menu utama pelanggan — Pesan, Profil, Riwayat, Kotak Masuk, Tampilan, Tes Notifikasi, Keluar](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215409.jpg)
!!ss[Mau Pesan Di Mana? — pemindai QR meja terbuka di bawah](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215412.jpg)
!!ss[Mau Pesan Di Mana? — Scan QR Meja atau Pilih Resto](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215416.jpg)
!!ss[Pilih Resto — daftar terdekat dengan jarak, lalu semua resto, bisa dicari](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215421.jpg)
!!ss[Menu resto — banner promo di atas, kategori terlipat, keranjang masih kosong](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215430.jpg)
!!ss[Kategori Makanan terbuka — foto, nama, harga, tombol tambah](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215434.jpg)
!!ss[Detail menu — level pedas, catatan opsional, jumlah, subtotal](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215438.jpg)
!!ss[Menu setelah item ditambahkan — bilah keranjang muncul di bawah](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215444.jpg)
!!ss[Keranjang — Dine In/Take Away, nomor meja & nama wajib, rincian biaya service dan PPN, pilihan QRIS/Tunai](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215448.jpg)
!!ss[Keranjang dengan nomor meja terisi](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215454.jpg)
!!ss[Keranjang dengan cara bayar Tunai — tombol berubah jadi "Pesan & Bayar di Kasir"](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215504.jpg)
!!ss[Pesanan Diterima (tunai) — nomor pesanan, nominal, hitung mundur 30 menit sebelum pesanan hangus](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215509.jpg)
!!ss[Pesanan Saya — pesanan yang belum dibayar bisa dibatalkan sendiri](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215515.jpg)
!!ss[Lengkapi Profil — foto, nama, email terkunci, nomor telepon opsional](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215522.jpg)
!!ss[Riwayat Saya — semua pesanan lintas resto, dengan tombol batal pada yang belum dibayar](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215526.jpg)


**Mode Gelap** — 22 tangkapan

!!ss[Halaman awal dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212736.jpg)
!!ss[Tentang KaataGo — tautan situs dan penjelasan fitur per peran](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212742.jpg)
!!ss[Ajakan login Gmail dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212748.jpg)
!!ss[Menyiapkan data setelah login](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212800_Google Play services.jpg)
!!ss[Menyiapkan data (lanjutan)](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212808_Google Play services.jpg)
!!ss[Menu utama pelanggan dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212818.jpg)
!!ss[Mau Pesan Di Mana?](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212822.jpg)
!!ss[Pilih Resto — daftar terdekat dan semua resto](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212826.jpg)
!!ss[Menu resto dengan banner promo — banner ikut tergulir bersama daftar menu](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212835.jpg)
!!ss[Banner promo diketuk — syarat dan periode promonya dibuka penuh](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212842.jpg)
!!ss[Kategori Makanan terbuka](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212902.jpg)
!!ss[Kategori Minuman terbuka](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212907.jpg)
!!ss[Keranjang berisi dua item, lengkap dengan pilihan level per item](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212935.jpg)
!!ss[Bayar dengan QRIS — QR berbingkai KaataGo, hitung mundur, simpan ke galeri](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212946.jpg)
!!ss[Pembayaran Berhasil — pesanan diteruskan ke kasir](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212955.jpg)
!!ss[Struk Pembayaran — rincian item, biaya service, PPN, metode; bisa disimpan atau dibagikan](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213006.jpg)
!!ss[Pesanan Saya — status dapur dan status bayar terpisah, termasuk yang dibatalkan](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213013.jpg)
!!ss[Lengkapi Profil dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213025.jpg)
!!ss[Riwayat Saya dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213030.jpg)
!!ss[Kotak Masuk pelanggan — tab Update Aplikasi dan General, yang belum dibaca bertanda titik](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213035.jpg)
!!ss[Pemilih tampilan: terang, gelap, atau ikut setelan HP — berlaku di perangkat ini saja](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213056.jpg)
!!ss[Konfirmasi keluar dari akun](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213105.jpg)


### A.3 Kasir

Kasir memegang dua antrean sekaligus: pesanan yang dia ketik sendiri di
meja kasir, dan pesanan yang dikirim pelanggan dari HP-nya lalu memilih
bayar tunai. Keduanya bertemu di layar yang sama.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Menu kasir** | Tujuh pintu: Input Pesanan, Pending Payment (berikut jumlah yang menunggu), Riwayat Kasir, Saldo & Pengeluaran, Setor Saldo Cash, Kotak Masuk, Diskon |
| **Input Pesanan** | Memilih menu per kategori; sisa stok tampil di pojok kartu — angka yang tidak pernah dilihat pelanggan |
| **Dialog menu** | Memilih level/varian, menulis catatan, mengatur jumlah; deskripsi dan sisa stok ikut terlihat |
| **Checkout** | Memilih Dine In atau Take Away; Dine In meminta nomor meja, Take Away meminta nama pelanggan; tombol pembayaran mati sampai yang wajib terisi; diskon sudah terhitung dan menurunkan nominal DIBAYAR |
| **Bayar QRIS di kasir** | Menampilkan QR berbingkai KaataGo, dan mencetak QR itu untuk diserahkan ke pelanggan |
| **Dialog pembayaran tunai** | Memakai pilihan nominal cepat atau papan angka; kembalian dihitung sendiri; tombol terima mati selama uangnya kurang |
| **Struk** | Mencetak struk lengkap berikut nama kasir, uang bayar, dan kembaliannya |
| **Pending Payment** | Melihat pesanan pelanggan yang menunggu dibayar berikut sisa waktunya; membuka rinciannya; memilih cara terima pembayaran — Tunai, QRIS, atau Transfer — walau pelanggannya tadi memilih tunai |
| **Riwayat Kasir** | Rekap per hari berikut rincian per cara bayar, dan mencetak ulang struk |
| **Saldo & Pengeluaran** | Melihat saldo total, cash dan non-cash, petty cash, dan rekening resto; mengajukan Top Up Petty Cash yang menunggu persetujuan Finance |
| **Setor Saldo Cash** | Melihat tunai di laci berikut rinciannya; mengisi formulir setoran dengan rekening tujuan yang terisi sendiri dari Pengaturan Pembayaran, dan melampirkan buktinya |
| **Diskon** | Membuat dan mengubah promo — per menu, bundling, atau minimum belanja; tiap menu diberi syarat jumlahnya sendiri, Minimal atau Tepat |


**Mode Terang** — 18 tangkapan

!!ss[Halaman awal — masuk sebagai Karyawan Resto](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215927.jpg)
!!ss[Memilih akun Google karyawan](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215931_Google Play services.jpg)
!!ss[Menu kasir — Input Pesanan, Pending Payment (2 menunggu), Riwayat Kasir, Saldo, Setor, Kotak Masuk, Diskon](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215939.jpg)
!!ss[Input Pesanan — kategori Makanan terbuka; angka di pojok kartu adalah sisa stok](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215946.jpg)
!!ss[Kategori Minuman ikut terbuka](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215949.jpg)
!!ss[Checkout — tombol bayar mati sampai nomor meja diisi; diskon sudah terhitung dan menurunkan nominal DIBAYAR](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215957.jpg)
!!ss[Nomor meja dan nama pelanggan terisi — ketiga tombol pembayaran menyala](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220007.jpg)
!!ss[Bayar dengan QRIS di meja kasir — QR berbingkai KaataGo dan tombol Cetak QR untuk Customer](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220014.jpg)
!!ss[Pembayaran berhasil — struk lengkap berikut nama kasirnya, siap dicetak](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220021.jpg)
!!ss[Pending Payment — dua pesanan menunggu, masing-masing dengan sisa waktu bayarnya](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220026.jpg)
!!ss[Memilih cara terima pembayaran: Tunai, QRIS, atau Transfer](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220037.jpg)
!!ss[Dialog pembayaran tunai — pilihan nominal cepat; tombol terima mati selama uangnya kurang](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220048.jpg)
!!ss[Uang diterima diisi — kembaliannya dihitung otomatis](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220051.jpg)
!!ss[Pesanan lunas hilang dari antrean; pemberitahuan menyebutkan kembaliannya](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220055.jpg)
!!ss[Riwayat Kasir — rekap per hari berikut rincian per cara bayar dan tombol cetak ulang struk](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220102.jpg)
!!ss[Saldo & Pengeluaran — saldo total, saldo cash dan non-cash, petty cash, rekening resto](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220107.jpg)
!!ss[Setor Saldo Cash — tunai di laci berikut rinciannya dan riwayat setoran](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220110.jpg)
!!ss[Diskon — kartu promo berikut lencana Berjalan dan masa berlakunya](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220115.jpg)


**Mode Gelap** — 32 tangkapan

!!ss[Halaman awal, tema gelap](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213818.jpg)
!!ss[Memilih akun Google karyawan](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213826_Google Play services.jpg)
!!ss[Menu kasir](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213831.jpg)
!!ss[Input Pesanan — kategori masih terlipat](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213836.jpg)
!!ss[Kedua kategori terbuka berikut sisa stok tiap menu](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213839.jpg)
!!ss[Dialog menu — deskripsi, sisa stok, level, catatan, dan jumlah](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213846.jpg)
!!ss[Dialog minuman — tiga kelompok level sekaligus](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213850.jpg)
!!ss[Checkout Dine In — tombol bayar mati sebelum nomor meja diisi](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213856.jpg)
!!ss[Checkout Take Away — yang diminta nama pelanggan, bukan nomor meja](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213901.jpg)
!!ss[Nama pelanggan terisi — tombol pembayaran menyala](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213912.jpg)
!!ss[Dialog pembayaran tunai — papan angka terbuka, tombol terima masih mati](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213919.jpg)
!!ss[Uang diterima diisi — kembalian muncul dan tombol terima menyala](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213925.jpg)
!!ss[Dialog yang sama dilihat utuh](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213939.jpg)
!!ss[Kembalian Rp 38.950 untuk uang Rp 100.000](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213943.jpg)
!!ss[Struk — memuat uang bayar dan kembaliannya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213951.jpg)
!!ss[Layar pelanggan setelah memilih bayar tunai — nomor pesanan dan hitung mundur](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214038.jpg)
!!ss[Menu kasir — penanda Pending Payment berubah jadi 1](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214057.jpg)
!!ss[Pending Payment — satu pesanan tamu menunggu dibayar](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214100.jpg)
!!ss[Rincian pesanan sebelum uangnya diterima](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214105.jpg)
!!ss[Memilih cara terima pembayaran](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214111.jpg)
!!ss[Dialog pembayaran tunai untuk pesanan dari HP pelanggan](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214119.jpg)
!!ss[Uang diterima diisi berikut kembaliannya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214124.jpg)
!!ss[Antrean kosong setelah dilunasi](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214128.jpg)
!!ss[Riwayat Kasir — pesanan tadi ikut masuk rekap hari ini](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214136.jpg)
!!ss[Saldo & Pengeluaran](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214142.jpg)
!!ss[Top Up Petty Cash — kasir mengajukan, menunggu persetujuan Finance](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214156.jpg)
!!ss[Pengajuan tercatat sebagai Pending dan ditandai di kartu Petty Cash](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214204.jpg)
!!ss[Setor Saldo Cash — tunai di laci berikut rinciannya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214210.jpg)
!!ss[Formulir setoran — rekening tujuan terisi dari Pengaturan Pembayaran, bukti bisa dilampirkan](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214222.jpg)
!!ss[Setoran tercatat Pending dan mengurangi tunai di laci](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214229.jpg)
!!ss[Diskon — daftar promo resto](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214243.jpg)
!!ss[Ubah Diskon — dasar promo, potongan, dan masa berlakunya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214248.jpg)


### A.4 Dapur (Chef)

Layar dapur hanya empat tab, dan urutannya adalah urutan hidup sebuah
pesanan. Yang belum dibayar berhenti di tab pertama dan tidak pernah
sampai ke antrean masak — bahan tidak terpakai untuk pesanan yang
uangnya belum tentu datang.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Tab Menunggu Bayar** | Melihat pesanan yang belum dilunasi; sengaja tanpa tombol masak |
| **Tab Baru** | Melihat pesanan siap dimasak, dikelompokkan Dine In dan Take Away; menekan Mulai Masak |
| **Tab Diproses** | Membuka daftar centang per menu; menyimpan progres sebagian, atau menutup pesanan begitu seluruh menunya tercentang |
| **Tab Selesai** | Melihat pesanan yang sudah beres, dikelompokkan per tanggal dan tertutup secara bawaan |
| **Pemilih tema** | Berganti terang, gelap, atau ikut setelan HP langsung dari layar dapur |


**Mode Terang** — 9 tangkapan

!!ss[Halaman awal](gambar/capture/Lightmode/Chef/Screenshot_20260816-220755.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Lightmode/Chef/Screenshot_20260816-220802.jpg)
!!ss[Tab Menunggu Bayar — kosong; pesanan yang belum dibayar berhenti di sini, bukan di antrean masak](gambar/capture/Lightmode/Chef/Screenshot_20260816-220807.jpg)
!!ss[Tab Baru — pesanan siap dimasak, dikelompokkan Dine In dan Take Away, berikut tombol Mulai Masak](gambar/capture/Lightmode/Chef/Screenshot_20260816-220810.jpg)
!!ss[Tab Diproses — belum ada yang dikerjakan](gambar/capture/Lightmode/Chef/Screenshot_20260816-220818.jpg)
!!ss[Tab Selesai — dikelompokkan per tanggal dan tertutup secara bawaan](gambar/capture/Lightmode/Chef/Screenshot_20260816-220821.jpg)
!!ss[Pesanan berpindah ke Diproses — tombolnya berubah jadi Cek Menu & Selesai](gambar/capture/Lightmode/Chef/Screenshot_20260816-220832.jpg)
!!ss[Daftar centang per menu — seluruhnya tercentang, pesanan siap ditutup](gambar/capture/Lightmode/Chef/Screenshot_20260816-220837.jpg)
!!ss[Tab Selesai — pesanan hari ini beserta rinciannya](gambar/capture/Lightmode/Chef/Screenshot_20260816-220841.jpg)


**Mode Gelap** — 8 tangkapan

!!ss[Halaman awal, tema gelap](gambar/capture/Darkmode/Chef/Screenshot_20260816-213602.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Darkmode/Chef/Screenshot_20260816-213612_Google Play services.jpg)
!!ss[Tab Menunggu Bayar](gambar/capture/Darkmode/Chef/Screenshot_20260816-213619.jpg)
!!ss[Tab Baru — dua pesanan menunggu dimasak](gambar/capture/Darkmode/Chef/Screenshot_20260816-213623.jpg)
!!ss[Tab Diproses](gambar/capture/Darkmode/Chef/Screenshot_20260816-213635.jpg)
!!ss[Daftar centang — baru sebagian dicentang, tombolnya jadi Simpan Progres](gambar/capture/Darkmode/Chef/Screenshot_20260816-213640.jpg)
!!ss[Seluruh menu tercentang — tombolnya berubah jadi Tandai Pesanan Selesai](gambar/capture/Darkmode/Chef/Screenshot_20260816-213647.jpg)
!!ss[Tab Selesai](gambar/capture/Darkmode/Chef/Screenshot_20260816-213701.jpg)


### A.5 Admin

Admin mengurus isi restonya — menu, harga, banner, QR meja — dan ikut
memegang antrean pembayaran bersama kasir. Yang tidak dia pegang adalah
angka akuntansinya: Info Pembayaran dan Mapping GL milik Finance.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Menu admin** | Kasir, Kelola Produk, Pesanan Masuk, Pending Payment, Riwayat Kasir, Pengaturan, Saldo, Kirim Pengumuman, Diskon |
| **Kelola Produk — tab Produk** | Menambah dan mengubah menu; menandai habis lewat saklar di barisnya, tanpa membuka formulirnya |
| **Tab Kategori** | Menyusun kategori menu |
| **Tab Level** | Mengubah dan menambah kelompok varian milik resto ini — lima kelompok bawaan sudah terisi |
| **Pesanan Masuk** | Melihat seluruh pesanan resto berikut status bayar dan status dapurnya |
| **Pending Payment** | Antrean yang sama dengan kasir: menerima pembayaran Tunai, QRIS, atau Transfer; QR-nya bisa dicetak untuk pelanggan |
| **Pengaturan → Info Resto** | Mengubah nama dan alamat; menggeser pin di pratinjau peta; memilih cara makan yang dilayani — Dine In, Take Away, atau keduanya |
| **Pengaturan → Banner Promo** | Menambah dan mengubah banner berikut gambar, judul, keterangan, urutan tampil, masa berlaku, dan saklar aktif |
| **Pengaturan → QR Meja** | Membuat kartu QR satu meja dengan pratinjau langsung, atau sekaligus banyak meja lalu Download Semua |
| **Pengaturan → Info Pembayaran** | Melihat saja — yang mengubahnya Finance atau Owner |
| **Saldo & Pengeluaran** | Melihat saldo dan petty cash; pengajuan yang menunggu persetujuan Finance ikut terlihat berikut penandanya |
| **Setor Saldo Cash** | Melihat setoran yang sudah dikonfirmasi maupun yang masih menunggu approval |
| **Kirim Pengumuman** | Menulis pengumuman dan memilih sasarannya: Karyawan, Customer, atau Semua |
| **Diskon** | Membuat promo per menu, bundling beberapa menu sekaligus, atau minimum belanja; tiap menu diberi syarat jumlahnya sendiri (Minimal atau Tepat), lalu bentuk potongan dan masa berlakunya |


**Mode Terang** — 19 tangkapan

!!ss[Halaman awal](gambar/capture/Lightmode/Admin/Screenshot_20260816-220213.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Lightmode/Admin/Screenshot_20260816-220220.jpg)
!!ss[Menu admin — Kasir, Kelola Produk, Pesanan Masuk, Pending Payment, Riwayat Kasir, Pengaturan, Saldo](gambar/capture/Lightmode/Admin/Screenshot_20260816-220225.jpg)
!!ss[Kelola Produk tab Produk — saklar di tiap baris menandai habis tanpa membuka formulirnya](gambar/capture/Lightmode/Admin/Screenshot_20260816-220230.jpg)
!!ss[Tab Kategori](gambar/capture/Lightmode/Admin/Screenshot_20260816-220234.jpg)
!!ss[Tab Level — lima kelompok bawaan berikut pilihannya, bisa diubah dan ditambah](gambar/capture/Lightmode/Admin/Screenshot_20260816-220236.jpg)
!!ss[Pending Payment — admin memegang antrean yang sama dengan kasir](gambar/capture/Lightmode/Admin/Screenshot_20260816-220240.jpg)
!!ss[Memilih cara terima pembayaran](gambar/capture/Lightmode/Admin/Screenshot_20260816-220243.jpg)
!!ss[Pelunasan lewat QRIS — QR-nya bisa dicetak untuk diserahkan ke pelanggan](gambar/capture/Lightmode/Admin/Screenshot_20260816-220248.jpg)
!!ss[Antrean kosong; pemberitahuan menyebutkan pesanan lunas lewat QRIS](gambar/capture/Lightmode/Admin/Screenshot_20260816-220255.jpg)
!!ss[Pengaturan — Info Resto, Banner Promo, QR Meja, Info Pembayaran, dan blok Tampilan](gambar/capture/Lightmode/Admin/Screenshot_20260816-220332.jpg)
!!ss[Info Resto — pratinjau peta lokasi dan saklar cara makan yang dilayani](gambar/capture/Lightmode/Admin/Screenshot_20260816-220336.jpg)
!!ss[Banner Promo — daftar banner berikut urutan tampil dan tombol aktif/nonaktif](gambar/capture/Lightmode/Admin/Screenshot_20260816-220340.jpg)
!!ss[Generator QR Meja mode satu meja — pratinjau kartunya berubah saat nomornya diketik](gambar/capture/Lightmode/Admin/Screenshot_20260816-220347.jpg)
!!ss[Info Pembayaran — hanya bisa dilihat; yang mengubah adalah Finance](gambar/capture/Lightmode/Admin/Screenshot_20260816-220350.jpg)
!!ss[Saldo & Pengeluaran](gambar/capture/Lightmode/Admin/Screenshot_20260816-220355.jpg)
!!ss[Setor Saldo Cash — setoran yang sudah dikonfirmasi Finance](gambar/capture/Lightmode/Admin/Screenshot_20260816-220359.jpg)
!!ss[Kirim Pengumuman — pemilih sasaran Karyawan, Customer, atau Semua](gambar/capture/Lightmode/Admin/Screenshot_20260816-220403.jpg)
!!ss[Diskon](gambar/capture/Lightmode/Admin/Screenshot_20260816-220407.jpg)


**Mode Gelap** — 22 tangkapan

!!ss[Halaman awal, tema gelap](gambar/capture/Darkmode/Admin/Screenshot_20260816-214457.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Darkmode/Admin/Screenshot_20260816-214503_Google Play services.jpg)
!!ss[Menu admin](gambar/capture/Darkmode/Admin/Screenshot_20260816-214510.jpg)
!!ss[Kelola Produk tab Produk](gambar/capture/Darkmode/Admin/Screenshot_20260816-214520.jpg)
!!ss[Tab Kategori](gambar/capture/Darkmode/Admin/Screenshot_20260816-214523.jpg)
!!ss[Tab Level](gambar/capture/Darkmode/Admin/Screenshot_20260816-214526.jpg)
!!ss[Pesanan Masuk — seluruh pesanan resto berikut status bayar dan status dapurnya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214537.jpg)
!!ss[Riwayat Kasir](gambar/capture/Darkmode/Admin/Screenshot_20260816-214545.jpg)
!!ss[Pengaturan](gambar/capture/Darkmode/Admin/Screenshot_20260816-214550.jpg)
!!ss[Info Resto berikut pratinjau petanya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214556.jpg)
!!ss[Banner Promo](gambar/capture/Darkmode/Admin/Screenshot_20260816-214603.jpg)
!!ss[Ubah Banner — gambar, judul, keterangan, dan masa berlakunya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214608.jpg)
!!ss[Generator QR Meja mode satu meja](gambar/capture/Darkmode/Admin/Screenshot_20260816-214621.jpg)
!!ss[Mode banyak meja — cukup mengisi jumlah mejanya, lalu Download Semua](gambar/capture/Darkmode/Admin/Screenshot_20260816-214640.jpg)
!!ss[Info Pembayaran](gambar/capture/Darkmode/Admin/Screenshot_20260816-214644.jpg)
!!ss[Saldo & Pengeluaran — pengajuan petty cash yang menunggu persetujuan ikut terlihat](gambar/capture/Darkmode/Admin/Screenshot_20260816-214654.jpg)
!!ss[Rincian petty cash — pengajuan Pending diberi penanda tersendiri](gambar/capture/Darkmode/Admin/Screenshot_20260816-214700.jpg)
!!ss[Setor Saldo Cash — setoran yang masih menunggu approval Finance](gambar/capture/Darkmode/Admin/Screenshot_20260816-214711.jpg)
!!ss[Kirim Pengumuman](gambar/capture/Darkmode/Admin/Screenshot_20260816-214735.jpg)
!!ss[Diskon](gambar/capture/Darkmode/Admin/Screenshot_20260816-214740.jpg)
!!ss[Ubah Diskon berbasis menu — beberapa menu dipilih sekaligus untuk bundling](gambar/capture/Darkmode/Admin/Screenshot_20260816-214752.jpg)
!!ss[Bagian bawah formulir diskon — bentuk potongan dan masa berlakunya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214755.jpg)


### A.6 Keuangan (Finance)

Finance tidak menyentuh pesanan sama sekali. Yang dia pegang adalah dua
titik tempat uang berpindah tangan — setoran tunai ke rekening dan top
up petty cash — dan keduanya sengaja dibuat menunggu persetujuannya.
Selama menunggu, uangnya duduk di akun suspense: sudah tidak ada di
laci, tapi belum diakui masuk.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Menu Finance** | Berpindah resto lewat pemilih di atas — semua angka mengikutinya; penanda merah menunjukkan menu yang sedang menunggu persetujuan |
| **Pemasukan** | Melihat total semua waktu, dirinci per hari dengan pecahan Tunai/QRIS/Transfer |
| **Saldo & Pengeluaran** | Melihat saldo total dan pecahan Cash/Non Cash; menyetujui atau menolak top up petty cash; mencatat pengeluaran; melipat bagian Petty Cash dan Riwayat Pengeluaran |
| **Dialog persetujuan** | Membaca perpindahan yang akan terjadi — dari GL Suspense ke GL tujuannya — sebelum menyetujui, dan menambahkan catatan |
| **Setor Saldo Cash** | Melihat tunai di laci berikut rinciannya; mengonfirmasi atau menolak setoran kasir setelah mencocokkan nominalnya di rekening |
| **Mapping GL Account** | Menetapkan nomor akun untuk tiap cara bayar, petty cash, pajak, service, total saldo, suspense, gateway, dan diskon; mengatur tarif PPN dan biaya service |
| **Pencairan Gateway** | Mencatat dana penyedia pembayaran yang masuk rekening berikut potongan MDR-nya |
| **Jurnal GL** | Membaca jejak audit tiap pergerakan: nomor akun, arah debit/kredit, referensi pesanan, dan pelepasan titipan suspense saat sesuatu disetujui; mencetak atau mengekspornya |
| **Laporan Transaksi** | Memilih rentang tanggal, melihat saldo awal dan akhir, mengekspor PDF |
| **Pengaturan Pembayaran** | Melihat data QRIS dan rekening transfer resto |


**Mode Terang** — 10 tangkapan

!!ss[Halaman awal — masuk sebagai Karyawan Resto](gambar/capture/Lightmode/Finance/Screenshot_20260816-220502.jpg)
!!ss[Menyiapkan data resto setelah masuk](gambar/capture/Lightmode/Finance/Screenshot_20260816-220510.jpg)
!!ss[Pemasukan — total semua waktu, dirinci per hari dengan pecahan Tunai/QRIS](gambar/capture/Lightmode/Finance/Screenshot_20260816-220515.jpg)
!!ss[Menu Finance dengan pemilih resto: semua angka mengikuti resto yang dipilih](gambar/capture/Lightmode/Finance/Screenshot_20260816-220518.jpg)
!!ss[Saldo & Pengeluaran — saldo total, pecahan Cash/Non Cash, Petty Cash & Riwayat Pengeluaran yang bisa dilipat](gambar/capture/Lightmode/Finance/Screenshot_20260816-220521.jpg)
!!ss[Setor Saldo Cash — tunai di laci, rincian yang sudah disetor & dipindah, riwayat setoran](gambar/capture/Lightmode/Finance/Screenshot_20260816-220524.jpg)
!!ss[Mapping GL Account — akun pemasukan per metode bayar dan akun Petty Cash](gambar/capture/Lightmode/Finance/Screenshot_20260816-220527.jpg)
!!ss[Mapping GL Account (lanjutan) — tarif PPN 11% & service 5%, GL Total Saldo, GL Suspense](gambar/capture/Lightmode/Finance/Screenshot_20260816-220531.jpg)
!!ss[Pencairan Gateway — dana penyedia pembayaran yang masuk rekening berikut potongan MDR](gambar/capture/Lightmode/Finance/Screenshot_20260816-220534.jpg)
!!ss[Jurnal GL — saldo GL Total, total debit & kredit, tiap baris dengan nomor akun dan referensi pesanan](gambar/capture/Lightmode/Finance/Screenshot_20260816-220539.jpg)


**Mode Gelap** — 17 tangkapan

!!ss[Halaman awal dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-214907.jpg)
!!ss[Menyiapkan data resto](gambar/capture/Darkmode/Finance/Screenshot_20260816-214910_Google Play services.jpg)
!!ss[Menyiapkan data resto (lanjutan)](gambar/capture/Darkmode/Finance/Screenshot_20260816-214924.jpg)
!!ss[Pemasukan dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-214932.jpg)
!!ss[Menu Finance dengan penanda merah pada menu yang menunggu persetujuan](gambar/capture/Darkmode/Finance/Screenshot_20260816-214936.jpg)
!!ss[Saldo & Pengeluaran — top up petty cash menunggu persetujuan, dengan tombol Setuju/Tolak](gambar/capture/Darkmode/Finance/Screenshot_20260816-214952.jpg)
!!ss[Dialog Setuju top up — menjelaskan perpindahan dari GL Suspense Petty Cash ke GL Petty Cash](gambar/capture/Darkmode/Finance/Screenshot_20260816-214957.jpg)
!!ss[Saldo & Pengeluaran setelah top up disetujui](gambar/capture/Darkmode/Finance/Screenshot_20260816-215003.jpg)
!!ss[Setor Saldo Cash — setoran berstatus Pending menunggu konfirmasi Finance](gambar/capture/Darkmode/Finance/Screenshot_20260816-215019.jpg)
!!ss[Dialog Konfirmasi setoran — mengingatkan mencocokkan nominal di rekening lebih dulu](gambar/capture/Darkmode/Finance/Screenshot_20260816-215026.jpg)
!!ss[Setor Saldo Cash setelah dikonfirmasi — status berubah Completed](gambar/capture/Darkmode/Finance/Screenshot_20260816-215031.jpg)
!!ss[Mapping GL Account dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-215042.jpg)
!!ss[Mapping GL Account (lanjutan) — tarif pajak, GL Total Saldo, GL Suspense](gambar/capture/Darkmode/Finance/Screenshot_20260816-215048.jpg)
!!ss[Pencairan Gateway dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-215052.jpg)
!!ss[Jurnal GL — jejak audit persetujuan: titipan suspense dilepas, dana pindah ke akun tujuan](gambar/capture/Darkmode/Finance/Screenshot_20260816-215058.jpg)
!!ss[Laporan Transaksi — rentang tanggal, saldo awal & akhir, ekspor PDF](gambar/capture/Darkmode/Finance/Screenshot_20260816-215103.jpg)
!!ss[Pengaturan Pembayaran — QRIS dan rekening transfer, hanya bisa dilihat oleh Finance](gambar/capture/Darkmode/Finance/Screenshot_20260816-215107.jpg)


### A.7 Owner

Owner tidak punya layar khusus miliknya sendiri. Yang dia punya adalah
seluruhnya: tiap layar kasir, dapur, admin, dan Finance terbuka untuknya
tanpa perlu ditambahkan peran satu per satu. Menunya karena itu
dikelompokkan tiga — dan pengelompokan itulah yang membedakan
tampilannya dari peran lain.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Pemilih resto** | Berpindah antar resto yang dimilikinya; seluruh isi menu mengikuti yang dipilih |
| **Kelompok PENJUALAN** | Kasir/Input Pesanan, Pesanan Masuk, Layar Dapur, Pending Payment, Riwayat Kasir |
| **Kelompok KEUANGAN** | Pemasukan, Saldo & Pengeluaran, Setor Saldo Cash, Mapping GL Account, Pencairan Gateway, Jurnal GL — sama persis dengan yang dipegang Finance, termasuk hak menyetujui |
| **Kelompok PENGELOLAAN** | Kelola Produk, Pengaturan (termasuk mengubah Info Pembayaran), Kirim Pengumuman, Kotak Masuk berikut jumlah belum dibaca, Diskon, dan Keluar |


**Mode Terang** — 6 tangkapan

!!ss[Halaman awal — masuk sebagai Karyawan Resto](gambar/capture/Lightmode/Owner/Screenshot_20260816-220640.jpg)
!!ss[Menyiapkan data resto setelah masuk](gambar/capture/Lightmode/Owner/Screenshot_20260816-220647.jpg)
!!ss[Pemilih resto — Owner dengan lebih dari satu resto berpindah dari sini](gambar/capture/Lightmode/Owner/Screenshot_20260816-220652.jpg)
!!ss[Menu Owner, kelompok PENJUALAN — Kasir, Pesanan Masuk, Layar Dapur, Pending Payment, Riwayat Kasir](gambar/capture/Lightmode/Owner/Screenshot_20260816-220657.jpg)
!!ss[Kelompok KEUANGAN — akses penuh seperti Finance, termasuk Jurnal GL](gambar/capture/Lightmode/Owner/Screenshot_20260816-220701.jpg)
!!ss[Kelompok PENGELOLAAN — Kelola Produk, Pengaturan, Kirim Pengumuman, Kotak Masuk, Diskon, Keluar](gambar/capture/Lightmode/Owner/Screenshot_20260816-220706.jpg)


**Mode Gelap** — 5 tangkapan

!!ss[Halaman awal dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215153.jpg)
!!ss[Menyiapkan data resto](gambar/capture/Darkmode/Owner/Screenshot_20260816-215159.jpg)
!!ss[Kelompok PENJUALAN dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215204.jpg)
!!ss[Kelompok KEUANGAN dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215208.jpg)
!!ss[Kelompok PENGELOLAAN dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215213.jpg)

*Dokumen ini disusun dari aplikasi versi 1.45.4. Sisi teknisnya —
arsitektur, tabel, keamanan baris, prasyarat basis data — ada di
`SPESIFIKASI-KAATAGO`.*
