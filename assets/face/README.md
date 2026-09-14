# Model pengenal wajah

`facenet.tflite` — 22,6 MB, dibundel di APK.

| | |
|---|---|
| Asal | [shubham0204/FaceRecognition_With_FaceNet_Android](https://github.com/shubham0204/FaceRecognition_With_FaceNet_Android) |
| Lisensi | Apache License 2.0 — salinannya di `LICENSE-facenet.txt` |
| SHA-256 | `d7c1f7f130376982c7004920ddc41925ac2e5aecf6522f476c8bbb3669db7013` |
| Masukan | 160 × 160 × 3, float32, diseragamkan per gambar (`(x − rata) / simpangan`) |
| Keluaran | 128 angka, **tidak** dinormalkan panjangnya |
| Dibandingkan dengan | kosinus — bukan jarak Euclid |

## Ambangnya

`0,40` untuk menerima, `0,55` untuk tidak menandai ragu. Angka 0,40
bukan tebakan: itu ambang kosinus yang dipakai aplikasi asalnya sendiri
setelah diuji.

Keduanya hidup di SQL (`_ambang_facenet()`, `_ambang_facenet_yakin()`)
supaya bisa disetel dari SQL Editor tanpa merilis APK.

## Yang perlu diketahui tentang asal-usulnya

Lisensi repo yang mendistribusikannya jelas dan diperiksa: `LICENSE.txt`
asli 201 baris, Apache-2.0, dan berkas modelnya ada di dalam repo yang
sama sehingga ikut tercakup.

Rantai hulunya tidak sejelas itu, dan itu harus tercatat di sini
alih-alih ditemukan lagi dari nol suatu hari nanti. Bobotnya turunan
[`nyoki-mtl/keras-facenet`](https://github.com/nyoki-mtl/keras-facenet),
repo yang **tidak punya berkas LICENSE sama sekali**, dan README-nya
menyebut bobotnya dilatih memakai **MS-Celeb-1M** — dataset yang ditarik
Microsoft pada 2019 karena berisi foto orang yang dikumpulkan tanpa izin.

Alternatifnya sudah ditelusuri dan tidak ada yang lebih bersih:

| Calon | Kenapa tidak |
|---|---|
| MobileFaceNet (atharvakale31) | Repo sumbernya tanpa LICENSE — hak cipta penuh |
| InsightFace / buffalo | Model dibatasi riset non-komersial |
| FaceNet (davidsandberg) | Kode MIT, bobotnya dilatih di VGGFace2 yang juga sudah ditarik |
| ML Kit, MediaPipe | Mendeteksi wajah, tidak mengenali siapa |

Praktis semua model pengenal wajah terbuka dilatih pada data hasil
keruk. Itu keadaan bidangnya, bukan pilihan yang kurang dicari.

Yang menanggung risiko distribusi adalah Apache-2.0 yang jelas itu, dan
soal data latih tidak menyentuh karyawan merchant: wajah mereka tidak
pernah masuk ke data latih siapa pun, cuma dibandingkan di ponsel
sendiri.

## Kenapa bukan mencocokkan bentuk wajah saja

Pernah dicoba, dan gagal — lihat catatan panjangnya di
`supabase/wajah_facenet.sql`. Ringkasnya: tiga orang yang berbeda
berjarak 0,85–0,88 dari skala 0–1, jauh di atas ambang yang dianggap
"yakin orangnya sama". Penyeragaman skalanya membuang justru apa yang
membedakan orang.
