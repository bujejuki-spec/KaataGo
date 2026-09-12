-- KaataGo - Saldo Perusahaan: kas dan bank sebagai dua kantong nyata.
--
-- Jalankan SETELAH jurnal_cash_pickup_benar.sql. Aman diulang.
--
-- Sampai sekarang aplikasi ini bisa menjawab "berapa yang masuk hari
-- ini" dan "berapa isi laci kasir", tapi tidak bisa menjawab pertanyaan
-- yang sebenarnya ditanyakan pemilik usaha: berapa uang perusahaan
-- sekarang, dan di mana — di tangan, atau di rekening.
--
-- Dua akun menjawab itu:
--
--   GL Saldo Cash Perusahaan (1990002)
--     Uang tunai yang sudah lepas dari laci kasir dan benar-benar
--     dipegang perusahaan. Masuk lewat serah terima cash pickup.
--
--   GL Saldo Bank Perusahaan (1990003)
--     Uang di rekening. Masuk dari penjualan non-tunai (QRIS Dinamis,
--     QRIS Statis, Transfer) dan dari setoran tunai kasir yang sudah
--     disetujui Finance.
--
-- Keduanya berkurang oleh pengeluaran, sesuai sumber dana yang dipilih
-- yang mencatatnya — dan itu yang membuat pertanyaan "uang ini diambil
-- dari mana" punya jawaban.
--
-- ── Satu angka, satu sumber ──────────────────────────────────────────
--
-- Saldonya TIDAK dihitung ulang di layar dari tabel pesanan dan
-- setoran. Ia dibaca dari pergerakan kedua akun GL itu, lewat satu
-- fungsi di bawah. Perhitungan kedua yang berdiri sendiri di layar akan
-- berpisah dari jurnalnya pada perubahan berikutnya — dan dua angka
-- yang mengaku menyebut uang yang sama adalah kekeliruan yang paling
-- sering harus diperbaiki di aplikasi ini.
--
-- Aturan saldonya sama dengan yang dipakai seluruh aplikasi: kredit
-- menaikkan, debit menurunkan.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Akun GL-nya
-- ─────────────────────────────────────────────────────────────────────

begin;

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

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'company_bank', '1990003', 'GL Saldo Bank Perusahaan'
from restaurants r
on conflict (resto_id, payment_method) do nothing;

-- Untuk resto yang dibuat sebelum cash pickup ada.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'company_cash', '1990002', 'GL Saldo Cash Perusahaan'
from restaurants r
on conflict (resto_id, payment_method) do nothing;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Pengeluaran menyebut sumber dananya
-- ─────────────────────────────────────────────────────────────────────
--
-- 'petty' — kas kecil kasir, seperti selama ini
-- 'cash'  — uang tunai perusahaan
-- 'bank'  — rekening perusahaan
--
-- Bawaannya 'petty': itu yang berlaku untuk setiap baris yang sudah ada,
-- dan menafsirkan ulang pengeluaran lama sebagai potongan rekening
-- membuat saldo bank berbunyi minus untuk uang yang tidak pernah keluar
-- dari sana.

begin;

alter table expenses
  add column if not exists fund_source text not null default 'petty';

alter table expenses drop constraint if exists expenses_fund_source_check;
alter table expenses add constraint expenses_fund_source_check
  check (fund_source in ('petty', 'cash', 'bank'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Setor ke bank dari uang perusahaan
-- ─────────────────────────────────────────────────────────────────────
--
-- Tabel tersendiri, BUKAN baris baru di `cash_deposits`. Alasannya
-- bukan kerapian: `cashOnHand` mengurangi isi laci kasir sebesar setiap
-- baris cash_deposits yang tidak ditolak. Uang yang disetor di sini
-- sudah lama meninggalkan laci — ia sedang dipegang perusahaan — jadi
-- menaruhnya di tabel itu akan menguranginya untuk kedua kalinya, dan
-- laci kasir berbunyi kurang sebesar setoran yang tidak pernah
-- menyentuhnya.

begin;

create table if not exists company_deposits (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,
  amount bigint not null check (amount > 0),

  -- Rekening tujuannya, kalau disebut. Merchant yang punya beberapa
  -- rekening perlu tahu uangnya mendarat di mana saat mencocokkan
  -- mutasi.
  bank_account_id uuid references bank_accounts (id),

  note text,
  proof_base64 text,

  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists company_deposits_resto_idx
  on company_deposits (resto_id, created_at desc);

alter table company_deposits enable row level security;

-- Dibaca dan ditulis Owner dan Finance saja. Yang dipindahkan di sini
-- bukan uang laci melainkan uang perusahaan, dan yang memegang laci
-- tidak memutuskan itu.
drop policy if exists "company_deposits: finance" on company_deposits;
create policy "company_deposits: finance" on company_deposits
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  );

commit;

begin;

create or replace function log_company_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cash record;
  v_bank record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  -- Meninggalkan kas perusahaan → debit.
  select * into v_cash from _gl_account_for(new.resto_id, 'company_cash');
  if v_cash.gl_code is not null and v_cash.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time, v_cash.gl_code, v_cash.gl_name,
      'company_deposit', new.id::text, new.amount, 'debit',
      'Setor ke bank #' || v_ref
    );
  end if;

  -- Mendarat di rekening → kredit.
  select * into v_bank from _gl_account_for(new.resto_id, 'company_bank');
  if v_bank.gl_code is not null and v_bank.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time, v_bank.gl_code, v_bank.gl_name,
      'company_deposit', new.id::text, new.amount, 'credit',
      'Setoran dari kas perusahaan #' || v_ref
    );
  end if;

  return new;
