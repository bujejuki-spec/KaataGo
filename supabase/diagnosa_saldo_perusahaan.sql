-- ═══════════════════════════════════════════════════════════════════
-- Diagnosa: "Saldo Perusahaan belum masuk semua"
-- ═══════════════════════════════════════════════════════════════════
--
-- BACA-SAJA. Tidak ada satu pun baris yang ditulis, diubah, atau
-- dihapus di sini.
--
-- Ganti nama restonya di baris `ilike` kalau mau memeriksa yang lain.
--
-- ── Kenapa tidak memanggil fungsinya saja ────────────────────────────
--
-- `saldo_perusahaan()` dan `periksa_pembukuan()` dipagari
-- `is_super_admin() or is_resto_employee(...)`, dan keduanya membaca
-- `auth.jwt()`. Di SQL Editor tidak ada JWT, jadi keduanya
-- mengembalikan NOL BARIS — bukan nol rupiah. Itu terbaca persis
-- seperti "tidak ada masalah".
--
-- Jadi yang di bawah menghitung ulang dari tabel dasarnya, dengan
-- rumus yang sama.

with resto as (
  select id, name
  from restaurants
  where name ilike '%Kopi Maman%'
),

-- Entri yang masih berlaku: bukan pembalik, dan belum dibalik.
-- Persis rumus `saldo_perusahaan`.
berlaku as (
  select j.*
  from gl_journal_entries j
  join resto r on r.id = j.resto_id
  where coalesce(j.is_reversal, false) = false
    and not exists (
      select 1 from gl_journal_entries x
      where x.resto_id = j.resto_id
        and coalesce(x.is_reversal, false) = true
        and x.reference_type = j.reference_type
        and x.reference_id = j.reference_id
        and x.gl_code = j.gl_code
    )
),

-- Semua entri bukan-pembalik, tanpa memperhatikan pembaliknya.
-- Rumus yang dipakai pemeriksa pembukuan untuk suspense dan pickup.
mentah as (
  select j.*
  from gl_journal_entries j
  join resto r on r.id = j.resto_id
  where coalesce(j.is_reversal, false) = false
),

akun as (
  select a.payment_method, a.gl_code
  from gl_accounts a
  join resto r on r.id = a.resto_id
  where a.payment_method in
    ('company_cash', 'company_bank', 'suspense', 'cash_pickup')
),

-- ── 1. Akun GL-nya sudah dipetakan? ─────────────────────────────────
--
-- Ini yang paling perlu dilihat pertama, dan yang paling mudah
-- terlewat. `saldo_perusahaan` ber-JOIN ke `gl_accounts`; kalau
-- barisnya tidak ada, saldonya 0 — bukan galat, bukan peringatan.
-- Pemeriksa pembukuan pun diam, karena pemeriksaan non-tunainya juga
-- ber-JOIN ke tabel yang sama. Angka nol tanpa sebab yang kelihatan.
pemetaan as (
  select
    1 as urut,
    'Akun GL' as pemeriksaan,
    p.pm as rincian,
    coalesce(nullif(a.gl_code, ''), '>>> BELUM DIPETAKAN <<<') as nilai
  from (values ('company_cash'), ('company_bank'),
               ('suspense'), ('cash_pickup')) p(pm)
  left join akun a on a.payment_method = p.pm
),

-- ── 2. Saldo menurut jurnalnya ──────────────────────────────────────
saldo as (
  select 2 as urut, 'Saldo menurut jurnal' as pemeriksaan,
    case a.payment_method when 'company_cash' then 'Cash Perusahaan'
                          else 'Bank Perusahaan' end as rincian,
    to_char(coalesce(sum(case when b.entry_type = 'credit'
                              then b.amount else -b.amount end), 0),
            'FM999,999,999,999') as nilai
  from akun a
  left join berlaku b on b.gl_code = a.gl_code
  where a.payment_method in ('company_cash', 'company_bank')
  group by a.payment_method
),

