-- KaataGo - masa percobaan punya paketnya sendiri.
--
-- Jalankan SETELAH paket_langganan.sql dan perbaikan_hak_fungsi.sql.
-- Aman diulang.
--
-- ── Apa yang keliru ──────────────────────────────────────────────────
--
-- Masa percobaan selalu membuka semua fitur, apa pun yang sebenarnya
-- mau ditawarkan. Akibatnya merchant yang dicoba-cobakan paket Basic
-- justru mencicipi Premium selama dua minggu, lalu kehilangan separuh
-- menunya persis di hari dia mulai membayar. Itu bukan masa percobaan,
-- itu jebakan.
--
-- Dan karena percobaannya tidak menyimpan paket apa pun, layar KaataGo
-- Admin tidak punya yang bisa ditampilkan selain "sedang percobaan" —
-- tanpa menyebut percobaan yang mana.
--
-- Kolom di bawah yang memperbaikinya: percobaan menyebut paketnya, dan
-- akses menunya mengikuti paket itu sejak hari pertama.

begin;

-- Paket yang sedang dicoba. Null berarti baris lama, atau percobaan
-- yang diberikan sebelum berkas ini dipasang — keduanya diperlakukan
-- sebagai Premium, sama seperti perilaku sebelumnya, supaya merchant
-- yang sedang mencoba hari ini tidak tiba-tiba kehilangan menu.
alter table resto_billing add column if not exists trial_paket text;

alter table resto_billing drop constraint if exists resto_billing_trial_paket_check;
alter table resto_billing add constraint resto_billing_trial_paket_check
  check (trial_paket is null or trial_paket in ('basic', 'premium'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memberi percobaan, berikut paketnya
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Daftar parameternya berubah, jadi yang lama dibuang lebih dulu.
--
-- `create or replace` dengan daftar parameter yang berbeda TIDAK
-- menimpa apa pun — ia membuat fungsi KEDUA dengan nama yang sama, dan
-- yang dipanggil aplikasi kemudian bergantung pada pencocokan tipe.
drop function if exists set_trial_resto(text, integer);

create or replace function set_trial_resto(
  p_resto_id text,
  p_hari integer,
  p_paket text default 'premium')
returns date
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_sampai date;
  v_paket text := coalesce(p_paket, 'premium');
begin
  if not is_super_admin() then
    raise exception 'Hanya KaataGo Admin yang bisa memberi masa percobaan.';
  end if;

  if p_hari is null or p_hari < 1 or p_hari > 365 then
    raise exception 'Lama percobaannya antara 1 dan 365 hari.';
  end if;

  if v_paket not in ('basic', 'premium') then
    raise exception 'Paket percobaannya harus Basic atau Premium.';
  end if;

  -- Yang sudah berlangganan tidak boleh diberi percobaan.
  --
  -- Fungsi ini menyetel paket jadi null dan harganya jadi nol. Dipanggil
  -- untuk merchant yang sudah membayar, ia diam-diam membatalkan
  -- langganannya dan menghentikan penagihannya — tanpa galat, tanpa
  -- catatan, dan yang menemukannya bukan kita melainkan tagihan yang
  -- berhenti datang.
  --
  -- Layarnya memang sudah menyembunyikan tombolnya, tapi layar yang
  -- menyembunyikan tombol tidak menahan apa pun: fungsinya tetap bisa
  -- dipanggil langsung.
  if exists (select 1 from resto_billing
             where resto_id = p_resto_id and paket is not null) then
    raise exception 'Merchant ini sudah berlangganan. Lepas paketnya dulu '
                    'kalau memang mau dikembalikan ke masa percobaan.';
  end if;

  v_sampai := (now() at time zone 'Asia/Jakarta')::date + p_hari;

  -- Percobaan bukan langganan: `paket` sengaja dikosongkan, dan
  -- harganya nol. Yang mengisinya nanti adalah pengajuan yang disetujui.
  insert into resto_billing (
    resto_id, trial_until, trial_days, trial_paket, paket, monthly_price)
  values (p_resto_id, v_sampai, p_hari, v_paket, null, 0)
  on conflict (resto_id) do update
    set trial_until = excluded.trial_until,
        trial_days = excluded.trial_days,
        trial_paket = excluded.trial_paket,
        paket = null,
        monthly_price = 0,
        updated_at = now();

  -- Akses menunya mengikuti paket yang sedang dicoba, bukan selalu
  -- terbuka penuh. Yang mencoba Basic memang harus melihat Basic.
  perform terapkan_paket(p_resto_id, v_paket);

  return v_sampai;
end;
$fn$;

revoke all on function set_trial_resto(text, integer, text) from public, anon;
grant execute on function set_trial_resto(text, integer, text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Keadaan langganan ikut menyebut paket percobaannya
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Tipe kembaliannya bertambah satu kolom, jadi dibuang dulu.
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
    -- Percobaan lama tanpa paket diperlakukan Premium, seperti dulu.
    case when s.trial_until is not null
         then coalesce(s.trial_paket, 'premium') end,
    (s.trial_until - h.ini)::integer,
    coalesce(s.paket is null and s.trial_until is not null
             and h.ini <= s.trial_until, false),
    coalesce(s.paket is null and s.trial_until is not null
             and h.ini > s.trial_until, false),
    r.status,
    case when r.status = 'ditolak' then r.alasan_tolak end,
    coalesce(s.paket is null and s.trial_until is not null
             and h.ini > s.trial_until, false)
  from hari h
  cross join boleh b
  left join s on true
  left join paket_langganan p on p.kode = s.paket
  left join r on true
  where b.ya;
$$;

grant execute on function keadaan_langganan(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Keadaan seluruh merchant, untuk layar KaataGo Admin
-- ─────────────────────────────────────────────────────────────────────
--
-- Satu panggilan, bukan satu per merchant.
--
-- Layar Billing Merchant menampilkan puluhan baris sekaligus. Menanyakan
-- keadaan tiap merchant satu per satu berarti puluhan panggilan tiap
-- kali layarnya dibuka — dan yang menunggunya adalah orang yang cuma
-- ingin melihat siapa yang sedang percobaan.

begin;

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
  status_pengajuan text
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
      order by r.diajukan_at desc limit 1)
  from resto_billing b
  cross join hari h
  where is_super_admin();
$$;

grant execute on function keadaan_langganan_semua() to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from keadaan_langganan_semua();
--   select resto_id, paket, trial_paket, trial_until, trial_days
--   from resto_billing where trial_until is not null;
