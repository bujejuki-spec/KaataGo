-- KaataGo - menutup fungsi bantu yang tidak seharusnya bisa dipanggil
-- aplikasi.
--
-- Jalankan SETELAH absensi_payroll.sql dan paket_langganan.sql.
-- Aman diulang.
--
-- ── Apa yang keliru ──────────────────────────────────────────────────
--
-- Postgres memberikan EXECUTE kepada PUBLIC secara bawaan untuk setiap
-- fungsi baru. Selama ini itu tidak menimbulkan apa-apa karena hampir
-- semua fungsi SECURITY DEFINER di aplikasi ini memeriksa sendiri siapa
-- pemanggilnya di baris pertama.
--
-- Dua fungsi tidak melakukannya, karena keduanya memang tidak dirancang
-- untuk dipanggil dari luar:
--
--   terapkan_paket()           dipanggil set_paket_resto, set_trial_resto,
--                              dan putuskan_langganan — ketiganya sudah
--                              memeriksa KaataGo Admin lebih dulu
--   ingatkan_percobaan_habis() dipanggil pg_cron
--
-- Akibatnya nyata, dan yang paling serius adalah yang pertama: siapa pun
-- yang sudah masuk bisa memanggil
--
--   select terapkan_paket('<resto_id>', 'premium');
--
-- dan seluruh pembatasan paket untuk resto itu terhapus. Merchant Basic
-- membuka sendiri setiap menu Premium, tanpa membayar dan tanpa satu pun
-- galat yang memberitahukannya.
--
-- Perlu disebut apa adanya: itu tidak membuka DATA yang tidak boleh dia
-- buka. RLS tetap lantai keamanannya, dan menu yang terbuka lewat cara
-- itu akan ditolak servernya begitu dipakai. Yang jebol adalah batas
-- paketnya — dan batas paket itulah seluruh isi fiturnya.
--
-- ── Kenapa mencabutnya tidak mematahkan pemanggilnya ─────────────────
--
-- Fungsi SECURITY DEFINER berjalan sebagai pemiliknya, bukan sebagai
-- pemanggilnya. Jadi set_paket_resto tetap bisa memanggil terapkan_paket
-- meskipun `authenticated` sudah tidak boleh menyentuhnya langsung, dan
-- pg_cron tetap bisa menjalankan pengingatnya.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Fungsi bantu ditutup dari aplikasi
-- ─────────────────────────────────────────────────────────────────────

revoke all on function terapkan_paket(text, text, text)
  from public, anon, authenticated;

revoke all on function ingatkan_percobaan_habis()
  from public, anon, authenticated;

-- Pembantu absen. Ia sudah memeriksa wajah, jarak, dan keanggotaan
-- sendiri, jadi tidak ada yang jebol lewat sini — tapi tidak ada juga
-- yang membutuhkannya, dan permukaan yang tidak dibutuhkan sebaiknya
-- tidak ada.
revoke all on function _absen(text, double precision[], double precision,
  double precision, text, boolean) from public, anon, authenticated;

-- Fungsi murni tanpa data. Dicabut demi kerapian, bukan keamanan.
revoke all on function _menu_semua() from public, anon;
revoke all on function _menu_paket_basic() from public, anon;
revoke all on function _ambang_wajah() from public, anon;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Keadaan langganan hanya untuk merchant sendiri
-- ─────────────────────────────────────────────────────────────────────
--
-- Sebelumnya fungsi ini menjawab pertanyaan tentang resto mana pun yang
-- id-nya ditebak orang: paketnya apa, harganya berapa, masa
-- percobaannya sampai kapan. Bukan uang, tapi tetap keterangan tentang
-- merchant lain yang tidak ada urusannya dengan penanyanya.
--
-- Yang tidak berhak menerima baris kosong, bukan galat: pesan galat
-- justru mengonfirmasi bahwa restonya ada.

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
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select p.proname,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') as boleh
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('terapkan_paket', 'ingatkan_percobaan_habis',
--                       '_absen', 'keadaan_langganan');
--
-- Yang benar: keadaan_langganan boleh, tiga sisanya tidak.
