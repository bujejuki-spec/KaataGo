-- ═══════════════════════════════════════════════════════════════════════
-- KaataGo — satu berkas, jalankan sekali dari atas ke bawah.
-- ═══════════════════════════════════════════════════════════════════════
--
-- ⚠ POTRET SEKALI PAKAI, bukan sumber kebenaran.
--
-- Isinya salinan lima berkas di `supabase/` pada saat gabungan ini
-- dibuat. Begitu salah satunya diubah, berkas ini basi — dan berkas
-- gabungan yang basi berbahaya justru karena ia tetap berjalan tanpa
-- galat, lalu menimpa fungsi dengan versi lama.
--
-- Aman diulang: semuanya memakai `create or replace`, `add column if
-- not exists`, dan `drop policy if exists`.
--
-- ── Urutannya BUKAN sembarang ─────────────────────────────────────────
--
-- `foto_acuan_wajah` ditulis dengan `language sql`, dan Postgres
-- memvalidasi badan fungsi semacam itu saat dibuat — bukan saat
-- dipanggil. Kalau kolom `employee_faces.foto_base64` belum ada, fungsi
-- itu ditolak dan seluruh sisa berkas ini batal.
--
-- Karena itu yang menambah kolom berjalan paling dulu:
--
--   1. paket_langganan         daftar menu UAM (Status Pesanan)
--   2. gambar_base64           kolom base64 + tabel product_photos
--   3. wajah_geometri          ambang, _mirip_geometri, foto_acuan_wajah
--   4. wajah_facenet           daftar_wajah & _absen (menimpa yang di 3)
--   5. bukti_bayar_qris_statis ember lama + kebijakannya
--
-- Bagian 4 memang menimpa sebagian isi bagian 3, dan itu disengaja:
-- bagian 3 masih memuat versi lama fungsi absen dari cara pencocokan
-- sebelumnya.


-- ════════════════════════════════════════════════════════════════════
-- BAGIAN 1 dari 5 — paket_langganan.sql — HANYA daftar menunya
-- ════════════════════════════════════════════════════════════════════
--
-- Yang berubah di berkas itu cuma satu nama menu: 'Layar Dapur' jadi
-- 'Status Pesanan'. Jadi yang dibawa ke sini cuma fungsi yang memuatnya.
--
-- ── Kenapa bukan seluruh berkasnya ────────────────────────────────
--
-- `paket_langganan.sql` juga memuat `keadaan_langganan`, dan versi di
-- sana sudah ketinggalan: ia belum mengenal penghentian langganan.
-- Membawanya ke sini berarti mengembalikan fungsi itu ke versi lama —
-- dan kalau bentuk kembaliannya kebetulan sama, Postgres akan
-- melakukannya tanpa satu pun galat, lalu fitur berhenti berlangganan
-- mati diam-diam. Yang menyelamatkan kita kali ini justru galatnya:
-- bentuk kembaliannya memang sudah berbeda.
--
-- Pemilik sahnya `supabase/hentikan_langganan.sql`, dan ia sudah
-- terpasang. Tidak ada alasan menjalankan ulang 760 baris skema yang
-- tidak berubah hanya untuk mengganti satu nama menu.

begin;

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
    'Pending Payment', 'Riwayat Kasir', 'Pesanan Masuk', 'Status Pesanan',
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

revoke all on function _menu_semua() from public, anon;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 2 dari 5 — gambar_base64.sql
-- ═══════════════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 3 dari 5 — wajah_geometri.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo - mencocokkan wajah dari bentuknya, tanpa model terlatih.
--
-- Jalankan SETELAH absensi_payroll.sql dan wajah_tidak_kembar.sql.
-- Aman diulang.
--
-- ── Kenapa bukan kosinus ─────────────────────────────────────────────
--
-- Sidik dari model terlatih adalah vektor abstrak, dan kemiripan
-- kosinus memang alat yang tepat untuknya.
--
-- Yang dikirim aplikasi sekarang bukan itu: ia deretan KOORDINATA titik
-- wajah yang sudah diluruskan dan diseragamkan skalanya. Kosinus atas
-- koordinat semacam itu mendekati 1 untuk siapa pun — karena semua
-- wajah memang berbentuk wajah, dan arah vektornya nyaris sama meski
-- orangnya berbeda. Yang dibandingkan berhenti berarti apa-apa, dan
-- semua orang lolos.
--
-- Yang benar jarak bentuknya: seberapa jauh tiap titik bergeser dari
-- titik pasangannya. Itu yang dihitung di bawah.
--
-- ── Ambangnya bisa disetel tanpa merilis APK ─────────────────────────
--
-- Angka di bawah ini tebakan awal yang belum diuji pada wajah
-- sungguhan. Keduanya sengaja berdiri sebagai fungsi tersendiri supaya
-- bisa disetel dari SQL Editor begitu terlihat kenyataannya — tanpa
-- membangun ulang aplikasi dan tanpa menunggu semua merchant
-- memperbaruinya.
--
-- Cara menyetelnya ada di bagian "Memeriksanya" di bawah.

begin;

