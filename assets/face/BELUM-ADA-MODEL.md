# Model pengenal wajah — belum dipasang

    assets/face/mobilefacenet.tflite

Berkasnya belum ada. Absensi tetap jalan: menu Absensi terbuka,
mengajukan izin/sakit/cuti tetap bisa, hanya absen wajahnya yang
menunggu berkas ini.

## Kenapa belum dipasang

Percobaan pertama diambil dari sebuah repo GitHub yang **tidak punya
berkas LICENSE sama sekali**. Repo tanpa lisensi berarti hak cipta penuh
pada pemiliknya — tidak ada izin mendistribusikan ulang, dan
menyertakannya di APK yang dijual ke merchant adalah risiko hukum yang
tidak pantas diambil diam-diam. Berkasnya dicabut.

## Dua pertanyaan yang harus dijawab sebelum memasang model apa pun

**1. Lisensi berkasnya.** Yang menerbitkan model harus memberi izin
mendistribusikan ulang. Apache-2.0 atau MIT aman; tanpa lisensi tidak.

**2. Lisensi data latihnya.** Ini yang sering terlewat. Bobot
MobileFaceNet dan FaceNet umumnya dilatih di MS-Celeb-1M — dataset yang
ditarik Microsoft pada 2019 — atau VGGFace2, yang syaratnya penggunaan
riset. Lisensi permisif pada reponya tidak dengan sendirinya menjawab
soal ini.

Pertanyaan kedua keputusan bisnis, bukan keputusan teknis.

## Yang sudah diperiksa dan hasilnya

| Sumber | Lisensi | Format | Catatan |
|---|---|---|---|
| `atharvakale31/Real-Time_Face_Recognition_Android` | **tidak ada** | `.tflite` 5 MB, 112×112 → 192 | bentuknya pas, lisensinya tidak ada |
| `sirius-ai/MobileFaceNet_TF` | Apache-2.0 | `.pb` 5,9 MB | perlu dikonversi ke `.tflite` (butuh TensorFlow) |
| `shubham0204/FaceRecognition_With_FaceNet_Android` | Apache-2.0 | `facenet.tflite` 23 MB, 160×160 → 128 | lisensi bersih, tapi 23 MB dan perlu ubah `_sisi` jadi 160 |
| `qualcomm/MobileFaceNet` (Hugging Face) | Apache-2.0 | lewat Qualcomm AI Hub | perlu akun |

## Syarat berkasnya

- Format TensorFlow Lite (`.tflite`)
- Masukan `[1, 112, 112, 3]`, float −1..1
- Keluaran satu vektor

Kalau panjang keluarannya bukan 192, ganti juga `namaModel` di
`lib/utils/mesin_wajah_tflite.dart`. Nama itu ikut tersimpan di basis
data; sidik dari dua model berbeda tidak bisa dibandingkan.

## Sesudah dipasang

Pengujian di `test/absensi_payroll_test.dart` menyala sendiri dan
memeriksa flatbuffer serta bentuk tensornya. Buat juga berkas
`ASAL-MODEL.md` di folder ini yang menyebut sumber, lisensi, dan
SHA-256-nya.

Lalu periksa di perangkat — ini satu-satunya yang membuktikan modelnya
bekerja:

1. Daftarkan wajahmu, lalu absen masuk — harus diterima
2. Minta orang lain absen memakai akunmu — harus ditolak

Kalau langkah 2 lolos, modelnya tidak layak pakai.
