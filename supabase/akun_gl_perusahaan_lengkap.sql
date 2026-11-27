-- KaataGo — bagan akun perusahaan yang lengkap, dan jurnal yang
-- terlewat selama akunnya belum ada.
--
-- Jalankan SETELAH qris_statis.sql dan jurnal_cash_pickup_benar.sql.
-- Aman diulang.
--
-- ═══════════════════════════════════════════════════════════════════
-- Apa yang sebenarnya terjadi
-- ═══════════════════════════════════════════════════════════════════
--
-- Resto baru dibuatkan bagan akunnya oleh pemicu `trg_seed_gl_accounts`
-- lewat `seed_gl_accounts()`, yang membaca `_default_gl_accounts()`.
--
-- Fungsi itu dinyatakan ulang di tiga berkas, dan yang berlaku —
-- `qris_statis.sql`, posisi 91 — menjatuhkan EMPAT akun yang ada di
-- versi sebelumnya:
--
--   cash_pickup · cash_variance · company_cash · opening_balance
--
-- Sementara `company_bank` tidak pernah ada di satu pun dari ketiganya.
-- Ia hanya pernah dibuat oleh insert sekali-jalan di
-- `saldo_perusahaan.sql` — `from restaurants r` — yang menjangkau resto
-- yang SUDAH ADA saat itu, bukan yang lahir sesudahnya.
--
-- Jadi tiap merchant yang dibuat sesudah itu kehilangan lima akun.
--
-- ── Dan kehilangannya tidak berbunyi ─────────────────────────────────
--
-- Fungsi yang menulis jurnal memeriksa dulu:
--
--   if v_gl.gl_code is not null and v_gl.gl_code <> '' then ... end if;
--
-- Akunnya tidak ada berarti barisnya tidak ditulis — dan tindakannya
-- tetap SUKSES. Serah terima cash pickup tercatat diterima, uangnya
-- dinyatakan sampai, lalu tidak muncul di Saldo Perusahaan. Tanpa galat,
-- tanpa peringatan.
--
-- Periksa Pembukuan pun diam, karena pemeriksaannya ber-JOIN ke
-- `gl_accounts` yang sama: tidak ada akun berarti tidak ada temuan.
--
-- ═══════════════════════════════════════════════════════════════════
-- 1. Bagan akun bawaan, lengkap
-- ═══════════════════════════════════════════════════════════════════
--
-- Gabungan dari ketiga versi, ditambah `company_bank` yang belum pernah
-- ada. Nomornya mengikuti yang sudah dipakai di berkas-berkas
-- sebelumnya, supaya resto lama dan resto baru memakai nomor yang sama.

begin;

create or replace function _default_gl_accounts()
returns table (payment_method text, gl_code text, gl_name text)
language sql
immutable
as $$
  values
    -- Pemasukan
    ('cash',             '1950001', 'GL Kas Tunai'),
    ('qris',             '1950002', 'GL Penerimaan QRIS Dinamis'),
    ('transfer',         '1950003', 'GL Penerimaan Transfer'),
    -- Uangnya mendarat langsung di rekening merchant, tanpa penyedia
    -- pembayaran di tengahnya. Karena itu ia tidak pernah muncul di
    -- pencairan gateway, dan akunnya harus terpisah supaya angka yang
    -- menunggu dicairkan tidak menghitung uang yang sudah sampai.
    ('qris_static',      '1950004', 'GL Penerimaan QRIS Statis'),
    ('income_aggregate', '1950000', 'GL Pemasukan'),
    -- Keduanya juga pernah disemai dengan pola `from restaurants r`
    -- yang sama — insert sekali-jalan — jadi resto yang lahir
    -- sesudahnya tidak kebagian. Uang modal yang disetor dan selisih
    -- laci yang berlebih sama-sama hilang tanpa galat.
    ('capital',          '1940001', 'GL Setoran Modal'),
    ('other_income',     '1950009', 'GL Pendapatan Lain-lain'),
    -- Pajak & service
    ('ppn',              '1960001', 'GL PPN Keluaran'),
    ('service',          '1960002', 'GL Biaya Service'),
    -- Petty cash
    ('petty_cash',       '1980001', 'GL Petty Cash'),
    -- Total saldo & uang yang benar-benar dipegang perusahaan
    ('total_balance',    '1990001', 'GL Total Saldo'),
    ('company_cash',     '1990002', 'GL Saldo Cash Perusahaan'),
    ('company_bank',     '1990003', 'GL Saldo Bank Perusahaan'),
    ('opening_balance',  '1990004', 'GL Saldo Awal'),
    -- Suspense — titipan yang belum diakui masuk ke mana pun
    ('suspense',         '2100001', 'GL Suspense Setoran'),
    ('suspense_petty',   '2100002', 'GL Suspense Petty Cash'),
    ('cash_pickup',      '2100004', 'GL Cash Pickup'),
    -- Payment gateway, diskon, selisih laci
    ('gateway_fee',      '2200001', 'GL Biaya Payment Gateway'),
    ('discount',         '2200002', 'GL Diskon Penjualan'),
    ('cash_variance',    '2100003', 'GL Selisih Kasir');