-- Seberapa jauh pergeseran yang masih dianggap orang yang sama.
--
-- Satuannya jarak antarmata: 0,30 berarti pergeseran rata-rata sebesar
-- 30% jarak antarmata sudah dianggap orang lain.
create or replace function _skala_geo()
returns double precision language sql immutable as
$$ select 0.30::double precision $$;

-- Di bawah ini absennya DITOLAK.
create or replace function _ambang_geo()
returns double precision language sql immutable as
$$ select 0.60::double precision $$;

-- Di bawah ini absennya diterima tapi DITANDAI ragu, supaya atasannya
-- memeriksa fotonya.
--
-- Ada pita di antara "jelas orangnya" dan "jelas bukan" — dan menolak
-- semua yang jatuh di situ berarti mengunci orang dari pekerjaannya
-- karena cahaya pagi yang berbeda. Yang ragu dicatat, bukan ditolak.
create or replace function _ambang_geo_yakin()
returns double precision language sql immutable as
$$ select 0.72::double precision $$;

revoke all on function _skala_geo() from public, anon;
revoke all on function _ambang_geo() from public, anon;
revoke all on function _ambang_geo_yakin() from public, anon;

-- Kemiripan dua bentuk wajah, 0 sampai 1.
--
-- Akar rata-rata kuadrat pergeseran tiap titik, lalu dibalik jadi
-- kemiripan. Panjang yang berbeda berarti tidak sebanding sama sekali —
-- dijawab 0, bukan dipaksa dibandingkan sebagian.
create or replace function _mirip_geometri(
  a double precision[], b double precision[])
returns double precision
language sql
immutable
as $$
  select case
    when a is null or b is null
      or array_length(a, 1) is distinct from array_length(b, 1)
      or coalesce(array_length(a, 1), 0) = 0
      then 0
    else greatest(0, 1 - sqrt((
      select avg((x - y) * (x - y)) from unnest(a, b) as t(x, y)
    )) / _skala_geo())
  end;
$$;

-- Satu pintu untuk dua cara membandingkan.
--
-- Mana yang dipakai ditentukan nama modelnya, bukan ditebak dari isi
-- vektornya. Sidik dari dua cara berbeda tidak sebanding, dan
-- membandingkannya menghasilkan penolakan yang tidak bisa dijelaskan ke
-- orangnya.
create or replace function _mirip(
  a double precision[], b double precision[], p_model text)
returns double precision
language sql
immutable
as $$
  select case
    when coalesce(p_model, '') like 'geometri-%' then _mirip_geometri(a, b)
    else _mirip_wajah(a, b)
  end;
$$;

create or replace function _ambang(p_model text)
returns double precision
language sql
stable
as $$
  select case
    when coalesce(p_model, '') like 'geometri-%' then _ambang_geo()
    else _ambang_wajah()
  end;
$$;

revoke all on function _mirip(double precision[], double precision[], text)
  from public, anon;
revoke all on function _ambang(text) from public, anon;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Absen memakai cara yang sesuai modelnya
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Ditandai saat kemiripannya jatuh di pita ragu-ragu.
--
-- Bukan penolakan, dan bukan pula dibiarkan lewat begitu saja: baris
-- yang ditandai muncul menonjol di layar Absensi Karyawan berikut foto
-- acuan dan foto absennya bersebelahan, supaya yang memutuskan gaji
-- bisa melihat sendiri dalam dua detik.
alter table attendance add column if not exists masuk_ragu boolean
  not null default false;
alter table attendance add column if not exists pulang_ragu boolean
  not null default false;

create or replace function _absen(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_pulang boolean)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_resto record;
  v_setelan record;
  v_wajah record;
  v_skor double precision;
  v_ragu boolean;
  v_jarak double precision;
  v_peran text;
  v_wajib_dekat boolean;
  v_tanggal date := (now() at time zone 'Asia/Jakarta')::date;
  v_sekarang timestamptz := now();
