-- KaataGo - gambar unggahan disimpan sebagai base64, bukan di Storage.
--
-- Jalankan kapan saja. Aman diulang.
--
-- ── Yang berubah ─────────────────────────────────────────────────────
--
-- Semua gambar yang diunggah orang kini tersimpan di basis data sebagai
-- base64: bukti bayar pelanggan, bukti transfer langganan, foto absensi
-- berikut surat sakitnya, QR statis merchant, dan foto menu.
--
-- Batasnya 2 MB SESUDAH dikecilkan, dan hanya JPG atau PNG yang
-- diterima — diperiksa dari isi berkasnya, bukan dari nama.
--
-- ── Kenapa foto menu punya TABELNYA SENDIRI ──────────────────────────
--
-- Kolom `products.photo_base64` masih ada, dan justru kolom itulah yang
-- dulu jadi masalah: aliran realtime Supabase tidak bisa memilih kolom.
-- `.stream()` selalu mengirim BARIS UTUH, dan payload perubahannya juga
-- baris utuh. Selama fotonya di sana, menandai satu barang habis berarti
-- mengirim ulang seluruh album ke setiap pelanggan yang sedang membuka
-- menu.
--
-- Dengan batas 2 MB per foto, menu berisi 30 produk berarti puluhan MB
-- terkirim ulang tiap kali stok berubah. Itu bukan kelambatan kecil;
-- itu kuota pelanggan.
--
-- Jadi fotonya berdiri di tabel terpisah yang TIDAK pernah dialirkan.
-- Baris produk tetap ringan, dan fotonya diambil sekali lalu diingat.
-- Jangan kembalikan ke `products` — kolom lamanya sengaja dibiarkan
-- kosong sebagai peninggalan, bukan sebagai tempat yang boleh dipakai
-- lagi.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Kolom base64 di samping kolom lamanya
-- ─────────────────────────────────────────────────────────────────────
--
-- Kolom lama TIDAK dibuang. Baris yang sudah terlanjur menunjuk ke
-- Storage masih bisa dibaca, dan yang membacanya memilih mana yang ada:
-- base64 dulu, jalur lama sebagai cadangan. Membuangnya sekarang berarti
-- bukti absensi dan bukti transfer bertahun lalu berubah jadi kotak
-- kosong pada hari berkas ini dijalankan.

alter table orders add column if not exists bukti_bayar_base64 text;

alter table subscription_requests add column if not exists bukti_base64 text;

alter table attendance
  add column if not exists masuk_foto_base64 text,
  add column if not exists pulang_foto_base64 text,
  add column if not exists bukti_base64 text;

alter table employee_faces add column if not exists foto_base64 text;

alter table settings add column if not exists qris_static_base64 text;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Foto menu, di tabelnya sendiri
-- ─────────────────────────────────────────────────────────────────────

begin;

create table if not exists product_photos (
  product_id text primary key,
  resto_id text not null,
  base64 text not null,
  updated_at timestamptz not null default now()
);

create index if not exists product_photos_resto_idx
  on product_photos (resto_id);

alter table product_photos enable row level security;

-- Membaca: siapa pun, termasuk pelanggan yang belum login.
--
-- Menu memang dipajang untuk umum — foto produk bukan rahasia, dan
-- pelanggan yang memindai QR meja tidak punya akun.
drop policy if exists "product_photos: baca umum" on product_photos;
create policy "product_photos: baca umum" on product_photos
  for select using (true);

-- Menulis: karyawan resto yang bersangkutan.
--
-- `resto_id` diperiksa, bukan sekadar "karyawan mana pun" — tanpa itu,
-- karyawan resto lain bisa menimpa foto menu resto ini.
drop policy if exists "product_photos: karyawan menulis" on product_photos;
create policy "product_photos: karyawan menulis" on product_photos
  for all using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin'])
  ) with check (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin'])
  );

grant select on product_photos to anon, authenticated;
grant insert, update, delete on product_photos to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Pelanggan melampirkan bukti bayarnya sendiri
-- ─────────────────────────────────────────────────────────────────────
--
-- Menggantikan versi yang menyimpan jalur Storage. Syaratnya sama
-- persis: hanya pesanan yang benar-benar ada, belum lunas, dan memang
-- memilih QRIS Statis.

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

  if v_o.payment_method is distinct from 'qris_static' then
    raise exception 'Pesanan ini tidak dibayar lewat QRIS Statis.';
  end if;

  if v_o.payment_status is distinct from 'pending' then
    raise exception 'Pesanan ini sudah selesai pembayarannya.';
  end if;

  -- Batas ukurannya ditegakkan di sini juga, bukan cuma di aplikasi.
  --
  -- Aplikasi memang sudah mengecilkan dan memeriksanya, tapi fungsi ini
  -- terbuka untuk `anon`: yang memanggilnya langsung bisa mengirim apa
  -- saja. Base64 membengkak kira-kira sepertiga, jadi 2 MB berkas
  -- menjadi sekitar 2,8 MB teks.
  if length(p_jalur) > 3000000 then
    raise exception 'Bukti bayarnya terlalu besar.';
  end if;

  update orders set bukti_bayar_base64 = p_jalur where id::text = p_order_id;
