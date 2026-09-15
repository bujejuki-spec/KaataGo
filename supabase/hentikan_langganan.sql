-- KaataGo - berhenti berlangganan, dan aturan kunci yang baru.
--
-- Jalankan SETELAH peran_hr.sql. Aman diulang.
--
-- ── Dua hal, dan keduanya soal kapan aplikasinya boleh dipakai ──────
--
-- 1. Merchant bisa menyatakan berhenti berlangganan sendiri, dan
--    penghentiannya BERLAKU DI TANGGAL TAGIHAN BERIKUTNYA — bukan
--    seketika. Yang sudah membayar bulan ini berhak memakai bulan ini;
--    mematikannya di detik dia menekan tombol berarti menjual sebulan
--    lalu mengambil sisanya kembali.
--
-- 2. Aplikasinya hanya bisa dipakai kalau merchant sedang mencoba atau
--    sedang berlangganan. Di luar itu — belum pernah disetel, masa
--    percobaannya habis, atau langganannya sudah lewat tanggal berhenti
--    — terkunci.
--
-- ── Yang berubah arahnya ─────────────────────────────────────────────
--
-- Sebelumnya merchant yang tidak pernah disentuh KaataGo Admin berjalan
-- apa adanya: tanpa paket, tanpa percobaan, tanpa kunci. Itu memang
-- disengaja waktu itu — supaya merchant lama tidak tiba-tiba mati pada
-- hari fitur paket dipasang.
--
-- Sekarang aturannya dibalik: tidak ada paket berarti tidak ada akses.
-- Sebelum menjalankan berkas ini, hitung siapa yang kena:
--
--   select r.id, r.name,
--          (select count(*) from employees e
--            where e.resto_id = r.id and e.active) as karyawan_aktif
--   from restaurants r
--   left join resto_billing b on b.resto_id = r.id
--   where b.paket is null and b.trial_until is null;
--
-- Yang punya karyawan aktif di daftar itu akan kehilangan aksesnya
-- begitu berkas ini dijalankan. Beri mereka percobaan dulu.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Kolom penghentian
-- ─────────────────────────────────────────────────────────────────────
--
-- Dua kolom, bukan satu bendera.
--
-- `dihentikan_at` menjawab kapan dia memutuskannya, `aktif_sampai`
-- menjawab sampai kapan dia masih boleh memakai. Satu bendera "berhenti"
-- saja memaksa tanggalnya dihitung ulang tiap kali ditanya — dan
-- hitungan yang diulang di beberapa tempat akan berbeda di salah
-- satunya, biasanya pada bulan yang tanggal tagihnya tidak ada.

alter table resto_billing
  add column if not exists dihentikan_at timestamptz,
  add column if not exists aktif_sampai date,
  add column if not exists alasan_berhenti text;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Menghentikan langganan
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function hentikan_langganan(
  p_resto_id text,
  p_alasan text)
returns date
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_b record;
  v_hari integer;
  v_ini date := (now() at time zone 'Asia/Jakarta')::date;
  v_sampai date;