$$;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 2. Resto yang sudah ada ikut dilengkapi
-- ═══════════════════════════════════════════════════════════════════
--
-- `seed_gl_accounts` memakai `on conflict do nothing`, jadi nomor yang
-- sudah disetel sendiri lewat Mapping GL Account TIDAK ditimpa. Yang
-- diisi hanya yang belum ada.

begin;

do $$
declare r record;
begin
  for r in select id from restaurants loop
    perform seed_gl_accounts(r.id);
  end loop;
end $$;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 3. Jurnal non-tunai yang terlewat → Saldo Bank Perusahaan
-- ═══════════════════════════════════════════════════════════════════
--
-- Ditanggalkan menurut tanggal PESANANNYA, bukan hari ini. Entri yang
-- semuanya bertanggal hari ini akan menggeser laporan tiap periode yang
-- sudah ditutup.
--
-- Aman diulang: pesanan yang sudah punya barisnya dilewati.
--
-- ⚠ YANG PERLU DIKETAHUI SEBELUM MENJALANKAN
--
-- Yang diisi hanya PENDAPATAN non-tunai. Uang yang pernah KELUAR dari
-- rekening — biaya yang dibayar transfer, penarikan, apa pun yang tidak
-- pernah dicatat di aplikasi ini — tidak ikut dikurangkan, karena
-- catatannya tidak ada.
--
-- Jadi angka Saldo Bank sesudah ini adalah TOTAL YANG PERNAH MASUK,
-- bukan sisa yang benar-benar ada di rekening sekarang. Kalau yang
-- diinginkan angka yang cocok dengan mutasi bank hari ini, yang tepat
-- bukan bagian ini melainkan satu baris saldo awal lewat menu Saldo
-- Perusahaan.

begin;

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  o.resto_id,
  (o.created_at at time zone 'Asia/Jakarta')::date,
  (o.created_at at time zone 'Asia/Jakarta')::time,
  a.gl_code,
  a.gl_name,
  'order',
  o.id::text,
  o.total,
  'credit',
  'Masuk rekening #' || upper(substr(o.id::text, 1, 8)) || ' (backfill)'
from orders o
join gl_accounts a
  on a.resto_id = o.resto_id
 and a.payment_method = 'company_bank'
 and coalesce(a.gl_code, '') <> ''
