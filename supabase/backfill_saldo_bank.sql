-- KaataGo - saldo bank perusahaan diisi dari penjualan non-tunai yang
-- sudah lewat.
--
-- Jalankan SETELAH saldo_perusahaan.sql. Aman diulang.
--
-- Mulai berlakunya saldo_perusahaan.sql, tiap pesanan non-tunai yang
-- lunas menuliskan barisnya sendiri di GL Saldo Bank Perusahaan. Yang
-- sebelum itu tidak punya baris apa pun di sana — jadi saldonya mulai
-- dari nol, seolah merchant baru buka hari ini.
--
-- Berkas ini menuliskan baris yang hilang itu untuk SELURUH pesanan
-- non-tunai yang pernah lunas, sejak hari pertama.
--
-- ── Yang perlu disadari sebelum menjalankannya ───────────────────────
--
-- Yang diisi hanya PENDAPATAN non-tunai. Uang yang sudah lama keluar
-- dari rekening sejak dulu — biaya yang dibayar transfer, penarikan
-- tunai, apa pun yang tidak pernah dicatat di aplikasi ini — tidak ikut
-- dikurangkan, karena catatannya memang tidak ada.
--
-- Akibatnya jelas dan harus diketahui: angka Saldo Bank sesudah ini
-- adalah TOTAL YANG PERNAH MASUK lewat penjualan non-tunai, bukan sisa
-- yang benar-benar ada di rekening sekarang. Kalau yang diinginkan
-- adalah saldo yang cocok dengan mutasi bank hari ini, yang tepat bukan
-- berkas ini melainkan satu baris saldo awal sebesar isi rekening pada
-- tanggal tertentu — bilang saja, dan itu yang dibuat.
--
-- Setoran tunai kasir yang disetujui juga TIDAK ikut di sini. Ia jalur
-- lain, dan menambahkannya berarti ikut memutuskan bahwa uang setoran
-- lama masih utuh di rekening.
--
-- ── Aman diulang ────────────────────────────────────────────────────
--
-- Pesanan yang sudah punya baris di akun ini dilewati. Jadi menjalankan
-- berkas ini dua kali tidak menggandakan saldonya, dan pesanan yang
-- lunas sesudah saldo_perusahaan.sql — yang sudah punya barisnya dari
-- trigger — tidak ikut ditulis ulang.

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

-- Berapa yang terisi, per merchant. Jalankan sesudahnya untuk melihat
-- hasilnya sebelum membuka aplikasinya.
--
-- select r.name,
--        count(*) as baris,
--        to_char(sum(j.amount), 'FM999G999G999G999') as total
-- from gl_journal_entries j
-- join gl_accounts a
--   on a.resto_id = j.resto_id
--  and a.payment_method = 'company_bank'
--  and a.gl_code = j.gl_code
-- join restaurants r on r.id = j.resto_id
-- where j.description like '%(backfill)'
-- group by r.name
-- order by r.name;