end;
$fn$;

revoke all on function lampirkan_bukti_bayar(text, text) from public;
grant execute on function lampirkan_bukti_bayar(text, text)
  to anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select column_name from information_schema.columns
--   where column_name like '%base64%' order by table_name;
--
--   select policyname, cmd from pg_policies where tablename='product_photos';
--
-- Dan yang paling penting — baris produk harus tetap RINGAN:
--
--   select pg_size_pretty(avg(pg_column_size(p.*))::bigint) from products p;
--
-- Kalau angka itu melonjak, fotonya kembali masuk ke baris produk, dan
-- seluruh album akan terkirim ulang tiap kali stok berubah.

-- ─────────────────────────────────────────────────────────────────────
-- 4. Fungsi yang menyimpan gambar ikut pindah kolom
-- ─────────────────────────────────────────────────────────────────────
--
-- Tanda tangannya SENGAJA tidak diubah. Nama parameternya memang jadi
-- sedikit usang — `p_bukti_url` kini membawa base64, bukan jalur — tapi
-- mengubah daftar parameter berarti membuat fungsi KEDUA dengan nama
-- yang sama, dan aplikasi yang belum diperbarui memanggil yang lama
-- tanpa satu pun galat yang menjelaskan kenapa buktinya tidak muncul.
--
-- Yang berubah cuma kolom yang ditulis.

begin;

create or replace function ajukan_tidak_masuk(
  p_resto_id text,
  p_tanggal date,
  p_status text,
  p_alasan text,
  p_bukti_url text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if v_email = '' then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id, peran_karyawan()) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  if p_status not in ('izin', 'sakit', 'cuti') then
    raise exception 'Statusnya harus izin, sakit, atau cuti.';
  end if;

  if p_tanggal > (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Belum bisa mengajukan untuk tanggal yang belum tiba.';
  end if;

  if length(coalesce(p_bukti_url, '')) > 3000000 then
    raise exception 'Bukti suratnya terlalu besar.';
  end if;

  -- Hari yang sudah terlanjur absen masuk tidak bisa diubah jadi izin
  -- oleh yang bersangkutan sendiri. Kalau memang keliru, atasannya yang
  -- membetulkan — dan itu meninggalkan jejak siapa yang mengubahnya.
  if exists (select 1 from attendance
             where resto_id = p_resto_id
               and lower(employee_email) = v_email
               and tanggal = p_tanggal
               and masuk_at is not null) then
    raise exception 'Hari itu sudah tercatat masuk. Minta Admin yang '
                    'membetulkannya.';
  end if;

  insert into attendance (
    resto_id, employee_email, tanggal, status, alasan, bukti_base64)
  values (p_resto_id, v_email, p_tanggal, p_status, p_alasan, p_bukti_url)
  on conflict (resto_id, employee_email, tanggal) do update
    set status = excluded.status,
        alasan = excluded.alasan,
        bukti_base64 =
          coalesce(excluded.bukti_base64, attendance.bukti_base64);
end;
$fn$;

create or replace function ajukan_langganan(
  p_resto_id text,
  p_paket text,
  p_bukti_url text,
  p_catatan text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_harga bigint;
  v_id uuid;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  -- Owner saja. Berlangganan adalah keputusan yang mengikat merchantnya
  -- pada pembayaran bulanan, dan itu bukan keputusan yang pantas bisa
  -- diambil setiap orang yang bisa menambah menu.
  if not (is_super_admin() or is_resto_employee(p_resto_id, array['owner'])) then
    raise exception 'Hanya Owner yang bisa berlangganan.';
  end if;

  if p_paket not in ('basic', 'premium') then
    raise exception 'Paketnya harus Basic atau Premium.';
  end if;

  if p_bukti_url is null or btrim(p_bukti_url) = '' then
    raise exception 'Bukti transfernya wajib diunggah.';
  end if;

  if length(p_bukti_url) > 3000000 then
    raise exception 'Bukti transfernya terlalu besar.';
  end if;

  if exists (select 1 from subscription_requests
             where resto_id = p_resto_id and status = 'verifikasi') then
    raise exception 'Pengajuanmu yang sebelumnya masih diperiksa.';
  end if;

  select harga_bulanan into v_harga from paket_langganan where kode = p_paket;
  if v_harga is null then
    raise exception 'Paket % tidak dikenal.', p_paket;
  end if;

  insert into subscription_requests (
    resto_id, paket, harga, bukti_base64, catatan, diajukan_oleh)
  values (p_resto_id, p_paket, v_harga, btrim(p_bukti_url), p_catatan, v_email)
  returning id into v_id;

  return v_id;
end;
$fn$;

commit;
