-- KaataGo - QRIS Statis, dan metode bayar yang bisa dipilih merchant.
--
-- Jalankan SETELAH default_gl_accounts.sql, gateway_settlement.sql, dan
-- cash_variance_lebih.sql. Aman diulang.
--
-- Tiga hal sekaligus, dan ketiganya saling bergantung:
--
--   1. Merchant memilih metode bayar mana yang ditawarkan. Sampai
--      sekarang tunai, QRIS, dan transfer selalu ketiganya tampil, di
--      kasir maupun di HP pelanggan. Resto yang tidak punya QRIS tetap
--      menawarkannya, dan yang memilihnya berhenti di layar yang tidak
--      bisa dibayar.
--
--   2. QRIS Statis: QR cetak milik merchant sendiri, difoto sekali lalu
--      ditampilkan ke pelanggan. Uangnya masuk langsung ke rekening
--      merchant tanpa melewati penyedia pembayaran.
--
--   3. Karena itu jurnalnya harus terpisah. QRIS lewat Xendit punya
--      pencairan yang menyusul dan potongan biayanya; QRIS Statis tidak
--      punya keduanya — uangnya sudah di sana sejak detik pelanggan
--      membayar. Menyatukan keduanya di satu akun membuat angka
--      pencairan gateway menagih uang yang tidak pernah dititipkan ke
--      siapa pun.
--
-- Yang lama TIDAK diganti nilainya, hanya namanya. Nilai 'qris' di
-- kolom payment_method tersebar di ribuan baris pesanan, jurnal, dan
-- pencairan; menggantinya berarti menulis ulang sejarah dan berharap
-- tidak ada satu pun tempat yang terlewat. Yang berubah cuma label yang
-- dibaca orang.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Metode bayar yang ditawarkan merchant
-- ─────────────────────────────────────────────────────────────────────
--
-- Kolom terpisah, bukan satu daftar. Daftar menuntut yang membacanya
-- tahu isi lengkapnya lebih dulu; kolom menjawab satu pertanyaan yang
-- jelas dan bisa dibaca RLS maupun layar tanpa menguraikan apa pun.
--
-- Tunai menyala bawaan dan tidak boleh dimatikan sendirian — merchant
-- yang mematikan semuanya berhenti bisa menerima uang sama sekali, dan
-- itu bukan keadaan yang pantas dicapai lewat satu saklar. Batasannya
-- di bawah.
alter table settings add column if not exists allow_cash boolean not null default true;
alter table settings add column if not exists allow_qris boolean not null default true;
alter table settings add column if not exists allow_qris_static boolean not null default false;
alter table settings add column if not exists allow_transfer boolean not null default true;

-- Tautan gambar QR statisnya di Storage.
--
-- Di Storage, bukan base64 di baris ini. Tabel `settings` disiarkan
-- realtime ke layar pembayaran tiap pelanggan — gambar di dalamnya
-- terkirim ulang tiap kali ada satu kolom yang berubah, ke semua orang
-- yang sedang membuka layarnya. Itu persis penyakit yang baru saja
-- diperbaiki pada foto menu.
alter table settings add column if not exists qris_static_url text;

-- Isi payload QR-nya, hasil pemindaian saat diunggah.
--
-- Disimpan supaya pemeriksaan "ini benar QRIS, bukan foto kucing" bisa
-- ditegakkan server juga, bukan cuma di aplikasi yang mengunggah.
alter table settings add column if not exists qris_static_payload text;

alter table settings drop constraint if exists settings_metode_aktif_check;
alter table settings add constraint settings_metode_aktif_check
  check (allow_cash or allow_qris or allow_qris_static or allow_transfer);

-- QRIS Statis tidak bisa dinyalakan sebelum QR-nya ada.
--
-- Tanpa ini, merchant bisa menawarkan metode yang layarnya kosong — dan
-- pelanggan yang memilihnya berdiri di depan kasir memandangi tempat
-- yang seharusnya berisi QR.
alter table settings drop constraint if exists settings_qris_static_check;
alter table settings add constraint settings_qris_static_check
  check (not allow_qris_static or qris_static_url is not null);

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Metode bayar baru dikenali seluruh jalur
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_payment_method in ('cash', 'qris', 'qris_static', 'transfer')
      then p_payment_method
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    when p_payment_method = 'Tunai' then 'cash'
    when p_source = 'customer' then 'qris'
    else 'cash'
  end;