-- ── 3. Uang yang masih tersangkut di titipan ────────────────────────
--
-- Keduanya SEHARUSNYA nol. Sisa positif berarti uangnya sudah dicatat
-- masuk tapi belum diputuskan — dan selama belum diputuskan, ia memang
-- bukan milik Saldo Perusahaan.
titipan as (
  select 3 as urut, 'Masih tersangkut' as pemeriksaan,
    case a.payment_method
      when 'suspense' then 'Suspense Setoran (menunggu Finance)'
      else 'Cash Pickup (belum diserahterimakan)' end as rincian,
    to_char(coalesce(sum(case when m.entry_type = 'credit'
                              then m.amount else -m.amount end), 0),
            'FM999,999,999,999') as nilai
  from akun a
  left join mentah m on m.gl_code = a.gl_code
  where a.payment_method in ('suspense', 'cash_pickup')
  group by a.payment_method
),

-- ── 4. Penjualan non-tunai yang belum punya baris di Saldo Bank ─────
--
-- Dipisah dua, karena artinya berbeda jauh:
--
--   HARI INI      — normal. Tugas jam 5 pagi baru menjalaninya besok.
--   SEBELUM ITU   — tidak normal. Tugasnya gagal atau tidak jalan.
nontunai as (
  select 4 as urut, 'Non-tunai tanpa jurnal' as pemeriksaan,
    case when o.created_at >= date_trunc('day', now() at time zone 'Asia/Jakarta')
                                at time zone 'Asia/Jakarta'
         then 'HARI INI — wajar, menunggu tugas jam 5 pagi'
         else '>>> SEBELUM HARI INI — tugasnya tidak jalan <<<' end as rincian,
    to_char(sum(o.total), 'FM999,999,999,999') as nilai
  from orders o
  join resto r on r.id = o.resto_id
  join akun a on a.payment_method = 'company_bank'
             and coalesce(a.gl_code, '') <> ''
  where o.payment_status = 'paid'
    and _normalize_payment_method(o.source, o.payment_method)
          in ('qris', 'qris_static', 'transfer')
    and not exists (
      select 1 from gl_journal_entries j
      where j.resto_id = o.resto_id
        and j.reference_type = 'order'
        and j.reference_id = o.id::text
        and j.gl_code = a.gl_code
    )
  group by 3
),

-- ── 5. Tunai yang masih di laci, belum disetor ──────────────────────
--
-- Ini bukan kekeliruan: uang di laci kasir memang belum jadi Saldo
-- Perusahaan. Disebut supaya selisihnya bisa dicocokkan, bukan dikira
-- hilang.
laci as (
  select 5 as urut, 'Belum jadi saldo perusahaan' as pemeriksaan,
    'Tunai lunas yang belum disetor/dijemput' as rincian,
    to_char(coalesce(sum(o.total), 0), 'FM999,999,999,999') as nilai
  from orders o
  join resto r on r.id = o.resto_id
  where o.payment_status = 'paid'
    and _normalize_payment_method(o.source, o.payment_method) = 'cash'
)

select pemeriksaan, rincian, nilai from (
  select urut, pemeriksaan, rincian, nilai from pemetaan
  union all select urut, pemeriksaan, rincian, nilai from saldo
  union all select urut, pemeriksaan, rincian, nilai from titipan
  union all select urut, pemeriksaan, rincian, nilai from nontunai
  union all select urut, pemeriksaan, rincian, nilai from laci
) hasil
order by urut, rincian;


-- ═══════════════════════════════════════════════════════════════════
-- Jalankan TERPISAH: riwayat tugas jam 5 pagi
-- ═══════════════════════════════════════════════════════════════════
--
-- Dipisah karena `cron.job_run_details` bisa tidak terbaca, dan kalau
-- digabung, galatnya membatalkan seluruh diagnosa di atas.
--
-- select j.jobname, d.status, d.start_time, d.end_time,
--        left(coalesce(d.return_message, ''), 200) as pesan
-- from cron.job j
-- left join cron.job_run_details d on d.jobid = j.jobid
-- where j.jobname like '%jurnal%'
-- order by d.start_time desc nulls last
-- limit 20;