begin
  if v_email = '' then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       array['owner', 'admin', 'finance', 'kasir', 'chef']) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  select latitude, longitude, name into v_resto
  from restaurants where id = p_resto_id;

  if v_resto.latitude is null or v_resto.longitude is null then
    raise exception 'Titik lokasi merchant belum disetel. Minta Admin '
                    'menyetelnya di menu Profil Merchant dulu.';
  end if;

  if p_lat is null or p_lng is null then
    raise exception 'Lokasimu tidak terbaca. Nyalakan GPS lalu coba lagi.';
  end if;

  select * into v_setelan from payroll_settings where resto_id = p_resto_id;

  v_jarak := _jarak_meter(v_resto.latitude, v_resto.longitude, p_lat, p_lng);

  -- Admin dan Finance tidak diikat radius.
  --
  -- Radiusnya ada supaya kasir dan dapur benar-benar berada di merchant
  -- saat menyatakan dirinya masuk. Admin dan Finance sering tidak: satu
  -- kantor pusat bisa mengurus beberapa merchant sekaligus, dan
  -- mengikat mereka ke titik salah satu merchant berarti menyuruh
  -- mereka pergi ke sana tiap pagi untuk pekerjaan yang tidak dikerjakan
  -- di sana.
  --
  -- Titik GPS-nya TETAP dicatat. Yang dilepas cuma penolakannya, bukan
  -- pencatatannya — kalau suatu hari ada yang perlu ditelusuri, yang
  -- dibutuhkan justru titik itu.
  select e.role into v_peran
  from employees e
  where e.resto_id = p_resto_id and lower(e.email) = v_email
  limit 1;

  v_wajib_dekat := coalesce(v_peran, '') not in ('admin', 'finance');

  if v_wajib_dekat and v_jarak > coalesce(v_setelan.radius_absen_m, 150) then
    raise exception 'Kamu % meter dari %. Absen hanya bisa dalam radius % meter.',
      round(v_jarak), coalesce(v_resto.name, 'merchant'),
      coalesce(v_setelan.radius_absen_m, 150);
  end if;

  select * into v_wajah from employee_faces
  where resto_id = p_resto_id and lower(employee_email) = v_email;

  if v_wajah is null then
    raise exception 'Wajahmu belum terdaftar. Daftarkan dulu di menu Absensi.';
  end if;

  v_skor := _mirip(v_wajah.embedding, p_embedding, v_wajah.model);

  if v_skor < _ambang(v_wajah.model) then
    raise exception 'Wajahnya tidak cocok dengan yang terdaftar. '
                    'Hadapkan wajahmu lurus ke kamera dengan cahaya yang '
                    'cukup, lalu coba lagi.';
  end if;

  -- Diterima, tapi belum tentu meyakinkan.
  v_ragu := coalesce(v_wajah.model, '') like 'geometri-%'
            and v_skor < _ambang_geo_yakin();

  if p_pulang then
    update attendance
    set pulang_at = v_sekarang,
        pulang_lat = p_lat,
        pulang_lng = p_lng,
        pulang_jarak_m = round(v_jarak),
        pulang_skor = v_skor,
        pulang_ragu = v_ragu,
        pulang_foto_url = coalesce(p_foto_url, pulang_foto_url)
    where resto_id = p_resto_id
      and lower(employee_email) = v_email
      and tanggal = v_tanggal
      and masuk_at is not null;

    if not found then
      raise exception 'Belum ada absen masuk hari ini.';
    end if;
  else
    insert into attendance (
      resto_id, employee_email, tanggal, status,
      masuk_at, masuk_lat, masuk_lng, masuk_jarak_m, masuk_skor,
      masuk_ragu, masuk_foto_url)
    values (
      p_resto_id, v_email, v_tanggal, 'hadir',
      v_sekarang, p_lat, p_lng, round(v_jarak), v_skor, v_ragu, p_foto_url)
    on conflict (resto_id, employee_email, tanggal) do update
      set status = 'hadir',
          masuk_at = coalesce(attendance.masuk_at, excluded.masuk_at),
          masuk_lat = coalesce(attendance.masuk_lat, excluded.masuk_lat),
          masuk_lng = coalesce(attendance.masuk_lng, excluded.masuk_lng),
          masuk_jarak_m =
            coalesce(attendance.masuk_jarak_m, excluded.masuk_jarak_m),
          masuk_skor = coalesce(attendance.masuk_skor, excluded.masuk_skor),
          masuk_ragu = coalesce(attendance.masuk_ragu, excluded.masuk_ragu),
          masuk_foto_url =
            coalesce(attendance.masuk_foto_url, excluded.masuk_foto_url),
          potong_gaji = false,
          alasan = null;
  end if;

  return query select round(v_jarak)::integer, v_skor, v_sekarang;
end;
$fn$;

revoke all on function _absen(text, double precision[], double precision,
  double precision, text, boolean) from public, anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pendaftaran ikut memakai cara yang sesuai
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function daftar_wajah(
  p_resto_id text,
  p_embedding double precision[],
  p_model text default 'geometri-mlkit-v1',
  p_foto_url text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_model text := coalesce(p_model, 'geometri-mlkit-v1');
  v_kembar record;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       array['owner', 'admin', 'finance', 'kasir', 'chef']) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  if p_embedding is null or array_length(p_embedding, 1) is null then
    raise exception 'Sidik wajahnya kosong. Ulangi pemindaian.';
  end if;

  if exists (select 1 from employee_faces
             where resto_id = p_resto_id
               and lower(employee_email) = lower(v_email)) then
    raise exception 'Wajahmu sudah terdaftar. Minta Owner atau Admin '
                    'mereset dulu kalau memang perlu didaftar ulang.';
  end if;

  -- Terlalu mirip dengan rekan satu merchant berarti salah satu dari
  -- dua hal, dan keduanya harus dihentikan di sini: wajah orang lain
  -- yang didaftarkan, atau cara pencocokan yang tidak membedakan siapa
  -- pun. Yang kedua adalah kegagalan paling berbahaya, karena ia tidak
  -- pernah membuat siapa pun mengeluh.
  select employee_email,
         _mirip(embedding, p_embedding, v_model) as skor
    into v_kembar
  from employee_faces
  where resto_id = p_resto_id and model = v_model
  order by _mirip(embedding, p_embedding, v_model) desc
  limit 1;

  if v_kembar.employee_email is not null
     and v_kembar.skor >= _ambang_kembar() then
    raise exception 'Wajah ini terlalu mirip dengan karyawan lain yang '
                    'sudah terdaftar. Minta Owner atau Admin memeriksanya.';
  end if;

  insert into employee_faces (
    resto_id, employee_email, embedding, model, foto_url)
  values (p_resto_id, lower(v_email), p_embedding, v_model, p_foto_url);
