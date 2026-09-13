# Model pengenal wajah

Absensi wajah membutuhkan satu berkas di folder ini:

    assets/face/mobilefacenet.tflite

Berkasnya **tidak ikut di dalam repo ini**, dan itu disengaja.

## Kenapa tidak ikut

Model pengenal wajah adalah berkas biner yang dijalankan di perangkat
setiap karyawan. Menariknya dari cermin GitHub acak lalu memasukkannya ke
APK berarti memercayai seseorang yang tidak dikenal dengan kode yang
berjalan di HP orang lain — dan keputusan semacam itu bukan keputusan
yang pantas diambil diam-diam oleh siapa pun yang kebetulan sedang
menulis kodenya.

Jadi yang memilih sumbernya adalah yang memegang produknya.

## Syarat berkasnya

- Format TensorFlow Lite (`.tflite`)
- Masukan `[1, 112, 112, 3]`, nilai float −1..1
- Keluaran satu vektor, panjang berapa pun (MobileFaceNet: 192)

Kalau modelnya menghasilkan panjang selain 192, ganti juga `namaModel` di
`lib/utils/mesin_wajah_tflite.dart` — nama itu ikut tersimpan di basis
data, dan sidik dari dua model berbeda tidak bisa dibandingkan.

## Selama berkasnya belum ada

Aplikasinya tetap bisa dibangun dan dijalankan. Menu Absensi tampil,
menjelaskan bahwa modelnya belum terpasang, dan tidak menawarkan tombol
yang akan gagal saat ditekan.
