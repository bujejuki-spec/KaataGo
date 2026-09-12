-- KaataGo - pendapatan non-tunai masuk Saldo Bank tiap jam 5 pagi WIB.
--
-- Jalankan SETELAH saldo_perusahaan.sql. Aman diulang.
-- Butuh pg_cron: Dashboard → Database → Extensions → cari "pg_cron" →
-- Enable.
--
-- ── Kenapa tidak seketika ────────────────────────────────────────────
--
-- Uang QRIS tidak mendarat di rekening merchant pada detik pelanggan
-- membayar. Ia ditahan penyedia pembayaran dan cair menurut jadwal
-- masing-masing — sehari, dua hari, kadang lebih. Mencatatnya sebagai
-- "sudah di rekening" saat itu juga membuat Saldo Bank menyebut uang
-- yang belum bisa dipakai, dan yang memeriksanya dengan mutasi bank
-- menemukan selisih yang tidak pernah bisa dijelaskan.
--
-- Jadi pencatatannya ditunda sampai jam 5 pagi WIB — jam ketika
-- pencairan semalam pada umumnya sudah masuk. Ini tetap perkiraan,
-- bukan kepastian: yang memastikan tetap rekonsiliasi mutasi bank.
-- Yang dihilangkan adalah selisih yang muncul setiap hari karena
-- penjualan sore ini dihitung sudah di rekening sebelum bank buka.
--
-- ── Yang berubah ────────────────────────────────────────────────────
--
--   sebelum : pesanan lunas → langsung kredit GL Saldo Bank
--   sesudah : pesanan lunas → tidak menyentuh Saldo Bank
--             jam 5 pagi WIB → seluruh pesanan non-tunai yang belum
--             punya barisnya dicatat sekaligus

-- ─────────────────────────────────────────────────────────────────────
-- 1. Pesanan lunas berhenti langsung menyentuh Saldo Bank
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function log_order_paid_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_gl_code text;
  v_now timestamptz := now();
  v_method text;
begin
  if new.payment_status = 'paid' then
    v_method := _normalize_payment_method(new.source, new.payment_method);

    select gl_code into v_gl_code
    from gl_accounts
    where resto_id = new.resto_id and payment_method = v_method
    limit 1;

    if v_gl_code is not null and v_gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id,
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl_code, 'order', new.id::text, new.total, 'credit',
        'Pemasukan pesanan #' || upper(substr(new.id::text, 1, 8))
      );
    end if;
  end if;
  return new;
end;
$fn$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Tugas jam 5 pagi
-- ─────────────────────────────────────────────────────────────────────
--
-- Menyapu seluruh pesanan non-tunai yang lunas dan belum punya barisnya
-- di GL Saldo Bank, bukan hanya pesanan kemarin. Bedanya penting: kalau
-- tugasnya pernah gagal jalan — server sedang mati, pg_cron sempat
-- dimatikan — yang terlewat akan ikut tersapu esok harinya, bukan
-- hilang selamanya.
--
-- Tanggal jurnalnya memakai tanggal PESANANNYA, bukan hari ia dicatat.
-- Tutup buku dan laporan per periode membaca tanggal itu, dan penjualan
-- 30 September yang tercatat 1 Oktober akan membuat kedua bulan salah.

begin;

create or replace function jurnal_pendapatan_bank()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_jumlah integer;
begin
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
    'Masuk rekening #' || upper(substr(o.id::text, 1, 8))
  from orders o
  join gl_accounts a
    on a.resto_id = o.resto_id
   and a.payment_method = 'company_bank'
   and coalesce(a.gl_code, '') <> ''
  where o.payment_status = 'paid'
    and _normalize_payment_method(o.source, o.payment_method)
          in ('qris', 'qris_static', 'transfer')
    and o.resto_id <> 'kaatago'
    -- Yang baru saja dibayar belum ikut: uangnya memang belum cair.
    -- Batasnya jam 5 pagi hari ini, jadi penjualan kemarin sampai lewat
    -- tengah malam semuanya masuk, dan penjualan pagi ini menunggu
    -- besok.
    and o.created_at < date_trunc('day', now() at time zone 'Asia/Jakarta')
                         at time zone 'Asia/Jakarta'
    and not exists (
      select 1 from gl_journal_entries j
      where j.resto_id = o.resto_id
        and j.reference_type = 'order'
        and j.reference_id = o.id::text
        and j.gl_code = a.gl_code
    );

  get diagnostics v_jumlah = row_count;
  return v_jumlah;
end;
$fn$;

commit;

begin;

create extension if not exists pg_cron with schema extensions;

select cron.unschedule('jurnal-pendapatan-bank')
where exists (
  select 1 from cron.job where jobname = 'jurnal-pendapatan-bank'
);

-- 22:00 UTC = 05:00 WIB. pg_cron berjalan dalam UTC, dan menuliskan
-- '0 5 * * *' di sini berarti tugasnya jalan jam 12 siang WIB.
select cron.schedule(
  'jurnal-pendapatan-bank',
  '0 22 * * *',
  $$select jurnal_pendapatan_bank();$$
);

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Setoran modal memilih kantongnya
-- ─────────────────────────────────────────────────────────────────────
--
-- GL Setoran Modal dilepas dari merchant. Akun terpisah untuk uang yang
-- masuk dari luar penjualan terdengar rapi, tapi di layar Saldo
-- Perusahaan ia jadi kantong ketiga yang tidak pernah ditanyakan
-- siapa pun — yang ditanyakan adalah berapa uang di tangan dan berapa
-- di rekening, dan setoran modal mendarat di salah satu dari keduanya.
--
-- Yang menyetor sekarang menyebutkan mendarat di mana.
--
-- KaataGo sendiri tetap memakai GL Setoran Modal: pembukuannya tidak
-- punya laci kasir maupun rekening merchant, jadi tidak ada kantong
-- lain untuk menampungnya.

begin;

alter table balance_topups
  add column if not exists destination text not null default 'bank';

alter table balance_topups drop constraint if exists balance_topups_destination_check;
alter table balance_topups add constraint balance_topups_destination_check
  check (destination in ('cash', 'bank'));

commit;

begin;

create or replace function log_balance_topup()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_akun record;
  v_jenis text;
  v_now timestamptz := now();
begin
  -- KaataGo sendiri tetap ke GL Setoran Modal; merchant ke kantong yang
  -- disebut penyetornya.
  v_jenis := case
    when new.resto_id = 'kaatago' then 'capital'
    when coalesce(new.destination, 'bank') = 'cash' then 'company_cash'
    else 'company_bank'
  end;

  select * into v_akun from _gl_account_for(new.resto_id, v_jenis);
  if v_akun.gl_code is null or v_akun.gl_code = '' then
    return new;
  end if;

  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    new.resto_id,
    (v_now at time zone 'Asia/Jakarta')::date,
    (v_now at time zone 'Asia/Jakarta')::time,
    v_akun.gl_code, v_akun.gl_name,
    'capital', new.id::text, new.amount, 'credit',
    'Setoran modal dari ' || new.source
  );

  return new;
end;
$fn$;

commit;

-- Pemetaan GL Setoran Modal milik merchant dilepas.
--
-- Barisnya di jurnal tidak disentuh: setoran modal yang sudah tercatat
-- tetap berdiri di akun itu, dan menghapusnya berarti menghapus uang
-- yang benar-benar pernah masuk. Yang dilepas cuma pemetaannya, supaya
-- tidak ada setoran BARU yang mendarat di sana.

begin;

delete from gl_accounts
where payment_method = 'capital'
  and resto_id <> 'kaatago';

commit;
