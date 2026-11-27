-- ═══════════════════════════════════════════════════════════════════════
-- KaataGo — satu berkas, jalankan sekali dari atas ke bawah.
-- ═══════════════════════════════════════════════════════════════════════
--
-- ⚠ POTRET SEKALI PAKAI, bukan sumber kebenaran.
--
-- Isinya salinan tiga berkas di `supabase/` pada saat gabungan ini
-- dibuat. Begitu salah satunya diubah, berkas ini basi — dan gabungan
-- yang basi berbahaya justru karena ia tetap berjalan tanpa galat, lalu
-- menimpa fungsi dengan versi lama.
--
-- Yang menjaganya `test/gabungan_sql_tidak_basi_test.dart`: ia menolak
-- gabungan yang membawa fungsi yang sudah ada penggantinya di berkas
-- yang jalan belakangan.
--
-- Aman diulang: semuanya `create or replace`, `on conflict do nothing`,
-- dan backfill yang melewati baris yang sudah punya jurnalnya.
--
-- ── Tiap bagian punya begin/commit sendiri ───────────────────────────
--
-- Disengaja. Satu galat di bagian ketiga tidak membatalkan dua bagian
-- yang sudah benar — yang perlu diulang hanya bagian itu dan sesudahnya.
-- Nomor bagiannya tertulis di komentar pemisah di bawah, jadi pesan
-- galat Supabase bisa langsung dicocokkan.
--
-- ── Urutannya ────────────────────────────────────────────────────────
--
--   1. akun_gl_perusahaan_lengkap       tujuh akun GL yang hilang + jurnal terlewat
--   2. lunas_langsung_disiapkan         lunas langsung masuk Diproses
--   3. push_pending_payment_qris        notifikasi Pending Payment untuk QRIS Statis
--
-- Ketiganya berdiri sendiri — tidak ada yang bergantung pada yang lain.
-- Urutan ini cuma supaya nomor bagiannya tetap sama kalau dijalankan
-- ulang sebagian.



-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 1 dari 3 — akun_gl_perusahaan_lengkap.sql
-- ═══════════════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 2 dari 3 — lunas_langsung_disiapkan.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pesanan yang lunas langsung masuk Diproses.
--
-- Jalankan SETELAH mark_order_paid.sql. Aman diulang.
--
-- ═══════════════════════════════════════════════════════════════════
-- Kenapa di basis data, bukan di aplikasi
-- ═══════════════════════════════════════════════════════════════════
--
-- `payment_status` jadi 'paid' dari enam tempat yang berbeda:
--
--   mark_order_paid()        — pelanggan QRIS dari HP-nya sendiri
--   payment_gateway          — webhook penyedia pembayaran
--   qris_hangus              — pelunasan setelah QR kedaluwarsa
--   settleCashPayment()      — kasir menerima tunai (UPDATE langsung)
--   settlePayment()          — kasir mengganti cara bayarnya
--   insert pesanan           — penjualan kasir yang lahir sudah lunas
--
-- Tiga yang pertama fungsi SQL, dua berikutnya UPDATE langsung dari
-- aplikasi, yang terakhir INSERT. Menaruh aturannya di aplikasi berarti
-- menuliskannya enam kali dan melupakannya di tempat ketujuh — dan yang
-- terlupa tidak akan berbunyi: pesanannya cuma diam di Menunggu
-- Diproses sampai ada yang menyadarinya.
--
-- Satu pemicu BEFORE menjangkau keenamnya.
--
-- ── Kenapa BEFORE, bukan AFTER ───────────────────────────────────────
--
-- BEFORE mengubah barisnya sebelum ditulis: satu kali tulis, dan tidak
-- ada pemicu yang memanggil dirinya sendiri. AFTER harus menjalankan
-- UPDATE kedua — yang membangunkan pemicu ini lagi, mengirim dua
-- payload realtime untuk satu perubahan, dan membuat tiap pelanggan yang
-- membuka menu menerima barisnya dua kali.