end;
$fn$;

revoke all on function daftar_wajah(text, double precision[], text, text)
  from public, anon;
grant execute on function daftar_wajah(text, double precision[], text, text)
  to authenticated;

-- Foto acuan yang terdaftar, untuk disandingkan dengan foto absennya.
--
-- Fungsi tersendiri karena `employee_faces` sengaja tidak punya satu pun
-- kebijakan SELECT: sidik yang bisa dibaca aplikasi adalah sidik yang
-- bisa dikirim balik sebagai hasil pemindaian. Yang dibuka di sini cuma
-- URL fotonya, dan cuma untuk yang memang memeriksa absensi.
drop function if exists foto_acuan_wajah(text);
create or replace function foto_acuan_wajah(p_resto_id text)
returns table (
  employee_email text,
  foto_url text,
  foto_base64 text,
  registered_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  -- Keduanya dikembalikan, bukan salah satu.
  --
  -- Wajah yang didaftarkan sebelum gambar pindah ke base64 masih
  -- menunjuk ke berkas di Storage. Mengembalikan yang baru saja berarti
  -- foto acuan mereka berubah jadi kotak kosong — tepat di layar tempat
  -- seseorang memutuskan absen ini benar orangnya atau bukan.
  select f.employee_email, f.foto_url, f.foto_base64, f.registered_at
  from employee_faces f
  where f.resto_id = p_resto_id
    and (is_super_admin()
         or is_resto_employee(p_resto_id,
              array['owner', 'admin', 'finance', 'hr'])
         or lower(f.employee_email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

grant execute on function foto_acuan_wajah(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya, dan menyetel ambangnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Angka ambang di atas belum diuji pada wajah sungguhan. Sesudah
-- beberapa hari absen berjalan, lihat sebarannya:
--
--   select round(masuk_skor::numeric, 2) as skor, count(*)
--   from attendance
--   where resto_id = '<resto_id>' and masuk_skor is not null
--   group by 1 order by 1;
--
-- Yang diharapkan: gumpalan tinggi di atas 0,75 (orangnya sendiri), dan
-- nyaris kosong di bawah 0,60.
--
--   - Banyak yang ditolak padahal orangnya benar → turunkan _ambang_geo()
--   - Ada yang lolos padahal bukan orangnya      → naikkan _ambang_geo()
--
-- Kemiripan antarkaryawan seharusnya jauh di bawah ambangnya. Yang
-- mendekati 1 untuk semua pasangan berarti caranya tidak membedakan
-- siapa pun, dan absensinya tidak membuktikan apa-apa:
--
--   select a.employee_email, b.employee_email,
--          round(_mirip(a.embedding, b.embedding, a.model)::numeric, 3)
--   from employee_faces a join employee_faces b
--     on a.resto_id = b.resto_id and a.employee_email < b.employee_email
--   where a.resto_id = '<resto_id>';


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 4 dari 5 — wajah_facenet.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo - wajah dicocokkan dengan model terlatih, dan didaftarkan
-- hanya setelah orangnya menyetujuinya.
--
-- Jalankan SETELAH wajah_geometri.sql. Aman diulang.
--
-- ── Kenapa cara yang lama harus dibuang ──────────────────────────────
--
-- Cara sebelumnya membandingkan BENTUK wajah: titik kontur dari ML Kit,
-- diluruskan di garis mata dan diseragamkan skalanya. Angka ambangnya
-- saya pasang berdasarkan vektor buatan, bukan wajah sungguhan.
--
-- Begitu ada tiga wajah asli di basis data, ia terbantah seketika:
--
--   kaatatemanjajan  vs  kahfi.gamal22     0,8849
--   ethereumluther   vs  kahfi.gamal22     0,8646
--   ethereumluther   vs  kaatatemanjajan   0,8478
--
-- Tiga orang yang BERBEDA, semuanya jauh di atas ambang "yakin" 0,72 —
-- jadi mereka tidak cuma lolos, mereka lolos tanpa ditandai ragu. Dalam
-- satuan jarak antarmata, wajah mereka cuma berselisih 3-5%, kira-kira
-- sebesar goyangan kontur ML Kit antara dua foto orang yang SAMA di
-- cahaya yang berbeda.
--
-- Tidak ada celah yang bisa disetel di situ. Penyeragaman skalanya
-- membuang justru apa yang membedakan orang, dan yang tersisa cuma
-- "berbentuk wajah" — dan semua orang berbentuk wajah.
--
-- Yang menggantikannya FaceNet: model terlatih, 128 angka, dijalankan
-- di ponsel lewat TensorFlow Lite. Fotonya tidak ke mana-mana; yang
-- masuk model adalah piksel di RAM, yang keluar 128 angka.
--
-- ── Sidik lama tidak bisa dibandingkan dengan yang baru ──────────────
--
-- Dua cara yang berbeda menghasilkan angka yang tidak sebanding sama
-- sekali. Membandingkannya tetap mengeluarkan bilangan — dan bilangan
-- itulah yang paling berbahaya, karena ia terlihat seperti jawaban.
--
-- Jadi wajah yang terdaftar dengan cara lama DITOLAK di sini, berikut
-- pesan yang menyuruh mendaftar ulang. Bukan dibiarkan lewat.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Ambangnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Angka 0,40 bukan tebakan: itu ambang kosinus yang dipakai aplikasi
-- asal modelnya sendiri setelah diuji. Sidik FaceNet TIDAK dinormalkan
-- panjangnya, jadi yang dipakai kosinus, bukan jarak Euclid.
--
-- Keduanya berdiri sebagai fungsi tersendiri supaya bisa disetel dari
-- SQL Editor begitu terlihat sebaran nyatanya — tanpa membangun ulang
-- aplikasi dan tanpa menunggu semua merchant memperbaruinya.

-- Di bawah ini absennya DITOLAK.
create or replace function _ambang_facenet()
returns double precision language sql immutable as
$$ select 0.40::double precision $$;

-- Di bawah ini diterima tapi DITANDAI ragu, supaya atasannya memeriksa
-- fotonya sendiri.
--
-- Ada pita di antara "jelas orangnya" dan "jelas bukan", dan menolak
-- semua yang jatuh di situ berarti mengunci orang dari pekerjaannya
-- karena cahaya pagi yang berbeda. Yang ragu dicatat, bukan ditolak.
create or replace function _ambang_facenet_yakin()
returns double precision language sql immutable as
$$ select 0.55::double precision $$;

-- Ambang "terlalu mirip dengan rekan" yang mengikuti modelnya.
--
-- Fungsi bernama BARU, bukan _ambang_kembar() dengan parameter tambahan.
-- `create or replace` dengan daftar parameter yang berbeda tidak menimpa
-- apa pun — ia membuat fungsi KEDUA dengan nama yang sama, dan mana
-- yang terpanggil kemudian bergantung pada pencocokan tipe.
create or replace function _ambang_kembar_model(p_model text)
returns double precision
language sql
stable
as $$
  select case
    when coalesce(p_model, '') like 'facenet-%' then 0.75::double precision
    else _ambang_kembar()
  end;
$$;

revoke all on function _ambang_facenet() from public, anon;
revoke all on function _ambang_facenet_yakin() from public, anon;
revoke all on function _ambang_kembar_model(text) from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- Satu pintu untuk memilih cara membandingkan
-- ─────────────────────────────────────────────────────────────────────

create or replace function _mirip(
  a double precision[], b double precision[], p_model text)
returns double precision
language sql
immutable
as $$
  select case
    when coalesce(p_model, '') like 'facenet-%' then _mirip_wajah(a, b)
    when coalesce(p_model, '') like 'geometri-%' then _mirip_geometri(a, b)
    else _mirip_wajah(a, b)
  end;
$$;

create or replace function _ambang(p_model text)
returns double precision
language sql
stable
as $$
  select case
    when coalesce(p_model, '') like 'facenet-%' then _ambang_facenet()
    when coalesce(p_model, '') like 'geometri-%' then _ambang_geo()
    else _ambang_wajah()
  end;
$$;

create or replace function _ambang_yakin(p_model text)
returns double precision
language sql
stable
as $$
  select case
    when coalesce(p_model, '') like 'facenet-%' then _ambang_facenet_yakin()
    when coalesce(p_model, '') like 'geometri-%' then _ambang_geo_yakin()
    else _ambang_wajah()
  end;
$$;

revoke all on function _mirip(double precision[], double precision[], text)
  from public, anon;
revoke all on function _ambang(text) from public, anon;
revoke all on function _ambang_yakin(text) from public, anon;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Persetujuan sebelum wajahnya didaftarkan
-- ─────────────────────────────────────────────────────────────────────
--
-- Wajah adalah data pribadi yang bersifat spesifik menurut UU 27/2022.
-- Mengambilnya tanpa persetujuan yang sah bukan cuma soal etika, dan
-- persetujuan yang sah berarti orangnya tahu untuk apa dipakai,
-- disimpan di mana, berapa lama, dan bagaimana mencabutnya.
--
-- Yang dicatat bukan cuma "sudah setuju", melainkan VERSI teks yang dia
-- setujui berikut waktunya. Kalau suatu hari syaratnya berubah, yang
-- pernah menyetujui teks lama tetap tercatat menyetujui teks lama —
-- dan tanpa versinya, catatan persetujuan tidak membuktikan apa pun
-- karena tidak ada yang tahu dia menyetujui apa.

begin;

alter table employee_faces
  add column if not exists setuju_versi text,
  add column if not exists setuju_at timestamptz;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Sidik dari cara yang lama dibuang
-- ─────────────────────────────────────────────────────────────────────
--
-- Bukan sekadar kebersihan. Sidik itu sudah tidak bisa dibandingkan
-- dengan apa pun — jadi ia data biometrik yang tersimpan tanpa satu pun
-- kegunaan, dan data semacam itu tidak boleh menganggur di basis data.
--
-- Membuangnya juga yang membuat orangnya BISA mendaftar ulang:
-- daftar_wajah() menolak siapa pun yang barisnya masih ada, dan tanpa
-- ini tiga orang terjebak di antara absen yang ditolak dan pendaftaran
-- yang ditolak.
--
-- Foto acuannya ikut hilang dari layar sampai mereka mendaftar ulang.
-- Berkasnya sendiri masih di penyimpanan, jadi tidak ada bukti sengketa
-- yang lenyap.

begin;

delete from employee_faces where model not like 'facenet-%';

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Mendaftarkan wajah
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Daftar parameternya bertambah satu, jadi yang lama dibuang lebih
-- dulu — lihat catatan di _ambang_kembar_model() di atas.
-- Dua-duanya dibuang, yang berparameter empat maupun yang lima.
--
-- Yang lima memang sudah bernama sama dan bertipe sama, tapi versi
-- terdahulunya punya nilai bawaan — dan `create or replace` MENOLAK
-- mencabut nilai bawaan dari fungsi yang sudah ada. Galatnya menyebut
-- DROP FUNCTION dengan jelas, tapi ia baru muncul saat berkas ini
-- dijalankan ulang, bukan saat pertama kali.
drop function if exists daftar_wajah(text, double precision[], text, text);
drop function if exists daftar_wajah(text, double precision[], text, text, text);

create or replace function daftar_wajah(
  p_resto_id text,
  p_embedding double precision[],
  -- Tidak satu pun berparameter bawaan, dan itu disengaja.
  --
  -- Postgres menuntutnya begitu parameter terakhir wajib: yang tanpa
  -- bawaan tidak boleh berdiri setelah yang punya bawaan.
  --
  -- Tapi bukan cuma menuruti aturan bahasanya. Bawaan di sini berarti
  -- panggilan berparameter empat punya tempat mendarat — dan tempat
  -- mendaratnya adalah versi lama yang tidak memeriksa persetujuan sama
  -- sekali. Aplikasi selalu mengirim kelimanya, jadi tidak ada yang
  -- hilang dengan mewajibkannya.
  p_model text,
  p_foto_url text,
  p_setuju_versi text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_model text := coalesce(p_model, 'facenet-128-v1');
  v_kembar record;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       peran_karyawan()) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  -- Persetujuannya diperiksa di SERVER, bukan cuma di layar.
  --
  -- Kotak centang di aplikasi menghalangi orang yang memakai aplikasi.
  -- Ia tidak menghalangi apa pun yang memanggil fungsi ini langsung —
  -- dan wajah yang masuk lewat jalan itu adalah wajah yang tersimpan
  -- tanpa ada yang pernah menyetujuinya.
  if coalesce(trim(p_setuju_versi), '') = '' then
    raise exception 'Pendaftaran wajah butuh persetujuanmu dulu. Baca '
                    'syarat penggunaan datanya lalu centang setuju.';
  end if;

  if p_embedding is null or array_length(p_embedding, 1) is null then
    raise exception 'Sidik wajahnya kosong. Ulangi pemindaian.';
  end if;

  if exists (select 1 from employee_faces
             where resto_id = p_resto_id
               and lower(employee_email) = lower(v_email)) then
    raise exception 'Wajahmu sudah terdaftar. Minta Owner atau Admin '
                    'mereset dulu kalau memang perlu didaftar ulang.';
  end if;

  -- Terlalu mirip dengan rekan satu merchant berarti salah satu dari
  -- dua hal, dan keduanya harus dihentikan di sini: wajah orang lain
  -- yang didaftarkan, atau cara pencocokan yang tidak membedakan siapa
  -- pun. Yang kedua adalah kegagalan paling berbahaya, karena ia tidak
  -- pernah membuat siapa pun mengeluh — persis yang terjadi pada cara
  -- lama, dan yang menemukannya bukan pemeriksaan ini melainkan seorang
  -- manusia yang menatap dua foto bersebelahan.
  --
  -- Hanya dibandingkan dengan sidik dari model yang SAMA. Sidik dari
  -- model berbeda tidak sebanding, dan membandingkannya menghasilkan
  -- penolakan yang tidak bisa dijelaskan ke orangnya.
  select employee_email,
         _mirip(embedding, p_embedding, v_model) as skor
    into v_kembar
  from employee_faces
  where resto_id = p_resto_id and model = v_model
  order by _mirip(embedding, p_embedding, v_model) desc
  limit 1;

  if v_kembar.employee_email is not null
     and v_kembar.skor >= _ambang_kembar_model(v_model) then
    raise exception 'Wajah ini terlalu mirip dengan karyawan lain yang '
                    'sudah terdaftar. Minta Owner atau Admin memeriksanya.';
  end if;

  insert into employee_faces (
    resto_id, employee_email, embedding, model, foto_base64,
    setuju_versi, setuju_at)
  values (p_resto_id, lower(v_email), p_embedding, v_model, p_foto_url,
          trim(p_setuju_versi), now());
end;
$fn$;

revoke all on function daftar_wajah(
  text, double precision[], text, text, text) from public, anon;
grant execute on function daftar_wajah(
  text, double precision[], text, text, text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Absen menolak sidik yang tidak sebanding
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Yang memanggil dibuang lebih dulu, baru yang dipanggil — dan
-- keduanya dibuang karena versi terdahulunya berparameter bawaan, yang
-- tidak bisa dicabut oleh `create or replace`.
drop function if exists absen_masuk(text, double precision[],
  double precision, double precision, text, text);
drop function if exists absen_pulang(text, double precision[],
  double precision, double precision, text, text);
drop function if exists _absen(text, double precision[], double precision,
  double precision, text, boolean, text);

create or replace function _absen(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_pulang boolean,
  -- TANPA nilai bawaan, dan itu disengaja.
  --
  -- Dengan `default null`, panggilan berparameter enam cocok ke DUA
  -- fungsi sekaligus — yang lama dan yang ini — dan Postgres menolaknya:
  -- "function _absen(...) is not unique". Yang kena bukan berkas ini
  -- melainkan absensi_payroll.sql yang dijalankan lebih dulu di bundel
  -- gabungan, jadi galatnya muncul jauh sebelum baris ini terbaca dan
  -- seluruh sisa bundelnya batal.
  p_model text)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_resto record;
  v_setelan record;
  v_wajah record;
  v_skor double precision;
  v_ragu boolean;
  v_jarak double precision;
  v_peran text;
  v_wajib_dekat boolean;
  v_tanggal date := (now() at time zone 'Asia/Jakarta')::date;
  v_sekarang timestamptz := now();
begin
  if v_email = '' then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       peran_karyawan()) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  select latitude, longitude, name into v_resto
  from restaurants where id = p_resto_id;

  if v_resto.latitude is null or v_resto.longitude is null then
    raise exception 'Titik lokasi merchant belum disetel. Minta Admin '
                    'menyetelnya di menu Profil Merchant dulu.';
  end if;

  if p_lat is null or p_lng is null then
    raise exception 'Lokasimu tidak terbaca. Nyalakan GPS lalu coba lagi.';
  end if;

  select * into v_setelan from payroll_settings where resto_id = p_resto_id;

  v_jarak := _jarak_meter(v_resto.latitude, v_resto.longitude, p_lat, p_lng);

  -- Admin dan Finance tidak diikat radius: satu kantor pusat bisa
  -- mengurus beberapa merchant, dan mengikat mereka ke titik salah
  -- satunya berarti menyuruh mereka pergi ke sana tiap pagi untuk
  -- pekerjaan yang tidak dikerjakan di sana. Titik GPS-nya TETAP
  -- dicatat; yang dilepas penolakannya, bukan pencatatannya.
  select e.role into v_peran
  from employees e
  where e.resto_id = p_resto_id and lower(e.email) = v_email
  limit 1;

  v_wajib_dekat := coalesce(v_peran, '') not in ('admin', 'finance');

  if v_wajib_dekat and v_jarak > coalesce(v_setelan.radius_absen_m, 150) then
    raise exception 'Kamu % meter dari %. Absen hanya bisa dalam radius % meter.',
      round(v_jarak), coalesce(v_resto.name, 'merchant'),
      coalesce(v_setelan.radius_absen_m, 150);
  end if;

  select * into v_wajah from employee_faces
  where resto_id = p_resto_id and lower(employee_email) = v_email;

  if v_wajah is null then
    raise exception 'Wajahmu belum terdaftar. Daftarkan dulu di menu Absensi.';
  end if;

  -- Sidik dari cara yang berbeda TIDAK dibandingkan.
  --
  -- Membandingkannya tetap mengeluarkan bilangan, dan bilangan itulah
  -- yang paling berbahaya: ia terlihat seperti jawaban. Yang wajahnya
  -- terdaftar dengan cara lama disuruh mendaftar ulang, bukan diadu
  -- dengan angka yang tidak berarti apa-apa.
  if p_model is not null and coalesce(v_wajah.model, '') <> p_model then
    raise exception 'Wajahmu terdaftar dengan cara pengenalan yang lama '
                    'dan tidak bisa dibandingkan dengan yang sekarang. '
                    'Minta Owner atau Admin mereset wajahmu lewat Kelola '
                    'Karyawan, lalu daftarkan ulang.';
  end if;

  v_skor := _mirip(v_wajah.embedding, p_embedding, v_wajah.model);

  if v_skor < _ambang(v_wajah.model) then
    raise exception 'Wajahnya tidak cocok dengan yang terdaftar. '
                    'Hadapkan wajahmu lurus ke kamera dengan cahaya yang '
                    'cukup, lalu coba lagi.';
  end if;

  -- Diterima, tapi belum tentu meyakinkan.
  v_ragu := v_skor < _ambang_yakin(v_wajah.model);

  if p_pulang then
    update attendance
    set pulang_at = v_sekarang,
        pulang_lat = p_lat,
        pulang_lng = p_lng,
        pulang_jarak_m = round(v_jarak),
        pulang_skor = v_skor,
        pulang_ragu = v_ragu,
        pulang_foto_base64 = coalesce(p_foto_url, pulang_foto_base64)
    where resto_id = p_resto_id
      and lower(employee_email) = v_email
      and tanggal = v_tanggal
      and masuk_at is not null;

    if not found then
      raise exception 'Belum ada absen masuk hari ini.';
    end if;
  else
    insert into attendance (
      resto_id, employee_email, tanggal, status,
      masuk_at, masuk_lat, masuk_lng, masuk_jarak_m, masuk_skor,
      masuk_ragu, masuk_foto_base64)
    values (
      p_resto_id, v_email, v_tanggal, 'hadir',
      v_sekarang, p_lat, p_lng, round(v_jarak), v_skor, v_ragu, p_foto_url)
    on conflict (resto_id, employee_email, tanggal) do update
      set status = 'hadir',
          masuk_at = coalesce(attendance.masuk_at, excluded.masuk_at),
          masuk_lat = coalesce(attendance.masuk_lat, excluded.masuk_lat),
          masuk_lng = coalesce(attendance.masuk_lng, excluded.masuk_lng),
          masuk_jarak_m =
            coalesce(attendance.masuk_jarak_m, excluded.masuk_jarak_m),
          masuk_skor = coalesce(attendance.masuk_skor, excluded.masuk_skor),
          masuk_ragu = coalesce(attendance.masuk_ragu, excluded.masuk_ragu),
          masuk_foto_base64 = coalesce(
              attendance.masuk_foto_base64, excluded.masuk_foto_base64),
          potong_gaji = false,
          alasan = null;
  end if;

  return query select round(v_jarak)::integer, v_skor, v_sekarang;
end;
$fn$;

revoke all on function _absen(text, double precision[], double precision,
  double precision, text, boolean, text) from public, anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pintu absennya meneruskan nama modelnya
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Urutannya penting. Yang memanggil dibuang lebih dulu, baru yang
-- dipanggil: membuang _absen() lama selagi absen_masuk() lama masih
-- menyebutnya adalah galat ketergantungan, dan galat itu membatalkan
-- seluruh berkas ini di tengah jalan.
drop function if exists absen_masuk(text, double precision[],
  double precision, double precision, text);
drop function if exists absen_pulang(text, double precision[],
  double precision, double precision, text);

-- Yang berparameter lama dibuang: ia memanggil jalur tanpa pemeriksaan
-- model, dan jalan memutar yang tidak dipakai sebaiknya tidak tertinggal.
drop function if exists _absen(text, double precision[], double precision,
  double precision, text, boolean);

create or replace function absen_masuk(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_model text)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language sql
security definer
set search_path = public
as $$
  select * from _absen(p_resto_id, p_embedding, p_lat, p_lng,
                       p_foto_url, false, p_model);
$$;

create or replace function absen_pulang(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_model text)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language sql
security definer
set search_path = public
as $$
  select * from _absen(p_resto_id, p_embedding, p_lat, p_lng,
                       p_foto_url, true, p_model);
$$;

revoke all on function absen_masuk(text, double precision[], double precision,
  double precision, text, text) from public, anon;
revoke all on function absen_pulang(text, double precision[], double precision,
  double precision, text, text) from public, anon;
grant execute on function absen_masuk(text, double precision[], double precision,
  double precision, text, text) to authenticated;
grant execute on function absen_pulang(text, double precision[], double precision,
  double precision, text, text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Wajah yang masih memakai cara lama — semuanya harus didaftar ulang:
--
--      select resto_id, employee_email, model from employee_faces
--      where model not like 'facenet-%';
--
-- 2. Sesudah beberapa orang mendaftar ulang, kemiripan ANTARKARYAWAN
--    adalah ujian yang dulu gagal. Dengan FaceNet, angka orang yang
--    berbeda seharusnya jauh di bawah 0,40 — bukan 0,85 seperti dulu:
--
--      select a.employee_email, b.employee_email,
--             round(_mirip(a.embedding, b.embedding, a.model)::numeric, 3)
--      from employee_faces a join employee_faces b
--        on a.resto_id = b.resto_id and a.employee_email < b.employee_email
--      where a.model like 'facenet-%' and b.model like 'facenet-%';
--
--    Kalau angkanya masih tinggi, JANGAN naikkan ambangnya — berarti
--    ada yang keliru di sisi aplikasi, dan menaikkan ambang cuma
--    menyembunyikannya sampai ada yang absen atas nama orang lain.
--
-- 3. Sebaran skor absen orangnya sendiri:
--
--      select round(masuk_skor::numeric, 2) as skor, count(*)
--      from attendance where masuk_skor is not null group by 1 order by 1;
--
--    - Banyak yang ditolak padahal orangnya benar → turunkan _ambang_facenet()
--    - Ada yang lolos padahal bukan orangnya      → naikkan _ambang_facenet()
--
-- 4. Persetujuan tercatat berikut versinya:
--
--      select employee_email, setuju_versi, setuju_at from employee_faces;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 5 dari 5 — bukti_bayar_qris_statis.sql
-- ═══════════════════════════════════════════════════════════════════

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
