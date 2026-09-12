-- KaataGo - Owner dan Finance benar-benar bisa menambah rekening.
--
-- Jalankan SETELAH rekening_perusahaan.sql. Aman diulang.
--
-- Menambah rekening selama ini cuma berhasil untuk Super Admin, dan
-- bukan karena perannya dibatasi di suatu tempat. Ada dua hal yang
-- saling mengunci:
--
-- 1. Policy tulis `bank_accounts` mengizinkan baris yang SUDAH tertaut
--    ke resto si penulis. Saat menambah rekening baru, tautannya belum
--    ada — ia baru dibuat sesudah barisnya jadi. Jadi with-check-nya
--    memeriksa sesuatu yang mustahil ada, dan INSERT-nya selalu
--    ditolak. Super Admin lolos hanya karena is_super_admin() berdiri
--    di depan pemeriksaan itu.
--
-- 2. Bahkan seandainya nomor rekening itu sudah pernah dicatat resto
--    lain, policy BACA menyembunyikannya. Aplikasi mencarinya dulu
--    supaya tidak membuat baris kedua, tidak menemukan apa-apa, lalu
--    memasukkannya — dan unique index menolaknya sebagai duplikat.
--    Yang terbaca orang: "gagal menyimpan", tanpa sebab.
--
-- Keduanya diselesaikan di satu tempat: sebuah fungsi yang memeriksa
-- peran penulisnya sendiri, lalu mencari-atau-membuat rekeningnya dan
-- menautkannya dalam satu transaksi. Policy-nya tidak dilonggarkan —
-- yang dilakukan justru sebaliknya: pemeriksaannya jadi eksplisit dan
-- ada di satu tempat, bukan tersebar sebagai syarat yang tak terpenuhi.

begin;

create or replace function simpan_rekening(
  p_resto_id text,
  p_bank_name text,
  p_account_number text,
  p_account_holder text,
  p_label text default null,
  p_utama boolean default false
)
returns bank_accounts
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_bank text := btrim(p_bank_name);
  v_nomor text := btrim(p_account_number);
  v_nama text := btrim(p_account_holder);
  v_label text := nullif(btrim(coalesce(p_label, '')), '');
  v_row bank_accounts;
begin
  -- Perannya diperiksa di sini, bukan diserahkan ke policy: fungsi ini
  -- security definer, jadi ia melewati RLS dan harus membawa
  -- pemeriksaannya sendiri.
  if not (
    public.is_super_admin()
    or public.is_resto_employee(p_resto_id, array['owner', 'finance'])
  ) then
    raise exception 'Hanya Owner dan Finance yang bisa mengatur rekening.';
  end if;

  if v_bank = '' or v_nomor = '' or v_nama = '' then
    raise exception 'Bank, nomor rekening, dan nama pemilik wajib diisi.';
  end if;

  -- Cari dulu. Nomor yang sama di bank yang sama adalah rekening yang
  -- sama — termasuk kalau yang mencatatnya lebih dulu adalah cabang
  -- lain yang tidak terlihat dari sini.
  select * into v_row
  from bank_accounts
  where lower(bank_name) = lower(v_bank)
    and account_number = v_nomor;

  if not found then
    insert into bank_accounts (bank_name, account_number, account_holder,
                               label, created_by)
    values (v_bank, v_nomor, v_nama, v_label, auth.uid()::text)
    returning * into v_row;
  else
    -- Yang sudah ada tidak ditimpa namanya begitu saja: rekening milik
    -- bersama, dan resto yang menautkannya belakangan tidak berhak
    -- mengganti nama pemilik yang dipakai resto lain. Yang diperbarui
    -- cuma label kalau sebelumnya kosong.
    if v_row.label is null and v_label is not null then
      update bank_accounts set label = v_label, updated_at = now()
      where id = v_row.id
      returning * into v_row;
    end if;
  end if;

  -- Yang lama diturunkan lebih dulu; satu resto cuma boleh punya satu
  -- rekening utama, dan menaikkan yang baru duluan akan ditolak.
  if p_utama then
    update resto_bank_accounts set is_primary = false
    where resto_id = p_resto_id;
  end if;

  insert into resto_bank_accounts (resto_id, bank_account_id, is_primary)
  values (p_resto_id, v_row.id, p_utama)
  on conflict (resto_id, bank_account_id)
  do update set is_primary = excluded.is_primary;

  return v_row;
end;
$fn$;

revoke all on function simpan_rekening(text, text, text, text, text, boolean)
  from public, anon;
grant execute on function simpan_rekening(text, text, text, text, text, boolean)
  to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Mengubah rekening yang sudah tertaut
-- ─────────────────────────────────────────────────────────────────────
--
-- Ini sebenarnya sudah bisa lewat policy biasa — tautannya sudah ada,
-- jadi with-check-nya terpenuhi. Yang tidak bisa adalah mengubah nomor
-- rekeningnya menjadi nomor yang sudah dipakai baris lain: unique index
-- menolaknya, dan barisnya tidak terlihat jadi orang tidak tahu kenapa.
-- Pesannya dibuat menjelaskan.

begin;

create or replace function _bentrok_rekening()
returns trigger
language plpgsql
as $fn$
begin
  if exists (
    select 1 from bank_accounts b
    where b.id <> new.id
      and lower(b.bank_name) = lower(btrim(new.bank_name))
      and b.account_number = btrim(new.account_number)
  ) then
    raise exception
      'Nomor rekening ini sudah terdaftar. Pakai yang sudah ada, jangan buat baru.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists bentrok_rekening on bank_accounts;
create trigger bentrok_rekening
  before insert or update of bank_name, account_number on bank_accounts
  for each row
  execute function _bentrok_rekening();

commit;
