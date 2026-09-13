-- KaataGo - paket langganan Basic dan Premium, berikut masa percobaan.
--
-- Jalankan SETELAH billing.sql, uam_menu.sql, dan cara_tagih.sql.
-- Aman diulang.
--
-- ── Yang sudah ada dan tidak diulang di sini ─────────────────────────
--
-- Penagihan bulanan, tagihan berikut unggah bukti, pemeriksaan oleh
-- KaataGo, dan penguncian saat lewat tenggang — semuanya sudah berdiri
-- di billing.sql. Berkas ini tidak membangun ulang satu pun di antaranya.
-- Yang ditambahkan cuma tiga hal: paketnya, masa percobaannya, dan
-- pengajuan berlangganan yang menjembatani keduanya.
--
-- ── Kenapa merchant lama tidak ikut terkunci ─────────────────────────
--
-- Semua merchant yang sudah berjalan hari ini tidak punya paket. Kalau
-- "tidak punya paket" langsung berarti terkunci, memasang berkas ini
-- mengunci seluruh merchant sekaligus — pada hari yang tidak mereka
-- ketahui, karena harga apa pun.
--
-- Jadi penguncian paket hanya berlaku bagi merchant yang memang sudah
-- dimasukkan ke jalurnya, yaitu yang pernah diberi masa percobaan oleh
-- KaataGo Admin (`trial_until` terisi). Yang belum pernah disentuh
-- berjalan persis seperti kemarin. Prinsipnya sama dengan menu_access:
-- baris yang tidak ada berarti tidak ada pembatasan.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Paket dan harganya
-- ─────────────────────────────────────────────────────────────────────

begin;

create table if not exists paket_langganan (
  kode text primary key check (kode in ('basic', 'premium')),
  nama text not null,
  harga_bulanan bigint not null check (harga_bulanan >= 0),
  keterangan text,
  urutan smallint not null default 0,
  updated_at timestamptz not null default now(),
  updated_by text
);

-- Harganya disimpan di basis data, bukan ditulis di aplikasi.
--
-- Harga yang tertanam di kode berarti menaikkannya menuntut merilis
-- APK baru — dan selama sebagian merchant belum memperbarui
-- aplikasinya, dua merchant akan melihat dua harga berbeda untuk paket
-- yang sama.
insert into paket_langganan (kode, nama, harga_bulanan, keterangan, urutan)
values
  ('basic', 'Basic', 99000,
   'Penjualan, shift kasir, dan keuangan harian. Cukup untuk warung yang '
   'ingin kasirnya rapi tanpa pembukuan penuh.', 1),
  ('premium', 'Premium', 249000,
   'Seluruh fitur KaataGo: pembukuan lengkap, laporan bergrafik, absensi '
   'wajah, payroll, dan semua yang menyusul.', 2)
on conflict (kode) do nothing;

alter table paket_langganan enable row level security;

-- Dibaca siapa pun yang sudah masuk. Merchant yang sedang memilih paket
-- perlu melihat harganya, dan harga langganan bukan rahasia.
drop policy if exists "paket: baca" on paket_langganan;
create policy "paket: baca" on paket_langganan
  for select using (auth.uid() is not null);

drop policy if exists "paket: super admin ubah" on paket_langganan;
create policy "paket: super admin ubah" on paket_langganan
  for all using (is_super_admin()) with check (is_super_admin());

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Paket dan masa percobaan menempel di setelan langganannya
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Null berarti belum berlangganan paket mana pun.
alter table resto_billing add column if not exists paket text;

alter table resto_billing drop constraint if exists resto_billing_paket_check;
alter table resto_billing add constraint resto_billing_paket_check
  check (paket is null or paket in ('basic', 'premium'));

-- Hari terakhir masa percobaan, sudah termasuk. Null berarti merchant
-- ini memang tidak pernah dimasukkan ke jalur paket.
alter table resto_billing add column if not exists trial_until date;

-- Berapa hari yang diberikan waktu itu. Disimpan supaya layar KaataGo
-- Admin bisa menyebut "14 hari" alih-alih menghitung mundur sendiri
-- dari tanggal yang sudah lewat.
alter table resto_billing add column if not exists trial_days integer;

-- Siapa yang menulis baris menu_access-nya.
--
-- Dibutuhkan supaya menaikkan paket ke Premium bisa membersihkan
-- pembatasan yang dipasang paket, tanpa ikut menghapus pengaturan yang
-- disetel tangan KaataGo Admin untuk merchant itu.
alter table menu_access add column if not exists sumber text not null
  default 'manual';

