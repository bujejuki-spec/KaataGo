-- KaataGo - cara menagih merchant: Virtual Account atau transfer.
--
-- Jalankan SETELAH billing_va.sql dan rekening_perusahaan.sql.
-- Aman diulang.
--
-- Sampai sekarang penagihan hanya punya satu jalan: Virtual Account
-- dari penyedia pembayaran. Itu rapi, tapi tidak selalu ada — VA
-- menuntut akun penyedia yang aktif, dan sebagian merchant ditagih pada
-- masa ketika akunnya belum siap atau sedang bermasalah.
--
-- Yang terjadi kalau VA-nya tidak terbit: tagihannya tetap ada, jatuh
-- temponya tetap berjalan, dan merchant tidak punya satu pun nomor
-- untuk membayar. Yang dia lihat cuma nominal dan tanggal.
--
-- Sekarang KaataGo Admin memilih caranya per merchant. Transfer memakai
-- rekening KaataGo sendiri — yang kebetulan sudah punya tempatnya:
-- `bank_accounts` yang tertaut ke resto platform 'kaatago'. Tidak ada
-- tabel baru untuk menyimpan satu nomor rekening.

begin;

-- 'va'       - Virtual Account dari penyedia pembayaran (cara lama)
-- 'transfer' - transfer manual ke rekening KaataGo
--
-- Bawaannya 'va': itu yang berlaku untuk semua merchant yang sudah ada,
-- dan mengubah cara menagih orang secara diam-diam saat aplikasinya
-- diperbarui bukan hal yang boleh terjadi.
alter table resto_billing
  add column if not exists payment_method text not null default 'va';

alter table resto_billing drop constraint if exists resto_billing_payment_method_check;
alter table resto_billing add constraint resto_billing_payment_method_check
  check (payment_method in ('va', 'transfer'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Rekening KaataGo yang ditampilkan ke merchant
-- ─────────────────────────────────────────────────────────────────────
--
-- Dibaca merchant — dan hanya inilah satu-satunya baris `bank_accounts`
-- yang boleh dilihat orang di luar restonya sendiri. Tanpa policy ini,
-- merchant yang membuka tagihannya melihat kolom kosong: rekening
-- KaataGo bukan miliknya, jadi RLS menyembunyikannya dengan benar dan
-- merchant tidak punya nomor untuk mentransfer.
--
-- Yang dibuka cuma yang tertaut ke resto platform. Rekening merchant
-- lain tetap tidak terlihat.

begin;

create or replace function _rekening_kaatago(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from resto_bank_accounts rb
    where rb.bank_account_id = p_id
      and rb.resto_id = 'kaatago'
  );
$$;

drop policy if exists "bank_accounts: rekening kaatago terbuka" on bank_accounts;
create policy "bank_accounts: rekening kaatago terbuka" on bank_accounts
  for select using (_rekening_kaatago(id));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Bukti bayar tagihan wajib
-- ─────────────────────────────────────────────────────────────────────
--
-- Alasannya sama dengan setoran tunai: menyatakan sudah membayar tanpa
-- melampirkan apa pun berarti yang memeriksanya nanti tidak punya
-- pembanding terhadap mutasi rekening. Dan berbeda dari setoran, yang
-- menyatakannya di sini adalah pihak lain — bukan karyawan sendiri.
--
-- Ditegakkan saat status berpindah ke 'review', bukan sebagai NOT NULL:
-- kolomnya juga dipakai tagihan yang belum dibayar sama sekali, dan
-- baris-baris itu memang belum punya bukti apa pun.

begin;

create or replace function _wajib_bukti_tagihan()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'review'
     and coalesce(btrim(new.proof_base64), '') = '' then
    raise exception 'Bukti pembayaran wajib dilampirkan.';
  end if;
  return new;
end;
$$;

drop trigger if exists wajib_bukti_tagihan on billing_invoices;
create trigger wajib_bukti_tagihan
  before insert or update on billing_invoices
  for each row
  execute function _wajib_bukti_tagihan();

commit;