begin
  -- Hanya Owner dan Finance.
  --
  -- Berhenti berlangganan adalah keputusan belanja, dan yang paling
  -- terkena adalah orang-orang yang tidak menekan tombolnya: kasir yang
  -- besok tidak bisa membuka shift, dapur yang berhenti menerima
  -- pesanan. Kasir yang bisa menekannya sendiri adalah kasir yang bisa
  -- mematikan restonya karena salah tekan.
  if not is_resto_employee(p_resto_id, array['owner', 'finance']) then
    raise exception 'Cuma Owner dan Finance yang bisa menghentikan '
                    'langganan.';
  end if;

  select * into v_b from resto_billing where resto_id = p_resto_id;

  if v_b is null or v_b.paket is null then
    raise exception 'Merchant ini sedang tidak berlangganan.';
  end if;

  if v_b.dihentikan_at is not null then
    raise exception 'Langganannya sudah dihentikan, berlaku % .',
      to_char(v_b.aktif_sampai, 'DD Mon YYYY');
  end if;

  -- Berlaku di tanggal tagihan BERIKUTNYA.
  --
  -- Kalau tanggal tagihnya bulan ini belum lewat, itulah batasnya;
  -- kalau sudah lewat, bulan depan. Tanggal 29-31 di bulan yang lebih
  -- pendek jatuh di hari terakhirnya, sama seperti penagihannya
  -- sendiri — dua aturan tanggal yang berbeda untuk satu siklus adalah
  -- selisih yang baru ketahuan dari orang yang merasa dikunci kecepatan
  -- sehari.
  v_hari := coalesce(v_b.billing_day, 1);

  v_sampai := least(
    v_hari,
    extract(day from (date_trunc('month', v_ini)
                      + interval '1 month - 1 day'))::integer
  );
  v_sampai := date_trunc('month', v_ini)::date + (v_sampai - 1);

  if v_sampai <= v_ini then
    v_sampai := date_trunc('month', v_ini) + interval '1 month';
    v_sampai := v_sampai + (least(
      v_hari,
      extract(day from (date_trunc('month', v_sampai)
                        + interval '1 month - 1 day'))::integer
    ) - 1);
  end if;

  update resto_billing
  set dihentikan_at = now(),
      aktif_sampai = v_sampai,
      alasan_berhenti = nullif(trim(coalesce(p_alasan, '')), ''),
      updated_at = now()
  where resto_id = p_resto_id;

  return v_sampai;
end;
$fn$;

revoke all on function hentikan_langganan(text, text) from public, anon;
grant execute on function hentikan_langganan(text, text) to authenticated;