alter table menu_access drop constraint if exists menu_access_sumber_check;
alter table menu_access add constraint menu_access_sumber_check
  check (sumber in ('manual', 'paket'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Pengajuan berlangganan
-- ─────────────────────────────────────────────────────────────────────

begin;

create table if not exists subscription_requests (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  paket text not null check (paket in ('basic', 'premium')),

  -- Harga saat diajukan, disalin.
  --
  -- Bukan dibaca ulang dari paket_langganan saat disetujui: harga bisa
  -- naik di antara merchant menekan tombol dan KaataGo memeriksanya,
  -- dan yang sudah mentransfer sesuai angka di layarnya tidak pantas
  -- ditagih selisihnya.
  harga bigint not null check (harga >= 0),

  -- 'verifikasi' → bukti sudah diunggah, menunggu diperiksa KaataGo
  -- 'selesai'    → diterima, paketnya berjalan
  -- 'ditolak'    → buktinya tidak cocok, merchant bisa mengajukan lagi
  status text not null default 'verifikasi'
    check (status in ('verifikasi', 'selesai', 'ditolak')),

  -- Wajib. Pengajuan tanpa bukti transfer adalah pengajuan yang tidak
  -- bisa diperiksa siapa pun, dan yang menumpuk dari situ adalah
  -- antrean berisi permintaan yang harus ditanyakan satu per satu.
  bukti_url text not null,

  catatan text,

  diajukan_oleh text,
  diajukan_at timestamptz not null default now(),

  diputuskan_oleh text,
  diputuskan_at timestamptz,
  alasan_tolak text
);

create index if not exists idx_subscription_requests_status
  on subscription_requests (status, diajukan_at desc);
create index if not exists idx_subscription_requests_resto
  on subscription_requests (resto_id, diajukan_at desc);

-- Satu pengajuan menunggu per merchant.
--
-- Tanpa ini, tombol yang ditekan dua kali karena jaringannya lambat
-- menjadi dua antrean untuk uang yang sama — dan yang memeriksanya
-- menyetujui keduanya.
create unique index if not exists idx_subscription_requests_satu_aktif
  on subscription_requests (resto_id) where status = 'verifikasi';

alter table subscription_requests enable row level security;

-- Merchant membaca pengajuannya sendiri; KaataGo Admin membaca semua.
drop policy if exists "subscription_requests: baca" on subscription_requests;
create policy "subscription_requests: baca" on subscription_requests
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

-- Ditulis lewat fungsi, bukan langsung: barisnya menentukan uang dan
-- akses, dan yang bisa menyisipkannya sendiri bisa menyisipkan yang
-- statusnya sudah 'selesai'.
drop policy if exists "subscription_requests: tulis" on subscription_requests;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Menu apa saja yang dibuka paket Basic
-- ─────────────────────────────────────────────────────────────────────
--
-- Ditulis sebagai daftar putih, bukan daftar hitam. Fitur baru muncul
-- terus di aplikasi ini; daftar hitam berarti tiap fitur baru otomatis
-- ikut terbuka untuk Basic sampai ada yang ingat menambahkannya ke
-- daftar — dan yang menemukannya adalah merchant Basic yang memakai
-- fitur Premium tanpa membayarnya.
--
-- Kotak Masuk, Tampilan, Penilaian Pelanggan, KaataGo Support, dan
-- Keluar tidak ada di sini karena memang tidak pernah ada di
-- menu_access: kelimanya selalu tersedia untuk semua orang.

begin;

create or replace function _menu_paket_basic()
returns text[]
language sql
immutable
as $$
  select array[
    -- Penjualan
    'Kasir / Input Pesanan',
    'Layar Pelanggan',
    'Pending Payment',
    'Riwayat Kasir',
    'Pesanan Masuk',
    -- Shift kasir
    'Shift Kasir',
    -- Keuangan harian
    'Saldo & Pengeluaran',
    'Setor Saldo Cash',
    -- Info merchant dan info pembayaran
    'Info Merchant',
    'Pengaturan Pembayaran',
    -- Absensi dirinya sendiri tetap dibuka: ia bukan fitur pembukuan,
    -- dan mengunci orang dari menyatakan dirinya sudah datang bekerja
    -- adalah pembatasan yang menyakiti orang yang salah.
    'Absensi'
  ];
$$;

-- Menuliskan pembatasan paket ke menu_access.
--
-- Premium tidak menulis apa pun — ia justru menghapus pembatasan yang
-- pernah dipasang paket, dan membiarkan pengaturan tangan KaataGo Admin
-- berdiri seperti semula.
create or replace function terapkan_paket(
  p_resto_id text,
  p_paket text,
  p_oleh text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_oleh text := coalesce(p_oleh, auth.jwt() ->> 'email', 'sistem');
begin
  -- Yang dipasang paket dibuang dulu, apa pun paketnya. Menumpuknya
  -- berarti merchant yang turun dari Premium ke Basic tetap membawa
  -- pembukaan yang diberikan Premium.
  delete from menu_access
  where resto_id = p_resto_id and sumber = 'paket';

  if p_paket <> 'basic' then
    return;
  end if;

  -- Semua menu yang dikenal, per peran, yang TIDAK ada di daftar putih
  -- ditutup. Daftar menunya diambil dari baris yang sudah pernah ada
  -- ditambah katalog tetap di bawah — karena basis data tidak tahu
  -- katalog menu aplikasi, daftarnya disebut di sini.
  insert into menu_access (resto_id, role, menu_key, level, sumber,
                           updated_by, updated_at)
  select p_resto_id, peran, menu, 'none', 'paket', v_oleh, now()
  from unnest(array['owner', 'admin', 'finance', 'kasir', 'chef']) peran
  cross join unnest(_menu_semua()) menu
  where not (menu = any (_menu_paket_basic()))
  on conflict (resto_id, role, menu_key) do update
    set level = 'none', sumber = 'paket',
        updated_by = excluded.updated_by, updated_at = now();
end;
$fn$;

-- Seluruh menu yang dikenal aplikasi.
--
-- Disebut di sini, bukan dibaca dari mana-mana: basis data tidak bisa
-- melihat katalog menu di dalam APK. Yang menjaga keduanya tetap sama
-- adalah pengujian di sisi aplikasi (`test/paket_langganan_test.dart`),
-- yang gagal begitu ada menu di katalog yang belum disebut di sini.
create or replace function _menu_semua()
returns text[]
language sql
immutable
as $$
  select array[
    'Shift Kasir', 'Kasir / Input Pesanan', 'Layar Pelanggan',
    'Pending Payment', 'Riwayat Kasir', 'Pesanan Masuk', 'Layar Dapur',
    'Laporan Penjualan', 'Pemasukan', 'Saldo & Pengeluaran',
    'Setor Saldo Cash', 'Terima Cash Pickup', 'Saldo Perusahaan',
    'Pembayaran dari KaataGo', 'Periksa Pembukuan', 'Tutup Buku',
    'Rekonsiliasi Bank', 'Mapping GL Account', 'Jurnal GL',
    'Laporan Transaksi', 'Pencairan Gateway', 'Tagihan Langganan',
    'Kelola Produk', 'Kelola Karyawan', 'Diskon', 'Kirim Pengumuman',
    'Kategori', 'Level', 'Info Merchant', 'QR Meja',
    'Pengaturan Pembayaran', 'Rekening Perusahaan',
    'Absensi', 'Absensi Karyawan', 'Payroll'
  ];
$$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 5. KaataGo Admin menyetel paket dan masa percobaan
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function set_paket_resto(
  p_resto_id text,
  p_paket text,
  p_harga bigint default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_harga bigint;
begin
  if not is_super_admin() then
    raise exception 'Hanya KaataGo Admin yang bisa menyetel paket.';
  end if;

  if p_paket is not null and p_paket not in ('basic', 'premium') then
    raise exception 'Paketnya harus basic atau premium.';
  end if;

  v_harga := coalesce(
    p_harga,
    (select harga_bulanan from paket_langganan where kode = p_paket),
    0);

  insert into resto_billing (resto_id, paket, monthly_price, active)
  values (p_resto_id, p_paket, v_harga, p_paket is not null)
  on conflict (resto_id) do update
    set paket = excluded.paket,
        monthly_price = excluded.monthly_price,
        -- Melepas paket tidak mematikan penagihannya diam-diam: yang
        -- dimatikan cuma kalau memang tidak ada paket sama sekali.
        active = case when excluded.paket is null then resto_billing.active
                      else true end,
        updated_at = now();

  perform terapkan_paket(p_resto_id, coalesce(p_paket, 'premium'));
end;
$fn$;

-- Memberi masa percobaan, dihitung dari hari ini.
create or replace function set_trial_resto(
  p_resto_id text,
  p_hari integer)
returns date
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_sampai date;
begin
  if not is_super_admin() then
    raise exception 'Hanya KaataGo Admin yang bisa memberi masa percobaan.';
  end if;

  if p_hari is null or p_hari < 1 or p_hari > 365 then
    raise exception 'Lama percobaannya antara 1 dan 365 hari.';
  end if;

  v_sampai := (now() at time zone 'Asia/Jakarta')::date + p_hari;

  insert into resto_billing (resto_id, trial_until, trial_days, monthly_price)
  values (p_resto_id, v_sampai, p_hari, 0)
  on conflict (resto_id) do update
    set trial_until = excluded.trial_until,
        trial_days = excluded.trial_days,
        updated_at = now();

  -- Selama percobaan, semuanya terbuka. Percobaan yang separuh terkunci
  -- tidak memperlihatkan apa yang sedang ditawarkan.
  perform terapkan_paket(p_resto_id, 'premium');

  return v_sampai;
end;
$fn$;

grant execute on function set_paket_resto(text, text, bigint) to authenticated;
grant execute on function set_trial_resto(text, integer) to authenticated;

-- Pembantu, bukan pintu.
--
-- Postgres memberi EXECUTE ke PUBLIC secara bawaan, dan terapkan_paket
-- adalah SECURITY DEFINER tanpa pemeriksaan izin di dalamnya — ia memang
-- mengandalkan ketiga pemanggilnya yang sudah memeriksa KaataGo Admin
-- lebih dulu. Tanpa pencabutan ini, siapa pun yang sudah masuk bisa
-- memanggilnya sendiri dan menghapus seluruh pembatasan paket sebuah
-- merchant.
--
-- Mencabutnya tidak mematahkan pemanggilnya: fungsi SECURITY DEFINER
-- berjalan sebagai pemiliknya, bukan sebagai pemanggilnya.
revoke all on function terapkan_paket(text, text, text)
  from public, anon, authenticated;
revoke all on function _menu_semua() from public, anon;
revoke all on function _menu_paket_basic() from public, anon;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 6. Merchant mengajukan, KaataGo memutuskan
-- ─────────────────────────────────────────────────────────────────────

begin;

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

  if exists (select 1 from subscription_requests
             where resto_id = p_resto_id and status = 'verifikasi') then
    raise exception 'Pengajuanmu yang sebelumnya masih diperiksa.';
  end if;

  select harga_bulanan into v_harga from paket_langganan where kode = p_paket;
  if v_harga is null then
    raise exception 'Paket % tidak dikenal.', p_paket;
  end if;

  insert into subscription_requests (
    resto_id, paket, harga, bukti_url, catatan, diajukan_oleh)
  values (p_resto_id, p_paket, v_harga, btrim(p_bukti_url), p_catatan, v_email)
  returning id into v_id;

  return v_id;
end;
$fn$;

create or replace function putuskan_langganan(
  p_request_id uuid,
  p_setuju boolean,
  p_alasan text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_req record;
  v_hari smallint;
  v_mulai date;
  v_jatuh date;
begin
  if not is_super_admin() then
    raise exception 'Hanya KaataGo Admin yang bisa memutuskan pengajuan.';
  end if;

  select * into v_req from subscription_requests where id = p_request_id;
  if v_req is null then
    raise exception 'Pengajuannya tidak ditemukan.';
  end if;
  if v_req.status <> 'verifikasi' then
    raise exception 'Pengajuan ini sudah diputuskan.';
  end if;

  if not p_setuju then
    if p_alasan is null or btrim(p_alasan) = '' then
      raise exception 'Sebutkan alasannya — merchant perlu tahu apa yang '
                      'harus diperbaiki.';
    end if;
    update subscription_requests
    set status = 'ditolak',
        diputuskan_oleh = v_email,
        diputuskan_at = now(),
        alasan_tolak = btrim(p_alasan)
    where id = p_request_id;
    return;
  end if;

  -- Disetujui: paketnya berjalan mulai hari ini.
  v_mulai := (now() at time zone 'Asia/Jakarta')::date;
  v_hari := least(greatest(extract(day from v_mulai)::smallint, 1), 28);

  insert into resto_billing (
    resto_id, paket, monthly_price, billing_day, active, started_on,
    trial_until)
  values (v_req.resto_id, v_req.paket, v_req.harga, v_hari, true, v_mulai, null)
  on conflict (resto_id) do update
    set paket = excluded.paket,
        monthly_price = excluded.monthly_price,
        billing_day = excluded.billing_day,
        active = true,
        started_on = excluded.started_on,
        -- Masa percobaannya dilepas: ia sudah berlangganan, dan
        -- membiarkannya membuat layar merchant tetap menghitung mundur
        -- sesuatu yang sudah tidak berlaku.
        trial_until = null,
        updated_at = now();

  perform terapkan_paket(v_req.resto_id, v_req.paket, v_email);

  -- Bulan pertama sudah dibayar — itulah yang barusan diperiksa. Jadi
  -- tagihannya dicatat lunas, bukan diterbitkan sebagai utang baru.
  -- Tanpa ini merchant yang baru saja transfer langsung melihat tagihan
  -- yang menuntutnya membayar lagi.
  v_jatuh := v_mulai;
  insert into billing_invoices (
    id, resto_id, period_start, period_end, due_date, amount,
    status, submitted_at, confirmed_by, confirmed_at, paid_note)
  values (
    v_req.resto_id || '-' || to_char(v_mulai, 'YYYYMM') || '-langganan',
    v_req.resto_id, v_mulai, (v_mulai + interval '1 month' - interval '1 day')::date,
    v_jatuh, v_req.harga, 'paid', v_req.diajukan_at, v_email, now(),
    'Pembayaran paket ' || v_req.paket || ' saat berlangganan')
  on conflict (resto_id, period_start) do update
    set status = 'paid',
        confirmed_by = excluded.confirmed_by,
        confirmed_at = now();

  update subscription_requests
  set status = 'selesai',
      diputuskan_oleh = v_email,
      diputuskan_at = now()
  where id = p_request_id;
end;
$fn$;

grant execute on function ajukan_langganan(text, text, text, text)
  to authenticated;
grant execute on function putuskan_langganan(uuid, boolean, text)
  to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 7. Keadaan langganan satu merchant
-- ─────────────────────────────────────────────────────────────────────
--
-- Fungsi tersendiri, bukan menambah kolom ke `resto_billing_state`.
--
-- Mengubah tipe kembalian fungsi yang sudah ada menuntut membuangnya
-- dulu, dan berkas yang harus dijalankan dalam urutan tertentu supaya
-- tidak gagal berhenti jadi berkas yang aman diulang — persis jebakan
-- yang sudah dicatat billing.sql tentang dirinya sendiri.

begin;

create or replace function keadaan_langganan(p_resto_id text)
returns table (
  paket text,
  nama_paket text,
  harga bigint,
  trial_until date,
  trial_days integer,
  sisa_hari integer,
  dalam_percobaan boolean,
  percobaan_habis boolean,
  status_pengajuan text,
  alasan_tolak text,
  terkunci_paket boolean
)
language sql
stable
security definer
set search_path = public
as $$
  -- Hanya untuk merchant sendiri.
  --
  -- Tanpa ini, id resto yang ditebak orang menjawab paket, harga, dan
  -- masa percobaan merchant lain. Yang tidak berhak menerima baris
  -- kosong, bukan galat: pesan galat justru mengonfirmasi restonya ada.
  with boleh as (
    select is_super_admin()
        or is_resto_employee(p_resto_id,
             array['owner', 'admin', 'finance', 'kasir', 'chef']) as ya
  ),
  s as (
    select * from resto_billing where resto_id = p_resto_id
  ),
  r as (
    select status, alasan_tolak
    from subscription_requests
    where resto_id = p_resto_id
    order by diajukan_at desc
    limit 1
  ),
  hari as (
    select (now() at time zone 'Asia/Jakarta')::date as ini
  )
  select
    s.paket,
    p.nama,
    coalesce(p.harga_bulanan, s.monthly_price, 0),
    s.trial_until,
    s.trial_days,
    (s.trial_until - h.ini)::integer,
    coalesce(s.paket is null and s.trial_until is not null
             and h.ini <= s.trial_until, false),
    coalesce(s.paket is null and s.trial_until is not null
             and h.ini > s.trial_until, false),
    r.status,
    case when r.status = 'ditolak' then r.alasan_tolak end,
    -- Terkunci karena paket: percobaannya habis dan belum berlangganan.
    --
    -- Pengajuan yang sedang diperiksa TIDAK membuka kuncinya, dan itu
    -- memang yang diminta — tapi ia juga tidak menguncinya sendiri.
    -- Merchant yang masih dalam masa percobaan lalu mengajukan lebih
    -- awal tetap bisa bekerja sampai percobaannya benar-benar habis.
    coalesce(s.paket is null and s.trial_until is not null
             and h.ini > s.trial_until, false)
  from hari h
  cross join boleh b
  left join s on true
  left join paket_langganan p on p.kode = s.paket
  left join r on true
  where b.ya;
$$;

-- Penguncian paket ikut ditegakkan RLS, bukan cuma oleh layar.
--
-- Layar yang terkunci hanyalah layar. Tanpa baris ini, merchant yang
-- masa percobaannya habis tetap bisa menyimpan pesanan lewat versi
-- aplikasi lama — dan yang menemukannya bukan kita.
create or replace function is_resto_billing_locked(p_resto_id text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when is_super_admin() then false
    else coalesce((select locked from resto_billing_state(p_resto_id)), false)
      or coalesce((select terkunci_paket from keadaan_langganan(p_resto_id)),
                  false)
  end;
$$;

grant execute on function keadaan_langganan(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 8. Pemberitahuan H-2
-- ─────────────────────────────────────────────────────────────────────
--
-- Pengumuman yang ditujukan ke satu merchant, bukan ke semua.
--
-- `app_announcements` selama ini selalu untuk semua orang. Kolom di
-- bawah membuatnya bisa disempitkan — null tetap berarti semua, jadi
-- seluruh pengumuman yang sudah ada tidak berubah artinya.

begin;

alter table app_announcements add column if not exists resto_id text;

drop policy if exists "announcements: public read" on app_announcements;
create policy "announcements: public read" on app_announcements
  for select using (
    resto_id is null
    or is_super_admin()
    or is_resto_employee(resto_id,
         array['owner', 'admin', 'finance', 'kasir', 'chef'])
  );

commit;

begin;

-- Dijalankan sekali sehari. Menyapa merchant yang masa percobaannya
-- tinggal dua hari lagi dan belum berlangganan.
create or replace function ingatkan_percobaan_habis()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_jumlah integer := 0;
  v_resto record;
  v_ini date := (now() at time zone 'Asia/Jakarta')::date;
begin
  for v_resto in
    select b.resto_id, b.trial_until, r.name
    from resto_billing b
    join restaurants r on r.id = b.resto_id
    where b.paket is null
      and b.trial_until is not null
      and b.trial_until - v_ini = 2
  loop
    -- Sekali per merchant per masa percobaan. Pengumuman yang sama
    -- dikirim ulang tiap kali cron-nya jalan akan memenuhi kotak masuk
    -- dengan kalimat yang sama persis.
    if exists (
      select 1 from app_announcements
      where resto_id = v_resto.resto_id
        and title = 'Masa percobaan tinggal 2 hari'
        and created_at > now() - interval '7 days'
    ) then
      continue;
    end if;

    insert into app_announcements (title, body, audience, resto_id, created_by)
    values (
      'Masa percobaan tinggal 2 hari',
      'Masa percobaan ' || coalesce(v_resto.name, 'merchant Anda') ||
      ' berakhir ' || to_char(v_resto.trial_until, 'DD Mon YYYY') || '. ' ||
      'Pilih paket langganan sekarang supaya aplikasinya tidak berhenti ' ||
      'bisa dipakai — buka menu Langganan di aplikasi.',
      'employees', v_resto.resto_id, 'sistem');

    v_jumlah := v_jumlah + 1;
  end loop;

  return v_jumlah;
end;
$fn$;

-- Dipanggil pg_cron sebagai pemilik jadwalnya, bukan oleh aplikasi.
revoke all on function ingatkan_percobaan_habis()
  from public, anon, authenticated;

commit;

-- Dijadwalkan jam 9 pagi WIB (02:00 UTC): jam kerja, bukan tengah malam
-- saat tidak ada yang membuka aplikasinya.
select cron.unschedule('kaatago-ingat-percobaan')
where exists (
  select 1 from cron.job where jobname = 'kaatago-ingat-percobaan');

select cron.schedule('kaatago-ingat-percobaan', '0 2 * * *',
  $cron$ select ingatkan_percobaan_habis(); $cron$);

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from keadaan_langganan('<resto_id>');
--   select resto_id, paket, trial_until, monthly_price from resto_billing;
--   select * from subscription_requests where status = 'verifikasi';