end;
$fn$;

drop trigger if exists trg_log_company_deposit_journal on company_deposits;
create trigger trg_log_company_deposit_journal
  after insert on company_deposits
  for each row execute function log_company_deposit_journal();

alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance',
     'other_income', 'company_deposit'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Uang yang masuk rekening
-- ─────────────────────────────────────────────────────────────────────
--
-- Penjualan non-tunai mendarat di rekening merchant, bukan di laci. Itu
-- sudah benar sejak dulu di dunia nyata — yang belum ada adalah
-- catatannya, jadi tidak ada satu angka pun yang bisa ditanya "berapa
-- yang ada di rekening sekarang".
--
-- Barisnya ditambahkan di samping baris pemasukan yang sudah ada, bukan
-- menggantikannya: GL Penerimaan QRIS dan kawan-kawannya menjawab
-- "berapa yang terjual lewat cara ini", sedangkan akun ini menjawab "di
-- mana uangnya sekarang". Dua pertanyaan berbeda, dan yang pertama
-- sudah lama dipakai laporan.

begin;

create or replace function log_order_paid_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_gl_code text;
  v_bank record;
  v_now timestamptz := now();
  v_method text;
  v_ref text := upper(substr(new.id::text, 1, 8));
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
        'Pemasukan pesanan #' || v_ref
      );
    end if;

    -- Yang non-tunai mendarat di rekening. Tunai tidak: ia masuk laci,
    -- dan perjalanannya ke perusahaan lewat setoran atau cash pickup —
    -- keduanya sudah punya jurnalnya sendiri.
    if v_method in ('qris', 'qris_static', 'transfer') then
      select * into v_bank from _gl_account_for(new.resto_id, 'company_bank');
      if v_bank.gl_code is not null and v_bank.gl_code <> '' then
        insert into gl_journal_entries (
          resto_id, entry_date, entry_time, gl_code, gl_name,
          reference_type, reference_id, amount, entry_type, description
        ) values (
          new.resto_id,
          (v_now at time zone 'Asia/Jakarta')::date,
          (v_now at time zone 'Asia/Jakarta')::time,
          v_bank.gl_code, v_bank.gl_name, 'order', new.id::text,
          new.total, 'credit', 'Masuk rekening #' || v_ref
        );
      end if;
    end if;
  end if;
  return new;
end;
$fn$;

commit;

-- Setoran tunai kasir yang disetujui ikut mendarat di rekening.

begin;

create or replace function log_cash_deposit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_titipan_gl record;
  v_target_gl record;
  v_bank_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_pickup boolean := coalesce(new.method, 'setor') = 'pickup';
  v_sebut text := case when v_pickup then 'Cash pickup' else 'Setoran' end;
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  -- Pickup yang baru saja diterima menulis jurnalnya sendiri di
  -- `terima_pickup`, berikut jumlah yang benar-benar dihitung penerima.
  if coalesce(new.method, 'setor') = 'pickup' and new.received_at is not null then
    return new;
  end if;

  select * into v_titipan_gl from _gl_account_for(
    new.resto_id, case when v_pickup then 'cash_pickup' else 'suspense' end);
  if v_titipan_gl.gl_code is not null and v_titipan_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_titipan_gl.gl_code, v_titipan_gl.gl_name, 'cash_deposit',
      new.id::text, new.amount, 'debit',
      'Titipan ' || lower(v_sebut) || ' #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    v_target := case when v_pickup then 'company_cash' else 'total_balance' end;
    v_note := v_sebut || ' #' || v_ref || ' disetujui';
  else
    v_target := 'cash';
    v_note := v_sebut || ' #' || v_ref || ' ditolak, kembali ke kas';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'cash_deposit',
      new.id::text, new.amount, 'credit', v_note
    );
  end if;

  -- Setoran bank yang disetujui: uangnya sekarang ada di rekening.
  -- Pickup tidak ikut — tujuannya kas perusahaan, sudah dicatat di atas.
  if new.status = 'approved' and not v_pickup then
    select * into v_bank_gl from _gl_account_for(new.resto_id, 'company_bank');
    if v_bank_gl.gl_code is not null and v_bank_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_bank_gl.gl_code, v_bank_gl.gl_name, 'cash_deposit',
        new.id::text, new.amount, 'credit',
        'Setoran kasir masuk rekening #' || v_ref
      );
    end if;
  end if;

  return new;
