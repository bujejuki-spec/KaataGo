-- KaataGo - pelanggan membayar QRIS Statis dari HP-nya sendiri.
--
-- Jalankan kapan saja. Aman diulang.
--
-- ── Apa yang berubah ─────────────────────────────────────────────────
--
-- Sebelumnya QRIS Statis diperlakukan sama persis dengan tunai: pesanan
-- masuk, lalu pelanggan disuruh ke meja kasir. Padahal justru QRIS yang
-- paling tidak perlu ke kasir — QR-nya bisa dipindai dari HP sendiri,
-- dan buktinya ada di HP itu juga.
--
-- Sekarang pelanggan melihat QR merchant di layarnya, membayar, lalu
-- mengunggah bukti transfernya. Yang memastikan tetap kasir, karena QR
-- statis tidak membawa nominal dan tidak ada kabar apa pun yang datang
-- dari penyedia pembayaran.
--
-- ── Kenapa fungsi, bukan melonggarkan kebijakan `orders` ─────────────
--
-- UPDATE pada `orders` menuntut karyawan resto. Pelanggan — apalagi tamu
-- yang tidak login — tidak termasuk, dan memang tidak boleh: tabel itu
-- juga memuat status dapur, total, dan diskon. Melonggarkannya supaya
-- satu kolom bisa diisi berarti membuka seluruh barisnya.
--
-- Fungsi di bawah hanya menyentuh satu kolom, dan hanya untuk pesanan
-- yang memang sedang menunggu dibayar lewat QRIS Statis.

begin;

alter table orders add column if not exists bukti_bayar_url text;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Melampirkan bukti — PINDAH ke gambar_base64.sql
-- ─────────────────────────────────────────────────────────────────────
--
-- `lampirkan_bukti_bayar` dulu didefinisikan di sini, menyimpan JALUR
-- berkas di Storage. Sejak gambar unggahan pindah ke base64, fungsinya
-- menulis ke kolom yang berbeda — dan definisinya ikut pindah.
--
-- Sengaja tidak ditinggalkan salinannya di sini. Dua berkas yang
-- mendefinisikan satu fungsi berarti mana yang berlaku bergantung pada
-- urutan dijalankannya, dan yang kalah tidak pernah berbunyi: ia cuma
-- menulis ke kolom yang tidak dibaca siapa pun.

-- ─────────────────────────────────────────────────────────────────────
-- Ember bukti bayar
-- ─────────────────────────────────────────────────────────────────────
--
-- Tertutup, tidak seperti `qris-statis` yang memang gambar publik.
-- Bukti transfer memuat nama pengirim, nomor rekening sebagian, dan
-- nominalnya — tidak satu pun pantas bisa dibuka siapa saja yang
-- menebak alamatnya.

begin;

insert into storage.buckets (id, name, public)
values ('bukti-bayar', 'bukti-bayar', false)
on conflict (id) do update set public = false;

-- Menulis: siapa pun, TAPI hanya ke pesanan yang benar-benar ada,
-- belum lunas, dan memang memilih QRIS Statis.
--
-- Jalurnya `<resto_id>/<order_id>.jpg`, dan kedua bagiannya diperiksa.
-- Ember yang menerima tulisan tanpa syarat adalah tempat penyimpanan
-- gratis bagi siapa pun yang menemukannya.
drop policy if exists "bukti bayar: pelanggan menulis" on storage.objects;
create policy "bukti bayar: pelanggan menulis" on storage.objects
  for insert with check (
    bucket_id = 'bukti-bayar'
    and exists (
      select 1 from public.orders o
      -- `o.id::text`, bukan sebaliknya. Nama berkas yang bukan uuid
      -- akan MELEMPAR galat kalau dipaksa jadi uuid — dan galat di
      -- dalam kebijakan storage mematikan unggahan untuk semua orang,
      -- bukan cuma untuk yang salah menamai.
      where o.id::text = split_part((storage.foldername(name))[2], '.', 1)
        and o.resto_id = (storage.foldername(name))[1]
        and o.payment_method = 'qris_static'
        and o.payment_status = 'pending'
    )
  );

-- Membaca: yang memutuskan pembayarannya.
--
-- Kasir ikut, dan memang harus: dialah yang menyatakan lunas setelah
-- melihat buktinya. Chef tidak — antrean dapur tidak berurusan dengan
-- bukti transfer siapa pun.
drop policy if exists "bukti bayar: kasir membaca" on storage.objects;
create policy "bukti bayar: kasir membaca" on storage.objects
  for select using (
    bucket_id = 'bukti-bayar'
    and (
      public.is_super_admin()
      or public.is_resto_employee((storage.foldername(name))[1],
           array['owner', 'admin', 'finance', 'kasir'])
    )
  );

-- Mengubah: pelanggan yang salah unggah boleh menimpanya, dengan syarat
-- yang sama persis seperti menulis.
drop policy if exists "bukti bayar: pelanggan menimpa" on storage.objects;
create policy "bukti bayar: pelanggan menimpa" on storage.objects
  for update using (
    bucket_id = 'bukti-bayar'
    and exists (
      select 1 from public.orders o
      -- `o.id::text`, bukan sebaliknya. Nama berkas yang bukan uuid
      -- akan MELEMPAR galat kalau dipaksa jadi uuid — dan galat di
      -- dalam kebijakan storage mematikan unggahan untuk semua orang,
      -- bukan cuma untuk yang salah menamai.
      where o.id::text = split_part((storage.foldername(name))[2], '.', 1)
        and o.resto_id = (storage.foldername(name))[1]
        and o.payment_method = 'qris_static'
        and o.payment_status = 'pending'
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select column_name from information_schema.columns
--   where table_name = 'orders' and column_name = 'bukti_bayar_url';
--
--   select id, public from storage.buckets where id = 'bukti-bayar';
--
--   select policyname, cmd from pg_policies
--   where tablename = 'objects' and policyname like 'bukti bayar%';
--
-- Yang benar: ember-nya TIDAK publik, dan ada tiga kebijakan —
-- menulis, membaca, menimpa.
