-- KaataGo - deret waktu dan pembagian untuk grafik Laporan Penjualan.
--
-- Jalankan SETELAH merchant_report.sql. Aman diulang.
--
-- Laporan Penjualan sudah menjawab "menu mana yang laku" dan "jam berapa
-- ramai". Yang belum dijawabnya justru pertanyaan pertama yang diajukan
-- orang saat membuka laporan: naik atau turun.
--
-- Angka satu rentang tidak bisa menjawab itu. Omzet tiga puluh juta
-- sebulan terbaca bagus atau buruk hanya kalau terlihat bentuknya dari
-- hari ke hari — dan bentuk itu tidak bisa dibayangkan dari satu angka
-- betapa pun besarnya.
--
-- ── Kenapa lubangnya diisi nol ──────────────────────────────────────
--
-- Hari tanpa penjualan tidak punya baris di `orders`. Grafik yang cuma
-- menggambar hari-hari yang ada barisnya menyambung Senin langsung ke
-- Rabu dengan garis yang naik mulus — dan hari Selasa yang tutup total
-- terbaca sebagai hari biasa. Deret di bawah membuat setiap hari dalam
-- rentangnya punya barisnya sendiri, termasuk yang nol.
--
-- ── Siapa yang boleh membacanya ─────────────────────────────────────
--
-- Owner dan Admin, sama seperti sisa laporannya. Syaratnya ditulis
-- sebagai bagian WHERE, bukan `raise`: yang tidak berhak menerima
-- daftar kosong, karena pesan galat justru mengonfirmasi datanya ada.
--
-- Merchantnya sendiri yang dibaca, bukan yang diminta pemanggilnya
-- begitu saja: `is_resto_employee` memeriksa bahwa yang bertanya memang
-- bekerja di resto itu, jadi id merchant yang ditukar di aplikasi tetap
-- tidak membuka angka merchant lain.

-- ─────────────────────────────────────────────────────────────────────
-- Deret waktu
-- ─────────────────────────────────────────────────────────────────────
--
-- Harian, mingguan, atau bulanan. Rentang setahun yang digambar harian
-- menjadi 365 batang selebar rambut di layar HP; yang sama digambar
-- bulanan menjadi dua belas batang yang bisa dibaca sekilas.
--
-- Mingguannya mulai Senin — minggu kerja, bukan minggu kalender yang
-- memotong akhir pekan jadi dua bagian di dua batang berbeda.
create or replace function report_sales_series(
  p_resto_id text,
  p_from date,
  p_to date,
  p_bucket text default 'day')
returns table (
  periode date,
  orders_count bigint,
  omzet bigint,
  qty bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with satuan as (
    select case lower(coalesce(p_bucket, 'day'))
             when 'week' then 'week'
             when 'month' then 'month'
             else 'day'
           end as b
  ),
  kerangka as (
    select date_trunc((select b from satuan), d)::date as periode
    from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d
    group by 1
  ),
  isi as (
    select date_trunc((select b from satuan),
             (o.created_at at time zone 'Asia/Jakarta'))::date as periode,
           count(*) as orders_count,
           coalesce(sum(o.total), 0)::bigint as omzet,
           coalesce(sum((
             select sum((item ->> 'quantity')::bigint)
             from jsonb_array_elements(o.items) item
           )), 0)::bigint as qty
    from orders o
    where o.resto_id = p_resto_id
      and o.payment_status = 'paid'
      and is_resto_employee(p_resto_id, array['owner', 'admin'])
      and (o.created_at at time zone 'Asia/Jakarta')::date
          between p_from and p_to
    group by 1
  )
  select k.periode,
         coalesce(i.orders_count, 0),
         coalesce(i.omzet, 0),
         coalesce(i.qty, 0)
  from kerangka k
  left join isi i on i.periode = k.periode
  order by k.periode;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Pembagian
-- ─────────────────────────────────────────────────────────────────────
--
-- Satu fungsi untuk empat sudut pandang, bukan empat fungsi.
--
-- Keempatnya menjawab pertanyaan berbentuk sama — "dari mana omzet ini
-- datang" — dan cuma berbeda pada kolom yang dikelompokkan. Memecahnya
-- jadi empat fungsi berarti empat tempat yang harus ikut berubah setiap
-- kali aturan "pesanan mana yang dihitung" berubah, dan yang terjadi
-- berikutnya selalu sama: satu di antaranya ketinggalan.
--
-- Nilai p_dimensi yang tidak dikenal jatuh ke cara bayar, bukan galat.
create or replace function report_sales_breakdown(
  p_resto_id text,
  p_from date,
  p_to date,
  p_dimensi text default 'payment_method')
returns table (
  kunci text,
  orders_count bigint,
  omzet bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(btrim(
           case lower(coalesce(p_dimensi, 'payment_method'))
             when 'order_type' then o.order_type
             when 'source' then o.source
             when 'cashier' then coalesce(o.cashier_name, o.customer_label)
             else o.payment_method
           end), ''), 'lainnya'),
         count(*),
         coalesce(sum(o.total), 0)::bigint
  from orders o
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and (o.created_at at time zone 'Asia/Jakarta')::date
        between p_from and p_to
  group by 1
  order by 3 desc;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Pembagian per kategori menu
-- ─────────────────────────────────────────────────────────────────────
--
-- Terpisah dari yang di atas karena bentuk datanya memang lain: yang
-- dikelompokkan baris menu di dalam pesanan, bukan pesanannya. Satu
-- pesanan berisi minuman dan makanan masuk ke dua kategori sekaligus,
-- dan menjumlahkan `orders.total` ke keduanya akan menghitung uang yang
-- sama dua kali.
--
-- Jadi yang dijumlahkan harga barisnya, dan jumlahnya memang tidak
-- persis sama dengan omzet — service per tagihan dan potongan tidak
-- menempel di baris mana pun. Itu disebut di layarnya.
--
-- Kategorinya dibaca dari katalog lewat productId. Menu yang sudah
-- dihapus dari katalog tetap punya sejarah penjualan: ia jatuh ke
-- "Tanpa kategori", bukan hilang dari jumlahnya.
create or replace function report_sales_by_category(
  p_resto_id text,
  p_from date,
  p_to date)
returns table (
  kunci text,
  qty bigint,
  omzet bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(btrim(p.category), ''), 'Tanpa kategori'),
         sum((item ->> 'quantity')::bigint),
         sum((item ->> 'price')::bigint * (item ->> 'quantity')::bigint)
  from orders o
       cross join lateral jsonb_array_elements(o.items) item
       left join products p
              on p.id = item ->> 'productId' and p.resto_id = o.resto_id
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and is_resto_employee(p_resto_id, array['owner', 'admin'])
    and (o.created_at at time zone 'Asia/Jakarta')::date
        between p_from and p_to
  group by 1
  order by 3 desc;
$$;

grant execute on function report_sales_series(text, date, date, text)
  to authenticated;
grant execute on function report_sales_breakdown(text, date, date, text)
  to authenticated;
grant execute on function report_sales_by_category(text, date, date)
  to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from report_sales_series('<resto_id>', '2026-08-01', '2026-08-31', 'day');
--   select * from report_sales_breakdown('<resto_id>', '2026-08-01', '2026-08-31', 'payment_method');
--   select * from report_sales_by_category('<resto_id>', '2026-08-01', '2026-08-31');
