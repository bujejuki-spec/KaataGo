-- KaataGo - rekening perusahaan berdiri sendiri, tidak menempel di resto.
--
-- Jalankan SETELAH resto_payment_accounts.sql dan tutup_buku_harian.sql.
-- Aman diulang.
--
-- Sampai sekarang rekening disimpan sebagai tiga kolom di `settings`:
-- nama bank, nomor, dan atas nama. Satu resto satu rekening, dan
-- rekeningnya tidak punya keberadaan sendiri — ia cuma keterangan yang
-- menempel.
--
-- Itu cukup selama satu merchant berarti satu resto. Begitu sebuah
-- perusahaan punya beberapa cabang yang menyetor ke rekening yang sama,
-- bentuk itu mulai berbohong dengan tiga cara sekaligus:
--
--   1. Nomor yang sama diketik ulang di tiap cabang, dan satu digit yang
--      keliru di salah satunya menghasilkan setoran yang tidak pernah
--      bisa dicocokkan dengan mutasi mana pun.
--
--   2. Mengganti rekening perusahaan berarti menyunting tiap cabang satu
--      per satu, dan yang terlewat tetap menyetor ke rekening lama.
--
--   3. Rekonsiliasi mutasi bank tidak bisa dikerjakan sama sekali. Satu
--      mutasi masuk ke REKENING, bukan ke resto — dan kalau rekeningnya
--      cuma keterangan di tiga baris berbeda, tidak ada satu pun tempat
--      untuk menautkan mutasi itu.
--
-- Yang ketiga itu alasan sebenarnya. Dua yang pertama merepotkan; yang
-- ketiga membuat tahap berikutnya mustahil.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Rekeningnya
-- ─────────────────────────────────────────────────────────────────────

create table if not exists bank_accounts (
  id uuid primary key default gen_random_uuid(),

  bank_name text not null,
  account_number text not null,
  account_holder text not null,

  -- Sebutan pendek untuk dibaca orang: "BCA Operasional", "Mandiri
  -- Cabang Dua". Nomor rekening tidak pernah dihafal siapa pun, dan
  -- daftar berisi empat nomor tanpa nama menuntut yang memilihnya
  -- membaca digit satu per satu.
  label text,

  active boolean not null default true,

  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Satu rekening tercatat sekali. Nomor yang sama di bank yang sama
-- adalah rekening yang sama, dan dua barisnya berarti dua tempat
-- menautkan mutasi yang sebenarnya satu.
create unique index if not exists bank_accounts_unik
  on bank_accounts (lower(bank_name), account_number);

-- ─────────────────────────────────────────────────────────────────────
-- 2. Resto mana memakai rekening mana
-- ─────────────────────────────────────────────────────────────────────
--
-- Banyak-ke-banyak, dan itu intinya: satu rekening dipakai beberapa
-- cabang, dan satu cabang boleh punya lebih dari satu rekening —
-- misalnya satu untuk setoran tunai, satu lagi untuk transfer pelanggan.
create table if not exists resto_bank_accounts (
  resto_id text not null references restaurants (id) on delete cascade,
  bank_account_id uuid not null references bank_accounts (id) on delete cascade,

  -- Rekening yang dipakai kalau tidak disebut yang mana: tujuan setoran
  -- tunai, dan yang ditampilkan di layar Transfer pelanggan.
  --
  -- Tepat satu per resto. Tanpa batas ini, "rekening utama" jadi
  -- pertanyaan yang jawabannya bergantung urutan baris.
  is_primary boolean not null default false,

  created_at timestamptz not null default now(),
  primary key (resto_id, bank_account_id)
);

create unique index if not exists resto_bank_accounts_satu_utama
  on resto_bank_accounts (resto_id)
  where is_primary;

create index if not exists resto_bank_accounts_rekening_idx
  on resto_bank_accounts (bank_account_id);

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Siapa boleh melihat dan mengubah
-- ─────────────────────────────────────────────────────────────────────
--
-- Sebuah rekening terlihat oleh karyawan resto mana pun yang memakainya.
-- Itu konsekuensi berbagi, dan perlu disadari: Owner cabang A bisa
-- menyunting rekening yang juga dipakai cabang B. Selama keduanya milik
-- perusahaan yang sama — dan memang itu alasan rekeningnya dibagi — itu
-- yang diinginkan. Kalau suatu saat dua perusahaan berbeda berbagi satu
-- rekening, batas ini tidak lagi cukup.

begin;

alter table bank_accounts enable row level security;
alter table resto_bank_accounts enable row level security;

create or replace function _rekening_milik_saya(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from resto_bank_accounts rb
    where rb.bank_account_id = p_id
      and is_resto_employee(rb.resto_id,
            array['owner', 'finance', 'admin', 'kasir'])
  );
$$;

drop policy if exists "bank_accounts: staff read" on bank_accounts;
create policy "bank_accounts: staff read" on bank_accounts
  for select using (is_super_admin() or _rekening_milik_saya(id));

-- Ditulis Owner dan Finance saja. Kasir memakai rekeningnya sebagai
-- tujuan setoran; mengubah nomornya berarti mengubah ke mana uang laci
-- pergi, dan itu bukan keputusan yang dibuat sambil melayani antrean.
drop policy if exists "bank_accounts: finance write" on bank_accounts;
create policy "bank_accounts: finance write" on bank_accounts
  for all using (
    is_super_admin()
    or exists (
      select 1 from resto_bank_accounts rb
      where rb.bank_account_id = bank_accounts.id
        and is_resto_employee(rb.resto_id, array['owner', 'finance'])
    )
  ) with check (
    is_super_admin()
    or exists (
      select 1 from resto_bank_accounts rb
      where rb.bank_account_id = bank_accounts.id
        and is_resto_employee(rb.resto_id, array['owner', 'finance'])
    )
  );

drop policy if exists "resto_bank_accounts: staff read" on resto_bank_accounts;
create policy "resto_bank_accounts: staff read" on resto_bank_accounts
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id,
         array['owner', 'finance', 'admin', 'kasir'])
  );