end;
$fn$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 5. Pengeluaran memotong kantong yang disebutkan
-- ─────────────────────────────────────────────────────────────────────
--
-- Sisi sumbernya juga diperbaiki arahnya. Sebelumnya petty cash
-- DIKREDIT saat uangnya dipakai — dan kredit menaikkan saldo menurut
-- aturan yang dipakai seluruh aplikasi, jadi tiap pengeluaran justru
-- menambah saldo petty cash di jurnal. Layar Saldo & Pengeluaran tidak
-- pernah menampakkannya karena ia menghitung petty cash dari tabelnya
-- sendiri, bukan dari jurnal.

begin;

create or replace function log_expense_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_expense_gl record;
  v_sumber_gl record;
  v_jenis text;
  v_sebut text;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
begin
  -- Sisi biaya: akun pengeluarannya bertambah.
  if new.gl_code is not null and new.gl_code <> '' then
    select * into v_expense_gl from _expense_gl_account_for(new.resto_id, new.gl_code);
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      new.gl_code, v_expense_gl.gl_name, 'expense', new.id::text,
      new.amount, 'debit', new.description
    );
  end if;

  v_jenis := case coalesce(new.fund_source, 'petty')
               when 'cash' then 'company_cash'
               when 'bank' then 'company_bank'
               else 'petty_cash' end;
  v_sebut := case coalesce(new.fund_source, 'petty')
               when 'cash' then 'Dana dari Saldo Cash Perusahaan'
               when 'bank' then 'Dana dari Saldo Bank Perusahaan'
               else 'Dana dari Petty Cash' end;

  -- Sisi sumber: kantongnya berkurang → debit.
  select * into v_sumber_gl from _gl_account_for(new.resto_id, v_jenis);
  if v_sumber_gl.gl_code is not null and v_sumber_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_sumber_gl.gl_code, v_sumber_gl.gl_name, 'expense', new.id::text,
      new.amount, 'debit', v_sebut
    );
  end if;

  return new;
end;
$fn$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 6. Saldonya, dibaca dari satu tempat
-- ─────────────────────────────────────────────────────────────────────
--
-- Baris pembatalan dan baris yang dibatalkannya sama-sama tidak
-- dihitung — aturan yang sama dengan layar Jurnal GL.

begin;

create or replace function saldo_perusahaan(p_resto_id text)
returns table (cash bigint, bank bigint)
language sql
stable
security definer
set search_path = public
as $fn$
  with berlaku as (
    select j.*
    from gl_journal_entries j
    where j.resto_id = p_resto_id
      and coalesce(j.is_reversal, false) = false
      and not exists (
        select 1 from gl_journal_entries r
        where r.resto_id = j.resto_id
          and coalesce(r.is_reversal, false) = true
          and r.reference_type = j.reference_type
          and r.reference_id = j.reference_id
          and r.gl_code = j.gl_code
      )
  ),
  akun as (
    select payment_method, gl_code
    from gl_accounts
    where resto_id = p_resto_id
      and payment_method in ('company_cash', 'company_bank')
  )
  select
    coalesce(sum(case when a.payment_method = 'company_cash'
      then case when b.entry_type = 'credit' then b.amount else -b.amount end
      else 0 end), 0)::bigint,
    coalesce(sum(case when a.payment_method = 'company_bank'
      then case when b.entry_type = 'credit' then b.amount else -b.amount end
      else 0 end), 0)::bigint
  from akun a
  join berlaku b on b.gl_code = a.gl_code
  where is_super_admin()
     or is_resto_employee(p_resto_id, array['owner', 'finance']);
$fn$;

revoke all on function saldo_perusahaan(text) from public, anon;
grant execute on function saldo_perusahaan(text) to authenticated;

commit;