where o.payment_status = 'paid'
  -- Tunai tidak ikut: ia masuk laci, dan perjalanannya ke perusahaan
  -- lewat setoran atau cash pickup — bukan lewat rekening.
  and _normalize_payment_method(o.source, o.payment_method)
        in ('qris', 'qris_static', 'transfer')
  -- Pembukuan KaataGo sendiri tidak punya penjualan resto.
  and o.resto_id <> 'kaatago'
  and not exists (
    select 1 from gl_journal_entries j
    where j.resto_id = o.resto_id
      and j.reference_type = 'order'
      and j.reference_id = o.id::text
      and j.gl_code = a.gl_code
  );

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 4. Jurnal serah terima cash pickup yang terlewat
-- ═══════════════════════════════════════════════════════════════════
--
-- Dua kaki, sama seperti yang ditulis `terima_pickup`:
--
--   debit  GL Cash Pickup              — uang meninggalkan titipan
--   kredit GL Saldo Cash Perusahaan    — dan sampai di perusahaan
--
-- Ditanggalkan menurut `received_at`, saat serah terimanya benar-benar
-- terjadi — bukan `now()`, yang akan menaruh serah terima bulan lalu di
-- bulan ini.
--
-- Nominalnya `received_amount`, yang benar-benar dihitung saat diterima,
-- bukan `amount` yang dicatat kasir. Kalau keduanya berbeda, itu
-- selisihnya — dan yang masuk perusahaan adalah yang dihitung.

begin;

-- Kaki pertama: titipan dilepas.
insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  d.resto_id,
  (d.received_at at time zone 'Asia/Jakarta')::date,
  (d.received_at at time zone 'Asia/Jakarta')::time,
  a.gl_code,
  a.gl_name,
  'cash_deposit',
  d.id::text,
  coalesce(d.received_amount, d.amount),
  'debit',
  'Serah terima pickup #' || upper(substr(d.id::text, 1, 8)) || ' (backfill)'
from cash_deposits d
join gl_accounts a
  on a.resto_id = d.resto_id
 and a.payment_method = 'cash_pickup'
 and coalesce(a.gl_code, '') <> ''
where coalesce(d.method, 'setor') = 'pickup'
  and d.received_at is not null
  and not exists (
    select 1 from gl_journal_entries j
    where j.resto_id = d.resto_id
      and j.reference_type = 'cash_deposit'
      and j.reference_id = d.id::text
      and j.gl_code = a.gl_code
  );

-- Kaki kedua: uangnya sampai di perusahaan.
insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  d.resto_id,
  (d.received_at at time zone 'Asia/Jakarta')::date,
  (d.received_at at time zone 'Asia/Jakarta')::time,
  a.gl_code,
  a.gl_name,
  'cash_deposit',
  d.id::text,
  coalesce(d.received_amount, d.amount),
  'credit',
  'Terima cash pickup #' || upper(substr(d.id::text, 1, 8)) || ' (backfill)'
from cash_deposits d
join gl_accounts a
  on a.resto_id = d.resto_id
 and a.payment_method = 'company_cash'
 and coalesce(a.gl_code, '') <> ''
where coalesce(d.method, 'setor') = 'pickup'
  and d.received_at is not null
  and not exists (
    select 1 from gl_journal_entries j
    where j.resto_id = d.resto_id
      and j.reference_type = 'cash_deposit'
      and j.reference_id = d.id::text
      and j.gl_code = a.gl_code
  );

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Memeriksanya
-- ═══════════════════════════════════════════════════════════════════
--
-- Yang terisi barusan, per merchant:
--
--   select r.name, j.gl_name, count(*) as baris,
--          to_char(sum(j.amount), 'FM999G999G999G999') as total
--   from gl_journal_entries j
--   join restaurants r on r.id = j.resto_id
--   where j.description like '%(backfill)'
--   group by r.name, j.gl_name
--   order by r.name, j.gl_name;
--
-- Masih ada merchant yang akunnya belum lengkap?
--
--   select r.name, p.pm as akun_yang_hilang
--   from restaurants r
--   cross join (values ('company_cash'), ('company_bank'),
--                      ('cash_pickup'), ('opening_balance'),
--                      ('cash_variance')) p(pm)
--   where not exists (
--     select 1 from gl_accounts a
--     where a.resto_id = r.id and a.payment_method = p.pm
--       and coalesce(a.gl_code, '') <> ''
--   )
--   order by r.name, p.pm;