$$;

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'qris_static', 'transfer', 'petty_cash',
     'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance', 'other_income',
     'cash_pickup', 'company_cash', 'company_bank'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Akun GL-nya
-- ─────────────────────────────────────────────────────────────────────

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
    -- Pajak & service
    ('ppn',              '1960001', 'GL PPN Keluaran'),
    ('service',          '1960002', 'GL Biaya Service'),
    -- Petty cash
    ('petty_cash',       '1980001', 'GL Petty Cash'),
    -- Total saldo
    ('total_balance',    '1990001', 'GL Total Saldo'),
    -- Suspense — titipan yang belum diakui masuk ke mana pun
    ('suspense',         '2100001', 'GL Suspense Setoran'),
    ('suspense_petty',   '2100002', 'GL Suspense Petty Cash'),
    -- Payment gateway & diskon
    ('gateway_fee',      '2200001', 'GL Biaya Payment Gateway'),
    ('discount',         '2200002', 'GL Diskon Penjualan');
$$;

-- Yang sudah ada ikut dapat akun barunya, tanpa menyentuh pemetaan yang
-- sudah disesuaikan sendiri oleh merchant.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'qris_static', '1950004', 'GL Penerimaan QRIS Statis'
from restaurants r
where not exists (
  select 1 from gl_accounts g
  where g.resto_id = r.id and g.payment_method = 'qris_static'
);

-- Namanya saja yang berubah, dan hanya yang masih memakai nama bawaan
-- lamanya. Merchant yang sudah menamainya sendiri tidak ditimpa —
-- pemetaan GL adalah keputusan pembukuan mereka, bukan milik kita.
update gl_accounts
   set gl_name = 'GL Penerimaan QRIS Dinamis'
 where payment_method = 'qris'
   and gl_name = 'GL Penerimaan QRIS';

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Ember penyimpanan QR statisnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Publik dibaca: QR-nya ditampilkan ke pelanggan yang belum tentu punya
-- akun, termasuk yang memesan lewat web setelah memindai QR meja. Yang
-- publik hanya membacanya.

insert into storage.buckets (id, name, public)
values ('qris-statis', 'qris-statis', true)
on conflict (id) do update set public = true;

-- Berkasnya bernama `<resto_id>.png`, jadi segmen pertamanya adalah
-- nama berkas itu sendiri — bukan folder. Yang dibandingkan karena itu
-- nama tanpa ekstensinya.
drop policy if exists "qris-statis: baca karyawan" on storage.objects;
create policy "qris-statis: baca karyawan" on storage.objects
  for select using (
    bucket_id = 'qris-statis'
    and (public.is_super_admin()
      or public.is_resto_employee(split_part(name, '.', 1),
                                    array['owner', 'finance', 'admin']))
  );

drop policy if exists "qris-statis: tulis karyawan" on storage.objects;
create policy "qris-statis: tulis karyawan" on storage.objects
  for insert with check (
    bucket_id = 'qris-statis'
    and (public.is_super_admin()
      or public.is_resto_employee(split_part(name, '.', 1),
                                    array['owner', 'finance']))
  );

drop policy if exists "qris-statis: ubah karyawan" on storage.objects;
create policy "qris-statis: ubah karyawan" on storage.objects
  for update using (
    bucket_id = 'qris-statis'
    and (public.is_super_admin()
      or public.is_resto_employee(split_part(name, '.', 1),
                                    array['owner', 'finance']))
  );

drop policy if exists "qris-statis: hapus karyawan" on storage.objects;
create policy "qris-statis: hapus karyawan" on storage.objects
  for delete using (
    bucket_id = 'qris-statis'
    and (public.is_super_admin()
      or public.is_resto_employee(split_part(name, '.', 1),
                                    array['owner', 'finance']))
  );