begin;

create or replace function _pesanan_lunas_langsung_disiapkan()
returns trigger
language plpgsql
as $fn$
begin
  -- Hanya dari 'waiting'.
  --
  -- Sengaja bukan "apa pun selain done": pesanan yang sudah ditandai
  -- selesai lalu cara bayarnya diperbaiki kasir TIDAK boleh kembali ke
  -- Diproses. Yang terlihat waiter adalah pesanan selesai yang
  -- tiba-tiba muncul lagi di antrean, tanpa ada yang memesannya.
  --
  -- 'cancelled' juga tidak ikut, dengan alasan yang sama.
  if new.payment_status = 'paid'
     and coalesce(new.kitchen_status, 'waiting') = 'waiting' then
    new.kitchen_status := 'onProgress';
  end if;
  return new;
end;
$fn$;

-- `update of payment_status` saja, bukan seluruh kolom.
--
-- Baris pesanan diperbarui sering — status dapur, barang yang sudah
-- siap, catatan. Pemicu yang bangun di tiap perubahan itu bekerja
-- berkali-kali untuk menjawab pertanyaan yang jawabannya tidak berubah.
--
-- `kitchen_status` sengaja TIDAK ikut dalam daftar. Kalau ikut, siapa
-- pun yang nanti menambahkan tombol "kembalikan ke Menunggu" akan
-- mendapati tombolnya tidak bekerja — statusnya dilontarkan balik ke
-- Diproses di dalam transaksi yang sama, tanpa jejak.
drop trigger if exists trg_lunas_langsung_disiapkan on orders;
create trigger trg_lunas_langsung_disiapkan
  before insert or update of payment_status on orders
  for each row execute function _pesanan_lunas_langsung_disiapkan();

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Pesanan hari ini yang sudah lunas tapi masih menunggu
-- ═══════════════════════════════════════════════════════════════════
--
-- Mereka berada di keadaan yang sudah tidak ada lagi dalam alur baru:
-- lunas, tapi menunggu konfirmasi yang tombolnya dicabut.
--
-- ── Kenapa hanya hari ini ────────────────────────────────────────────
--
-- `watchAktif` — yang mengisi layar Status Pesanan — tidak menyaring
-- tanggal; ia mengambil sejumlah pesanan terbaru. Mendorong SELURUH
-- pesanan lunas-tapi-menunggu sejak hari pertama ke Diproses berarti
-- membangkitkan pesanan berbulan lalu ke dalam antrean waiter hari ini.
--
-- Yang kemarin dan sebelumnya ditinggalkan apa adanya. Itu riwayat, dan
-- riwayat tidak perlu diperbaiki supaya cocok dengan alur yang baru.

begin;

update orders
set kitchen_status = 'onProgress'
where payment_status = 'paid'
  and coalesce(kitchen_status, 'waiting') = 'waiting'
  and created_at >= date_trunc('day', now() at time zone 'Asia/Jakarta')
                      at time zone 'Asia/Jakarta';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Memeriksanya