-- Membatalkan penghentian, selama tanggalnya belum lewat.
--
-- Ada karena keputusan berhenti sering dibuat saat kesal lalu ditarik
-- kembali keesokan harinya — dan tanpa jalan pulang, yang tersisa cuma
-- menghubungi KaataGo dan menunggu seseorang membetulkannya dari sisi
-- sana.
create or replace function lanjutkan_langganan(p_resto_id text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_b record;
begin
  if not is_resto_employee(p_resto_id, array['owner', 'finance']) then
    raise exception 'Cuma Owner dan Finance yang bisa melanjutkan '
                    'langganan.';
  end if;

  select * into v_b from resto_billing where resto_id = p_resto_id;

  if v_b is null or v_b.dihentikan_at is null then
    raise exception 'Langganannya memang sedang tidak dihentikan.';
  end if;

  if v_b.aktif_sampai < (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Masa aktifnya sudah lewat. Ajukan langganan baru '
                    'lewat menu Paket Langganan.';
  end if;

  update resto_billing
  set dihentikan_at = null,
      aktif_sampai = null,
      alasan_berhenti = null,
      updated_at = now()
  where resto_id = p_resto_id;
end;
$fn$;

revoke all on function lanjutkan_langganan(text) from public, anon;
grant execute on function lanjutkan_langganan(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Aturan kunci yang baru
-- ─────────────────────────────────────────────────────────────────────

begin;

drop function if exists keadaan_langganan(text);

create or replace function keadaan_langganan(p_resto_id text)
returns table (
  paket text,
  nama_paket text,
  harga bigint,
  trial_until date,
  trial_days integer,
  trial_paket text,
  sisa_hari integer,
  dalam_percobaan boolean,
  percobaan_habis boolean,
  status_pengajuan text,
  alasan_tolak text,
  terkunci_paket boolean,
  dihentikan boolean,
  aktif_sampai date,
  alasan_berhenti text
)
language sql
stable
security definer
set search_path = public
as $$
  with boleh as (
    select is_super_admin()
        or is_resto_employee(p_resto_id, peran_karyawan()) as ya
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
  ),
  hitung as (
    select
      h.ini,
      s.*,
      -- Sedang mencoba.
      coalesce(s.paket is null and s.trial_until is not null
               and h.ini <= s.trial_until, false) as v_coba,
      -- Berlangganan dan masih dalam masa aktifnya.
      coalesce(s.paket is not null
               and (s.aktif_sampai is null or h.ini <= s.aktif_sampai),
               false) as v_langganan
    from hari h left join s on true
  )
  select
    c.paket,
    p.nama,
    coalesce(p.harga_bulanan, c.monthly_price, 0),
    c.trial_until,
    c.trial_days,
    case when c.trial_until is not null
         then coalesce(c.trial_paket, 'premium') end,
    (c.trial_until - c.ini)::integer,
    c.v_coba,
    coalesce(c.paket is null and c.trial_until is not null
             and c.ini > c.trial_until, false),
    r.status,
    case when r.status = 'ditolak' then r.alasan_tolak end,
    -- TERKUNCI kalau bukan keduanya.
    --
    -- Baris yang tidak ada sama sekali ikut terkunci: `c.v_coba` dan
    -- `c.v_langganan` keduanya false di situ, dan merchant tanpa baris
    -- billing memang merchant yang belum pernah diberi apa pun.
    not (coalesce(c.v_coba, false) or coalesce(c.v_langganan, false)),
    c.dihentikan_at is not null,
    c.aktif_sampai,
    c.alasan_berhenti
  from hitung c
  cross join boleh b
  left join paket_langganan p on p.kode = c.paket
  left join r on true
  where b.ya;
$$;

grant execute on function keadaan_langganan(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. KaataGo Admin melihat siapa yang berhenti
-- ─────────────────────────────────────────────────────────────────────

begin;

drop function if exists keadaan_langganan_semua();

create or replace function keadaan_langganan_semua()
returns table (
  resto_id text,
  paket text,
  trial_until date,
  trial_days integer,
  trial_paket text,
  sisa_hari integer,
  dalam_percobaan boolean,
  percobaan_habis boolean,
  status_pengajuan text,
  dihentikan boolean,
  aktif_sampai date,
  alasan_berhenti text
)
language sql
stable
security definer
set search_path = public
as $$
  with hari as (
    select (now() at time zone 'Asia/Jakarta')::date as ini
  )
  select
    b.resto_id,
    b.paket,
    b.trial_until,
    b.trial_days,
    case when b.trial_until is not null
         then coalesce(b.trial_paket, 'premium') end,
    (b.trial_until - h.ini)::integer,
    coalesce(b.paket is null and b.trial_until is not null
             and h.ini <= b.trial_until, false),
    coalesce(b.paket is null and b.trial_until is not null
             and h.ini > b.trial_until, false),
    (select status from subscription_requests r
      where r.resto_id = b.resto_id
      order by r.diajukan_at desc limit 1),
    b.dihentikan_at is not null,
    b.aktif_sampai,
    b.alasan_berhenti
  from resto_billing b
  cross join hari h
  where is_super_admin();
$$;

grant execute on function keadaan_langganan_semua() to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 5. Paket yang disetujui menghapus penghentian sebelumnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Tanpa ini, merchant yang berhenti lalu berlangganan lagi tetap
-- membawa tanggal berhentinya yang lama — dan aplikasinya mati di
-- tanggal itu meski dia baru saja membayar.

begin;

create or replace function _bersihkan_penghentian()
returns trigger
language plpgsql
as $fn$
begin
  if new.paket is not null and new.paket is distinct from old.paket then
    new.dihentikan_at := null;
    new.aktif_sampai := null;
    new.alasan_berhenti := null;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_bersihkan_penghentian on resto_billing;
create trigger trg_bersihkan_penghentian
  before update on resto_billing
  for each row execute function _bersihkan_penghentian();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select resto_id, paket, trial_until, dihentikan_at, aktif_sampai
--   from resto_billing order by resto_id;
--
--   select * from keadaan_langganan_semua() where dihentikan;
--
-- Dan yang paling penting — siapa yang sekarang terkunci:
--
--   select r.id, r.name from restaurants r
--   join resto_billing b on b.resto_id = r.id
--   where not (
--     (b.paket is null and b.trial_until is not null
--       and (now() at time zone 'Asia/Jakarta')::date <= b.trial_until)
--     or (b.paket is not null and (b.aktif_sampai is null
--       or (now() at time zone 'Asia/Jakarta')::date <= b.aktif_sampai))
--   );
