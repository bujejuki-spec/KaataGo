-- KaataGo - foto menu pindah dari kolom tabel ke Storage.
--
-- Aman dijalankan berulang kali.
--
-- Sekarang foto menu tersimpan sebagai `products.photo_base64`, dan itu
-- menempati dua kuota termahal sekaligus:
--
--   1. Ukuran database. Di paket Free jatahnya 500 MB - yang paling
--      sempit dari semua kuota yang ada - sementara file storage
--      jatahnya 1 GB. Foto adalah hal yang paling tidak pantas
--      menempati ruang termahal yang dimiliki proyek ini.
--
--   2. Egress, berulang-ulang. Dan ini yang menentukan: aliran realtime
--      Supabase tidak bisa memilih kolom - `.stream()` selalu mengambil
--      seluruh baris, dan payload perubahannya juga baris utuh. Jadi
--      selama base64 masih ada di sana, tiap foto terkirim ulang tiap
--      kali seorang pelanggan membuka menu, DAN tiap kali satu produk
--      berubah. Menandai satu barang habis mengirim ulang seluruh album
--      ke setiap orang yang sedang membuka menu.
--
-- Foto di Storage disajikan lewat CDN dan masuk hitungan "cached
-- egress" - jatah terpisah, dan tarif kelebihannya sepertiga dari
-- egress biasa.
--
-- Yang TIDAK dikerjakan berkas ini: memindahkan fotonya. Isi berkas
-- tidak bisa diunggah lewat SQL. Pemindahannya dijalankan dari aplikasi,
-- lewat tombol di Kelola Produk, supaya kemajuannya terlihat dan
-- kegagalannya bisa diulang per produk.

begin;

-- Tautan foto di Storage. Null berarti produk ini belum dipindahkan -
-- dan selama itu, `photo_base64`-nya yang dipakai.
alter table products
  add column if not exists photo_url text;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Ember penyimpanannya
-- ─────────────────────────────────────────────────────────────────────
--
-- Publik dibaca siapa saja, dan itu memang yang diinginkan: menu dibuka
-- pelanggan yang belum tentu punya akun, termasuk lewat pemindaian QR
-- meja tanpa memasang aplikasi. Yang publik hanya membacanya - menulis
-- tetap dijaga policy di bawah.

insert into storage.buckets (id, name, public)
values ('menu-foto', 'menu-foto', true)
on conflict (id) do update set public = true;

-- Nama berkasnya berbentuk `<resto_id>/<product_id>.jpg`, dan segmen
-- pertama itu yang dipakai policy untuk menentukan siapa boleh menulis.
-- Tanpa itu, karyawan resto mana pun bisa menimpa foto menu resto lain.

-- Policy SELECT yang terbuka untuk semua sengaja TIDAK dipasang.
--
-- Ember ini publik, dan gambarnya dibaca lewat URL publiknya — jalur itu
-- tidak melewati RLS sama sekali, jadi pelanggan tetap melihat menunya
-- tanpa policy apa pun di sini.
--
-- Yang diberikan policy SELECT justru hal lain: kemampuan MENDAFTAR isi
-- ember. Dengan itu siapa pun bisa meminta daftar seluruh berkas, dan
-- karena namanya `<resto_id>/<product_id>.jpg`, daftar itu membocorkan
-- seluruh id resto dan id produk yang pernah punya foto. Tidak ada yang
-- membutuhkannya: aplikasi ini hanya mengunggah, menyusun URL, dan
-- menghapus — tidak pernah mendaftar.
--
-- Yang tersisa dibatasi ke karyawan restonya sendiri. Layanan Storage
-- membaca baris objeknya saat menimpa berkas yang sudah ada, jadi
-- mencabut SELECT sepenuhnya bisa mematahkan penggantian foto.
drop policy if exists "menu-foto: baca publik" on storage.objects;

drop policy if exists "menu-foto: baca karyawan" on storage.objects;
create policy "menu-foto: baca karyawan" on storage.objects
  for select using (
    bucket_id = 'menu-foto'
    and public.is_resto_employee((storage.foldername(name))[1],
                                 array['owner', 'admin'])
  );

drop policy if exists "menu-foto: tulis karyawan" on storage.objects;
create policy "menu-foto: tulis karyawan" on storage.objects
  for insert with check (
    bucket_id = 'menu-foto'
    -- Disebut lengkap dengan skemanya. Policy pada storage.objects
    -- tidak dijalankan PostgREST melainkan layanan Storage, yang
    -- menyambung dengan search_path-nya sendiri — dan nama tanpa skema
    -- di sana bisa tidak ditemukan. Galatnya baru muncul saat seseorang
    -- benar-benar mengunggah, bukan saat policy-nya dibuat.
    and public.is_resto_employee((storage.foldername(name))[1],
                                 array['owner', 'admin'])
  );

drop policy if exists "menu-foto: ubah karyawan" on storage.objects;
create policy "menu-foto: ubah karyawan" on storage.objects
  for update using (
    bucket_id = 'menu-foto'
    -- Disebut lengkap dengan skemanya. Policy pada storage.objects
    -- tidak dijalankan PostgREST melainkan layanan Storage, yang
    -- menyambung dengan search_path-nya sendiri — dan nama tanpa skema
    -- di sana bisa tidak ditemukan. Galatnya baru muncul saat seseorang
    -- benar-benar mengunggah, bukan saat policy-nya dibuat.
    and public.is_resto_employee((storage.foldername(name))[1],
                                 array['owner', 'admin'])
  );

drop policy if exists "menu-foto: hapus karyawan" on storage.objects;
create policy "menu-foto: hapus karyawan" on storage.objects
  for delete using (
    bucket_id = 'menu-foto'
    -- Disebut lengkap dengan skemanya. Policy pada storage.objects
    -- tidak dijalankan PostgREST melainkan layanan Storage, yang
    -- menyambung dengan search_path-nya sendiri — dan nama tanpa skema
    -- di sana bisa tidak ditemukan. Galatnya baru muncul saat seseorang
    -- benar-benar mengunggah, bukan saat policy-nya dibuat.
    and public.is_resto_employee((storage.foldername(name))[1],
                                 array['owner', 'admin'])
  );

-- ─────────────────────────────────────────────────────────────────────
-- Sesudah semua foto pindah
-- ─────────────────────────────────────────────────────────────────────
--
-- Kolom base64-nya sengaja TIDAK dikosongkan di sini.
--
-- Aplikasi versi lama yang masih terpasang di HP orang membaca
-- `photo_base64`, dan tidak tahu apa-apa tentang `photo_url`. Mengosongkan
-- kolomnya hari ini membuat menu mereka kehilangan seluruh gambarnya
-- sampai mereka memperbarui aplikasinya - dan sebagian tidak akan
-- memperbarui selama berminggu-minggu.
--
-- Jalankan perintah di bawah HANYA setelah pemindahannya selesai dan
-- versi barunya sudah tersebar. Sebelum itu dijalankan, ukuran database
-- dan beban egress-nya belum berkurang: yang mengurangi bukan adanya
-- photo_url, melainkan hilangnya base64 dari barisnya.
--
--   update products set photo_base64 = null
--    where photo_url is not null and photo_base64 is not null;
--
-- Periksa dulu berapa yang belum pindah, dan jangan kosongkan kalau
-- angkanya belum nol:
--
--   select count(*) filter (where photo_url is null and photo_base64 is not null)
--            as belum_pindah,
--          count(*) filter (where photo_url is not null) as sudah_pindah
--     from products;