-- ═══════════════════════════════════════════════════════════════════
--
-- Pemicunya terpasang?
--
--   select tgname, tgenabled
--   from pg_trigger
--   where tgrelid = 'orders'::regclass and not tgisinternal;
--
-- Masih ada yang lunas tapi menunggu? (hari ini harus 0)
--
--   select (created_at at time zone 'Asia/Jakarta')::date as tanggal,
--          count(*)
--   from orders
--   where payment_status = 'paid'
--     and coalesce(kitchen_status, 'waiting') = 'waiting'
--   group by 1
--   order by 1 desc;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 3 dari 3 — push_pending_payment_qris.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pesanan pelanggan yang menunggu dibayar juga berbunyi
-- untuk QRIS Statis, bukan cuma tunai.
--
-- Jalankan SETELAH push_notifications.sql. Aman diulang.
--
-- ═══════════════════════════════════════════════════════════════════
-- Yang salah
-- ═══════════════════════════════════════════════════════════════════
--
-- `queue_push_pending_payment` menyaring `new.payment_method = 'cash'`.
-- Waktu ia ditulis, tunai memang satu-satunya cara bayar yang
-- menyisakan pekerjaan di kasir.
--
-- QRIS Statis menyisakan pekerjaan yang sama — kasir yang menyatakan
-- lunasnya, karena QR statis tidak membawa nominal dan tidak ada kabar
-- apa pun dari penyedia pembayaran. Tapi saringan itu tidak pernah
-- ikut diperlebar, jadi pesanan QRIS Statis masuk ke Pending Payment
-- tanpa satu pun pemberitahuan.
--
-- Tidak ada galat. Pesanannya ada di daftar, cuma tidak ada yang tahu
-- ia datang.
--
-- ── Memakai `isAwaitingPayment`-nya aplikasi, bukan daftar cara bayar
--
-- Aplikasi menentukan "menunggu dibayar" begitu: pesanan dari pelanggan
-- yang pembayarannya masih pending — tanpa menyebut cara bayarnya sama
-- sekali (`CustomerOrder.isAwaitingPayment`).
--
-- Fungsi ini sekarang bertanya dengan cara yang sama. Daftar cara bayar
-- yang ditulis tangan di sini adalah daftar yang akan ketinggalan lagi
-- pada cara bayar berikutnya — persis yang baru saja terjadi.

begin;

create or replace function queue_push_pending_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cara text;
begin
  -- Tidak menyaring cara bayarnya.
  --
  -- Pesanan pelanggan yang pembayarannya masih pending SELALU
  -- menyisakan pekerjaan di kasir, cara bayarnya apa pun. Yang
  -- membedakan cuma kalimatnya.
  if new.source = 'customer' and new.payment_status = 'pending' then
    v_cara := case new.payment_method
      when 'cash' then 'Pelanggan memilih bayar tunai di kasir'
      when 'qris_static' then 'Pelanggan bayar QRIS — tunggu bukti transfernya'
      else 'Menunggu pembayaran'
    end;

    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'pending_payment',
      jsonb_build_object(
        -- Sama dengan yang punya akses menu Pending Payment di
        -- `lib/utils/katalog_menu.dart`. Peran yang tidak bisa membuka
        -- layarnya tidak perlu dibangunkan olehnya.
        'audience', 'role', 'roles', array['kasir', 'admin', 'owner'],
        'title', 'Pesanan menunggu dibayar',
        'body', v_cara || ' — #' || upper(substr(new.id::text, 1, 8))
      )
    );
  end if;
  return new;
end;
$$;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Memeriksanya
-- ═══════════════════════════════════════════════════════════════════
--
-- Pemicunya masih terpasang? (fungsinya diganti, pemicunya tidak)
--
--   select tgname from pg_trigger
--   where tgrelid = 'orders'::regclass
--     and tgname = 'trg_queue_push_pending_payment';
--
-- Yang terkirim belakangan — isi kalimatnya menyebut cara bayarnya,
-- jadi tidak perlu disambungkan ke tabel pesanan:
--
--   select payload->>'body' as kabar, created_at
--   from push_outbox
--   where event = 'pending_payment'
--     and created_at > now() - interval '2 days'
--   order by created_at desc
--   limit 20;
--
-- Masih ada pesanan menunggu bayar yang TIDAK punya barisnya?
-- (harus 0 untuk pesanan sesudah query ini dijalankan)
--
--   select o.id, o.payment_method, o.created_at
--   from orders o
--   where o.source = 'customer'
--     and o.payment_status = 'pending'
--     and o.created_at > now() - interval '1 day'
--     and not exists (
--       select 1 from push_outbox p
--       where p.event = 'pending_payment'
--         and p.resto_id = o.resto_id
--         and p.payload->>'body' like '%' ||
--             upper(substr(o.id::text, 1, 8))
--     );
