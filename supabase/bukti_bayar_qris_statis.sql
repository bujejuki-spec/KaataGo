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
-- Melampirkan bukti
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function lampirkan_bukti_bayar(
  p_order_id text,
  p_jalur text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_o record;
begin
  select * into v_o from orders where id::text = p_order_id;

  if v_o is null then
    raise exception 'Pesanannya tidak ditemukan.';
  end if;

  -- Hanya pesanan yang memang menunggu dibayar lewat QRIS Statis.
  --
  -- Tanpa syarat ini, satu kolom di pesanan mana pun bisa ditimpa oleh
  -- siapa pun yang menebak id-nya — termasuk pesanan yang sudah lunas,
  -- yang buktinya justru jadi bahan sengketa.
  if v_o.payment_method is distinct from 'qris_static' then
    raise exception 'Pesanan ini tidak dibayar lewat QRIS Statis.';
  end if;

  -- 'pending', bukan 'unpaid'. Nilainya ditulis aplikasi dari nama
  -- enum-nya sendiri (OrderPaymentStatus.pending), dan menebak namanya
  -- menghasilkan fungsi yang menolak SETIAP pesanan yang sah.
  if v_o.payment_status is distinct from 'pending' then
    raise exception 'Pesanan ini sudah selesai pembayarannya.';
  end if;

  update orders set bukti_bayar_url = p_jalur where id::text = p_order_id;
end;
$fn$;

-- `anon` memang disengaja: pelanggan yang memesan dari QR meja sering
-- tidak login sama sekali, dan dialah yang memegang buktinya.
revoke all on function lampirkan_bukti_bayar(text, text) from public;
grant execute on function lampirkan_bukti_bayar(text, text)
  to anon, authenticated;

commit;

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