drop policy if exists "resto_bank_accounts: finance write" on resto_bank_accounts;
create policy "resto_bank_accounts: finance write" on resto_bank_accounts
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Memindahkan rekening yang sudah ada
-- ─────────────────────────────────────────────────────────────────────
--
-- Tiap resto yang sudah mengisi rekeningnya di `settings` mendapat baris
-- di `bank_accounts`, dan ditandai sebagai rekening utamanya.
--
-- Resto berbeda yang kebetulan mengisi nomor yang sama akan berbagi satu
-- baris — dan itu justru yang diinginkan, karena memang satu rekening.
--
-- Kolom lama di `settings` TIDAK dihapus. Aplikasi versi lama membacanya
-- dan tidak tahu apa-apa tentang tabel ini; mengosongkannya hari ini
-- membuat layar Transfer mereka berhenti menyebutkan rekening mana pun.
-- Perintah pengosongannya ditulis di bawah, untuk dijalankan nanti.

begin;

with sumber as (
  select s.resto_id,
         btrim(s.bank_name) as bank_name,
         btrim(s.account_number) as account_number,
         btrim(coalesce(nullif(btrim(s.account_holder), ''), 'a.n. -'))
           as account_holder
  from settings s
  where btrim(coalesce(s.bank_name, '')) <> ''
    and btrim(coalesce(s.account_number, '')) <> ''
),
dibuat as (
  insert into bank_accounts (bank_name, account_number, account_holder, label)
  select distinct on (lower(bank_name), account_number)
         bank_name, account_number, account_holder, bank_name
  from sumber
  on conflict (lower(bank_name), account_number) do nothing
  returning id, bank_name, account_number
)
insert into resto_bank_accounts (resto_id, bank_account_id, is_primary)
select s.resto_id, b.id, true
from sumber s
join bank_accounts b
  on lower(b.bank_name) = lower(s.bank_name)
 and b.account_number = s.account_number
on conflict (resto_id, bank_account_id) do nothing;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Sesudah versi barunya tersebar
-- ─────────────────────────────────────────────────────────────────────
--
-- Jalankan HANYA setelah aplikasi versi baru terpasang di semua
-- perangkat. Sebelum itu, kolom lamanya masih jadi satu-satunya yang
-- dibaca versi lama.
--
-- Periksa dulu bahwa tiap resto yang punya rekening sudah punya
-- tautannya; angkanya harus nol:
--
--   select count(*) from settings s
--    where btrim(coalesce(s.bank_name, '')) <> ''
--      and not exists (select 1 from resto_bank_accounts rb
--                       where rb.resto_id = s.resto_id);
--
-- Baru sesudah itu:
--
--   update settings set bank_name = '', account_number = '',
--          account_holder = '';
