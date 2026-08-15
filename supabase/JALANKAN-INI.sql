-- ═══════════════════════════════════════════════════════════════════
-- KaataGo — seluruh migrasi yang tertunda, dalam satu berkas.
--
-- DIHASILKAN OLEH scripts/gabung_sql.sh — jangan disunting di sini.
-- Suntingannya akan hilang saat berkas ini dibuat ulang; sunting berkas
-- aslinya di supabase/ lalu jalankan skripnya lagi.
--
-- Cara pakai: salin seluruh isinya ke SQL Editor Supabase, jalankan.
-- Aman dijalankan berulang kali.
--
-- Tiap bagian punya begin/commit sendiri. Artinya kalau ada satu bagian
-- yang gagal, bagian sebelumnya tetap tersimpan — yang perlu diulang
-- hanya bagian yang gagal itu dan sesudahnya. Perhatikan pesan galat
-- Supabase: nomor bagiannya tertulis di komentar pemisah di bawah.
-- ═══════════════════════════════════════════════════════════════════



-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 1 dari 7 — employee_surrogate_key.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — email karyawan jadi bisa diubah.
--
-- Jalankan SETELAH owner_multi_resto.sql. Aman dijalankan berulang kali.
--
-- Selama ini baris karyawan dikenali dari emailnya sendiri, jadi
-- mengubah email berarti mengubah identitas barisnya — yang bukan
-- "mengubah", melainkan membuat orang baru dan meninggalkan yang lama.
-- Karena itu kolomnya dikunci di layar admin.
--
-- Sekarang barisnya punya id sendiri yang tidak berarti apa-apa selain
-- "baris ini". Email kembali menjadi data biasa: boleh salah ketik saat
-- didaftarkan, boleh diperbaiki nanti, tanpa kehilangan riwayat apa pun
-- yang menempel pada baris itu.

begin;

-- Kolom baru terisi otomatis untuk baris yang sudah ada, karena
-- defaultnya dihitung per baris saat kolomnya ditambahkan.
alter table employees add column if not exists id uuid not null default gen_random_uuid();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'employees'::regclass and contype = 'p'
  ) then
    alter table employees add constraint employees_pkey primary key (id);
  end if;
end $$;

-- Pasangan (email, resto_id) tetap unik: satu orang tetap tidak boleh
-- terdaftar dua kali di resto yang sama. Yang berubah hanya soal apa
-- yang menjadi identitas barisnya.
do $$
begin
  begin
    create unique index if not exists employees_email_resto_uidx
      on employees (email, resto_id) nulls not distinct;
  exception when syntax_error or feature_not_supported then
    create unique index if not exists employees_email_resto_uidx
      on employees (email, resto_id);
  end;
end $$;

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 2 dari 7 — promo_banner.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — banner promo per resto.
--
-- Jalankan kapan saja setelah schema.sql. Aman dijalankan berulang kali.
--
-- Bannernya milik resto, bukan milik KaataGo: tiap resto memasang
-- promonya sendiri, dan customer hanya melihat banner resto yang sedang
-- dia buka.

begin;

create table if not exists promo_banners (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants(id),

  -- Gambar disimpan langsung sebagai base64 di barisnya, sama seperti
  -- logo resto dan foto produk. Tidak ada storage bucket baru yang perlu
  -- disiapkan dan dijaga izinnya — dan banner jumlahnya sedikit, tidak
  -- seperti foto struk yang tumbuh tiap hari.
  image_base64 text not null,

  title text,
  description text,

  -- Nonaktif berarti disimpan tapi tidak ditampilkan. Promo musiman
  -- biasanya kembali dipakai tahun depan, jadi menghapusnya berarti
  -- mengunggah ulang gambar yang sama.
  active boolean not null default true,

  -- Urutan tampil. Promo utama harus bisa ditaruh di depan tanpa
  -- menghapus dan mengunggah ulang yang lain.
  sort_order integer not null default 0,

  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists idx_promo_banners_resto
  on promo_banners(resto_id, active, sort_order);

alter table promo_banners enable row level security;

-- Dibaca siapa saja, termasuk tamu: banner promo justru ditujukan untuk
-- orang yang belum punya akun.
drop policy if exists "promo_banners: public read" on promo_banners;
create policy "promo_banners: public read" on promo_banners
  for select using (true);

-- Yang mengelola hanya admin restonya sendiri (dan owner, yang lolos
-- setiap pemeriksaan peran lewat is_resto_employee), atau super_admin.
drop policy if exists "promo_banners: admin manage" on promo_banners;
create policy "promo_banners: admin manage" on promo_banners
  for all
  using (is_super_admin() or is_resto_employee(resto_id, array['admin']))
  with check (is_super_admin() or is_resto_employee(resto_id, array['admin']));

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 3 dari 7 — rilis_setor_petty_inbox.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — setoran & top up petty cash berjenjang, GL Suspense, dan
-- kotak masuk pengumuman.
--
-- SATU file untuk seluruh rilis ini; menggantikan deposit_approval.sql
-- dan inbox_and_petty_approval.sql yang sebelumnya terpisah. Aman
-- dijalankan berulang kali.
--
-- Alurnya:
--   Kasir/Admin mencatat  → status 'pending', uang ditampung di GL
--                           Suspense (setoran dan petty cash punya
--                           akun suspense masing-masing).
--   Finance mengonfirmasi → dipindah dari suspense ke akun tujuannya.
--   Finance menolak       → dikembalikan ke akun asalnya.
--
-- Mengonfirmasi hanya milik Finance (dan Owner, yang lolos setiap
-- pemeriksaan peran). Admin disamakan dengan kasir: keduanya mengajukan,
-- bukan memutuskan — persetujuan atas permintaan sendiri tidak berarti
-- apa-apa.

-- ARAH JURNAL. Aplikasi ini memakai satu kesepakatan di seluruh
-- layarnya: **kredit = uang masuk ke akun itu, debit = uang keluar**.
-- Penjualan mengkredit akun pemasukan, dan panah di layar Jurnal GL
-- mengikuti aturan yang sama.
--
-- Kesepakatan akuntansi aset yang biasa (aset bertambah = debit) adalah
-- kebalikannya, dan sempat terpakai di sini — akibatnya setoran tunai
-- menambah sisi yang sama dengan penjualan alih-alih menguranginya, dan
-- di layar terbaca seolah GL Suspense yang mengeluarkan uang.

begin;


-- ── 1. Status persetujuan ────────────────────────────────────────────
alter table cash_deposits add column if not exists status text not null default 'pending';
alter table cash_deposits add column if not exists reviewed_by text;
alter table cash_deposits add column if not exists reviewed_at timestamptz;
alter table cash_deposits add column if not exists review_note text;

alter table cash_deposits drop constraint if exists cash_deposits_status_check;
alter table cash_deposits add constraint cash_deposits_status_check
  check (status in ('pending', 'approved', 'rejected'));

-- Setoran yang sudah terlanjur tercatat sebelum alur ini ada memang sudah
-- masuk GL Total Saldo, jadi statusnya disamakan dengan 'approved' —
-- menandainya 'pending' akan meminta Finance menyetujui sesuatu yang
-- uangnya sudah lama diakui.
update cash_deposits set status = 'approved' where status = 'pending' and created_at < now() - interval '1 second';

create index if not exists idx_cash_deposits_status on cash_deposits(resto_id, status);

-- ── 2. GL Suspense ───────────────────────────────────────────────────
-- Batasan payment_method dipasang sekali saja, di bagian GL Suspense
-- Petty Cash di bawah — daftarnya sudah memuat 'suspense' sekaligus
-- 'suspense_petty'. Memasang daftar yang lebih pendek lebih dulu membuat
-- file ini menolak dirinya sendiri saat dijalankan ulang, karena baris
-- 'suspense_petty' yang dibuatnya sudah ada.

-- ── 3. Jurnal saat setoran diajukan ──────────────────────────────────
-- Uang meninggalkan laci, tapi berhenti dulu di Suspense.
create or replace function log_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_gl record;
  v_suspense_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  select * into v_cash_gl from _gl_account_for(new.resto_id, 'cash');
  if v_cash_gl.gl_code is not null and v_cash_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_cash_gl.gl_code, v_cash_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Setor tunai #' || v_ref || ' (menunggu approval)'
    );
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', 'Titipan setoran #' || v_ref
    );
  end if;

  return new;
end;
$$;

-- ── 4. Jurnal saat disetujui / ditolak ───────────────────────────────
-- Dipicu oleh perubahan status, dan hanya untuk baris yang berubah, jadi
-- setoran lain yang masih menunggu tidak ikut terbawa.
create or replace function log_cash_deposit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suspense_gl record;
  v_target_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit', 'Titipan setoran #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    v_target := 'total_balance';
    v_note := 'Setoran #' || v_ref || ' disetujui';
  else
    -- Ditolak: uangnya kembali menjadi tanggung jawab laci kasir.
    v_target := 'cash';
    v_note := 'Setoran #' || v_ref || ' ditolak, kembali ke kas';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', v_note
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_cash_deposit_review on cash_deposits;
create trigger trg_log_cash_deposit_review
  after update of status on cash_deposits
  for each row execute function log_cash_deposit_review();

-- ── 5. Hanya Finance/Admin/Owner yang boleh menyetujui ───────────────
-- Kasir dan Admin tetap boleh menambah setoran, tapi tidak boleh
-- mengubah statusnya sendiri. Owner ikut lolos lewat klausa 'owner' di
-- dalam is_resto_employee.
drop policy if exists "cash_deposits: finance review" on cash_deposits;
create policy "cash_deposits: finance review" on cash_deposits
  for update
  using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));


-- ─────────────────────────────────────────────────────────────────────
-- 1. Rekening tujuan pada setoran tunai
-- ─────────────────────────────────────────────────────────────────────
-- Tanpa ini, "sudah disetor" tidak menyebut ke mana. Saat Finance
-- memeriksa mutasi bank, tidak ada yang bisa dicocokkan selain nominal.
alter table cash_deposits add column if not exists bank_name text;
alter table cash_deposits add column if not exists account_number text;
alter table cash_deposits add column if not exists account_holder text;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Approval top up petty cash
-- ─────────────────────────────────────────────────────────────────────
-- Kasir kini boleh mengajukan top up, tapi uangnya belum diakui masuk
-- petty cash sampai Finance menyetujui. Selama menunggu, nilainya
-- ditampung di GL Suspense Petty Cash — sengaja terpisah dari suspense
-- setoran bank, supaya Finance bisa melihat berapa yang tertahan pada
-- masing-masing alur tanpa harus memilahnya satu per satu.
alter table petty_cash_entries add column if not exists status text not null default 'approved';
alter table petty_cash_entries add column if not exists requested_by text;
alter table petty_cash_entries add column if not exists reviewed_by text;
alter table petty_cash_entries add column if not exists reviewed_at timestamptz;
alter table petty_cash_entries add column if not exists review_note text;

alter table petty_cash_entries drop constraint if exists petty_cash_entries_status_check;
alter table petty_cash_entries add constraint petty_cash_entries_status_check
  check (status in ('pending', 'approved', 'rejected'));

-- Baris lama dibuat oleh Finance sendiri, jadi memang sudah setara
-- disetujui — default kolomnya 'approved' supaya riwayat tidak
-- tiba-tiba minta persetujuan ulang.
create index if not exists idx_petty_cash_status on petty_cash_entries(resto_id, status);

-- Kasir boleh mengajukan dan melihat, tapi tidak boleh menyetujui —
-- persetujuan atas permintaannya sendiri tidak berarti apa-apa.
drop policy if exists "petty_cash_entries: kasir request" on petty_cash_entries;
create policy "petty_cash_entries: kasir request" on petty_cash_entries
  for insert with check (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

drop policy if exists "petty_cash_entries: staff read" on petty_cash_entries;
create policy "petty_cash_entries: staff read" on petty_cash_entries
  for select using (is_resto_employee(resto_id, array['admin', 'finance', 'kasir']));

-- ─────────────────────────────────────────────────────────────────────
-- 3. GL Suspense Petty Cash
-- ─────────────────────────────────────────────────────────────────────
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty'));

-- ─────────────────────────────────────────────────────────────────────
-- 4. Jurnal petty cash mengikuti statusnya
-- ─────────────────────────────────────────────────────────────────────
-- Saat diajukan: sumbernya berkurang, nilainya mengendap di Suspense
-- Petty Cash. Saat disetujui: berpindah dari suspense ke petty cash.
-- Saat ditolak: dikembalikan ke sumbernya semula.
create or replace function log_petty_cash_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petty_gl record;
  v_source_gl record;
  v_suspense_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_label text;
begin
  v_label := case new.source
    when 'cash_withdrawal' then 'Saldo Cash'
    when 'income_withdrawal' then 'Saldo Non Cash'
    else null
  end;

  -- Sumbernya berkurang begitu diajukan, apa pun statusnya: uangnya
  -- memang sudah diambil dari sana. Top up manual adalah modal dari
  -- luar, jadi tidak punya lawan akun.
  if v_label is not null then
    select * into v_source_gl from _gl_account_for(
      new.resto_id,
      case when new.source = 'cash_withdrawal' then 'cash' else 'income_aggregate' end
    );
    if v_source_gl.gl_code is not null and v_source_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_source_gl.gl_code, v_source_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'debit', 'Dipindah ke Petty Cash #' || v_ref
      );
    end if;
  end if;

  if new.status = 'pending' then
    -- Menunggu persetujuan: berhenti dulu di suspense.
    select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense_petty');
    if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit', 'Titipan top up petty cash #' || v_ref
      );
    end if;
  else
    -- Dibuat langsung oleh Finance: tidak perlu singgah di suspense.
    select * into v_petty_gl from _gl_account_for(new.resto_id, 'petty_cash');
    if v_petty_gl.gl_code is not null and v_petty_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_petty_gl.gl_code, v_petty_gl.gl_name, 'petty_cash', new.id::text,
        new.amount, 'credit',
        coalesce('Top Up Petty Cash dari ' || v_label, 'Top Up Petty Cash (Manual)')
      );
    end if;
  end if;

  return new;
end;
$$;

create or replace function log_petty_cash_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suspense_gl record;
  v_target_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  select * into v_suspense_gl from _gl_account_for(new.resto_id, 'suspense_petty');
  if v_suspense_gl.gl_code is not null and v_suspense_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_suspense_gl.gl_code, v_suspense_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'debit', 'Titipan top up #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    v_target := 'petty_cash';
    v_note := 'Top up petty cash #' || v_ref || ' disetujui';
  else
    -- Ditolak: uangnya kembali ke sumber asalnya.
    v_target := case when new.source = 'cash_withdrawal' then 'cash' else 'income_aggregate' end;
    v_note := 'Top up petty cash #' || v_ref || ' ditolak';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'petty_cash', new.id::text,
      new.amount, 'credit', v_note
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_petty_cash_review on petty_cash_entries;
create trigger trg_log_petty_cash_review
  after update of status on petty_cash_entries
  for each row execute function log_petty_cash_review();

drop policy if exists "petty_cash_entries: finance review" on petty_cash_entries;
create policy "petty_cash_entries: finance review" on petty_cash_entries
  for update
  using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));

-- ─────────────────────────────────────────────────────────────────────
-- 5. Inbox pengumuman
-- ─────────────────────────────────────────────────────────────────────
-- Pengumumannya disimpan sekali, bukan disalin ke tiap penerima. Menyalin
-- berarti orang yang mendaftar besok tidak akan pernah melihat
-- pengumuman hari ini, dan setiap blast menambah ribuan baris kembar.
-- Yang per orang hanyalah keadaannya: sudah dibaca, atau sudah dihapus.
create table if not exists app_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  -- Versi aplikasi yang diumumkan. Dipakai layar tamu untuk tahu apakah
  -- aplikasinya sudah usang, tanpa perlu punya akun.
  version text,
  download_url text,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists idx_announcements_created on app_announcements(created_at desc);

alter table app_announcements enable row level security;

-- Boleh dibaca siapa saja, termasuk tamu: pemberitahuan versi baru justru
-- paling dibutuhkan orang yang belum punya akun.
drop policy if exists "announcements: public read" on app_announcements;
create policy "announcements: public read" on app_announcements
  for select using (true);

drop policy if exists "announcements: super_admin write" on app_announcements;
create policy "announcements: super_admin write" on app_announcements
  for all using (is_super_admin()) with check (is_super_admin());

create table if not exists inbox_states (
  email text not null,
  announcement_id uuid not null references app_announcements(id) on delete cascade,
  read_at timestamptz,
  deleted_at timestamptz,
  primary key (email, announcement_id)
);

alter table inbox_states enable row level security;

-- Setiap orang hanya menyentuh barisnya sendiri. Inbox milik orang lain
-- bukan urusan siapa pun, termasuk admin.
drop policy if exists "inbox_states: own rows" on inbox_states;
create policy "inbox_states: own rows" on inbox_states
  for all
  using (email = auth.jwt()->>'email')
  with check (email = auth.jwt()->>'email');

-- ─────────────────────────────────────────────────────────────────────
-- 6. Titik lokasi resto
-- ─────────────────────────────────────────────────────────────────────
-- Alamat berupa teks cukup untuk dicetak di struk, tapi tidak cukup
-- untuk mengantar orang ke sana. Koordinatnya disimpan terpisah supaya
-- alamat tetap bisa disunting sedetail yang dibutuhkan ("ruko blok C
-- no. 4") tanpa merusak titik petanya.
alter table restaurants add column if not exists latitude double precision;
alter table restaurants add column if not exists longitude double precision;

-- ─────────────────────────────────────────────────────────────────────
-- 7. Membetulkan baris jurnal yang terlanjur terbalik
-- ─────────────────────────────────────────────────────────────────────
-- Setoran dan top up petty cash yang sudah tercatat sebelum perbaikan di
-- atas memakai arah yang salah. Barisnya tidak dihapus — riwayat jurnal
-- tidak boleh hilang — hanya arahnya yang dibalik.
--
-- Dijaga supaya hanya berjalan sekali. Menjalankannya dua kali akan
-- mengembalikan keadaan yang justru sedang diperbaiki, dan file ini
-- memang dirancang untuk boleh dijalankan berulang kali.
create table if not exists applied_migrations (
  name text primary key,
  applied_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from applied_migrations where name = 'flip_transfer_journal_direction') then
    update gl_journal_entries
       set entry_type = case entry_type when 'debit' then 'credit' else 'debit' end
     where reference_type in ('cash_deposit', 'petty_cash');

    insert into applied_migrations (name) values ('flip_transfer_journal_direction');
  end if;
end $$;


commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 4 dari 7 — customer_cash_payment.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pelanggan boleh memilih bayar tunai di kasir.
--
-- Jalankan SETELAH orders_gl_code.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang pesanan mandiri dari HP pelanggan selalu QRIS, dan itu
-- dianggap benar di banyak tempat sekaligus. Yang berubah di sini cuma
-- satu: kalau pesanannya sudah menyebut cara bayarnya sendiri, sebutan
-- itu yang dipakai — bukan diganti QRIS karena kebetulan datang dari
-- pelanggan.

begin;

-- Uang yang diserahkan pelanggan di meja kasir.
--
-- Kembaliannya tidak ikut disimpan: itu selalu bisa dihitung ulang dari
-- uang yang diterima dikurangi totalnya, dan menyimpan dua angka yang
-- saling terikat berarti membuka peluang keduanya tidak lagi cocok.
alter table orders add column if not exists cash_received bigint;

-- Sebelumnya: pesanan mana pun dari pelanggan langsung dipetakan ke
-- 'qris' tanpa melihat apa pun. Akibatnya pesanan tunai akan tercatat
-- masuk ke GL QRIS — uangnya benar jumlahnya, tapi salah kantong, dan
-- Finance baru sadar saat mencocokkan mutasi QRIS yang tidak pernah ada.
--
-- Baris pelanggan lama tidak pernah mengisi payment_method, jadi
-- pemetaan lamanya tetap berlaku persis untuk mereka.
create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_payment_method in ('cash', 'qris', 'transfer') then p_payment_method
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    when p_payment_method = 'Tunai' then 'cash'
    when p_source = 'customer' then 'qris'
    else 'cash'
  end;
$$;

-- Setoran dan top up ikut disiarkan realtime.
--
-- Tanpa ini, kasir baru tahu pengajuannya disetujui kalau kebetulan
-- membuka layarnya lagi — padahal justru itu yang bikin orang tidak
-- membukanya: tidak ada yang memberi tahu ada yang perlu dilihat.
do $$
begin
  alter publication supabase_realtime add table cash_deposits;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table petty_cash_entries;
exception when duplicate_object then null;
end $$;

-- Pesanan tunai pelanggan diselesaikan kasir lewat UPDATE biasa —
-- kebijakan "orders: employees update" sudah mengizinkannya, dan RPC
-- mark_order_paid memang khusus untuk tamu yang tidak punya sesi login.
-- Tidak ada yang perlu ditambahkan di sini.

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 5 dari 7 — push_notifications.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — notifikasi yang tetap sampai walau aplikasinya tertutup.
--
-- Jalankan SETELAH customer_cash_payment.sql. Aman dijalankan berulang
-- kali.
--
-- Notifikasi yang sudah ada dibangkitkan aplikasinya sendiri dari aliran
-- realtime, dan itu hanya hidup selama prosesnya hidup. Berkas ini
-- menyiapkan sisi servernya: daftar perangkat yang boleh diketuk, dan
-- pemicu yang memberi tahu Edge Function bahwa ada yang perlu
-- dikabarkan.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Daftar perangkat
-- ─────────────────────────────────────────────────────────────────────

-- Satu baris per perangkat, bukan per orang: satu orang bisa memegang HP
-- dan tablet sekaligus, dan satu HP bisa berpindah tangan antar shift.
-- Tokennya sendiri yang jadi kunci — itu satu-satunya hal yang benar-
-- benar mewakili "tempat notifikasi ini akan mendarat".
create table if not exists device_tokens (
  token text primary key,

  -- Siapa yang sedang memakainya. Semuanya boleh kosong: pelanggan tamu
  -- tidak punya email, dan perangkat yang belum memilih resto belum
  -- terikat ke mana pun.
  email text,
  resto_id text references restaurants (id) on delete cascade,
  role text,

  -- Pengenal pelanggan tamu. Tamu adalah sebagian besar pelanggan resto;
  -- tanpa kolom ini fitur ini hanya bekerja untuk yang paling jarang
  -- membutuhkannya.
  session_id text,

  platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_resto_role_idx
  on device_tokens (resto_id, role);
create index if not exists device_tokens_email_idx on device_tokens (email);
create index if not exists device_tokens_session_idx on device_tokens (session_id);

alter table device_tokens enable row level security;

-- Siapa pun boleh mendaftarkan tokennya sendiri, termasuk tamu yang
-- tidak punya sesi login sama sekali — sama seperti kebijakan `orders`,
-- yang memang harus menerima pesanan dari orang tanpa akun.
--
-- Yang dijaga bukan siapa yang boleh menulis, tapi siapa yang boleh
-- membaca: daftar token adalah daftar "ke mana notifikasi bisa
-- dikirim", dan itu tidak boleh bisa dibaca dari aplikasi sama sekali.
-- Edge Function membacanya dengan service role, yang melewati RLS.
drop policy if exists "device_tokens: public upsert" on device_tokens;
create policy "device_tokens: public upsert" on device_tokens
  for insert with check (true);

drop policy if exists "device_tokens: update own" on device_tokens;
create policy "device_tokens: update own" on device_tokens
  for update using (true) with check (true);

drop policy if exists "device_tokens: delete own" on device_tokens;
create policy "device_tokens: delete own" on device_tokens
  for delete using (true);

-- Sengaja tidak ada kebijakan select untuk peran mana pun.

-- ─────────────────────────────────────────────────────────────────────
-- 2. Antrean kabar
-- ─────────────────────────────────────────────────────────────────────

-- Kejadian ditulis ke tabel dulu, baru dikirim.
--
-- Memanggil FCM langsung dari trigger berarti transaksi database
-- menunggu jaringan pihak lain: FCM lambat sedetik, dan kasir menunggu
-- sedetik itu sebelum pesanannya tersimpan. Lebih buruk lagi, FCM
-- gagal berarti seluruh transaksinya batal — pesanan yang sah hilang
-- gara-gara notifikasinya tidak terkirim.
--
-- Dengan antrean, kejadiannya tercatat dulu dan dikirim menyusul. Yang
-- gagal terkirim tetap tercatat di sini berikut galatnya, jadi
-- "notifikasinya tidak sampai" berhenti jadi tebakan.
create table if not exists push_outbox (
  id uuid primary key default gen_random_uuid(),
  resto_id text,
  event text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  error text,
  attempts int not null default 0
);

create index if not exists push_outbox_pending_idx
  on push_outbox (created_at) where sent_at is null;

alter table push_outbox enable row level security;
-- Tidak ada kebijakan apa pun: hanya trigger dan service role yang
-- menyentuhnya.

-- ─────────────────────────────────────────────────────────────────────
-- 3. Pemicu — pesanan
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_push_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_where text;
begin
  v_where := case
    when new.table_number is not null and new.table_number <> ''
      then 'Meja ' || new.table_number
    when coalesce(new.customer_name, '') <> ''
      then 'Take Away · ' || new.customer_name
    else 'Take Away'
  end;

  -- Pesanan baru → dapur.
  if tg_op = 'INSERT' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'order_new',
      jsonb_build_object(
        'audience', 'role', 'roles', array['chef'],
        'title', 'Pesanan baru masuk',
        'body', v_where || ' · #' || v_ref
      )
    );
    return new;
  end if;

  -- Dapur bergerak → pelanggannya, dan kasir yang menginput.
  if new.kitchen_status is distinct from old.kitchen_status then
    if new.kitchen_status = 'onProgress' then
      insert into push_outbox (resto_id, event, payload) values (
        new.resto_id, 'order_cooking',
        jsonb_build_object(
          'audience', 'order_owner',
          'email', new.customer_label,
          'session_id', new.session_id,
          'title', 'Pesanan kamu lagi dimasak 👨‍🍳',
          'body', 'Dapur sudah mulai. Tunggu sebentar ya — #' || v_ref
        )
      );
    elsif new.kitchen_status = 'done' then
      insert into push_outbox (resto_id, event, payload) values (
        new.resto_id, 'order_ready',
        jsonb_build_object(
          'audience', 'order_owner',
          'email', new.customer_label,
          'session_id', new.session_id,
          'title', 'Pesanan kamu siap! 🎉',
          'body', 'Selamat menikmati — #' || v_ref
        )
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_queue_push_order_insert on orders;
create trigger trg_queue_push_order_insert
  after insert on orders
  for each row execute function queue_push_order();

drop trigger if exists trg_queue_push_order_update on orders;
create trigger trg_queue_push_order_update
  after update on orders
  for each row execute function queue_push_order();

-- Pesanan tunai dari HP pelanggan yang menunggu dibayar — kasir, admin,
-- dan owner perlu tahu ada orang berdiri di depan kasir.
create or replace function queue_push_pending_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source = 'customer'
     and new.payment_status = 'pending'
     and new.payment_method = 'cash' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'pending_payment',
      jsonb_build_object(
        'audience', 'role', 'roles', array['kasir', 'admin', 'owner'],
        'title', 'Pesanan menunggu dibayar',
        'body', 'Pelanggan memilih bayar tunai di kasir — #'
                || upper(substr(new.id::text, 1, 8))
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_pending_payment on orders;
create trigger trg_queue_push_pending_payment
  after insert on orders
  for each row execute function queue_push_pending_payment();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Pemicu — setoran & petty cash
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_push_deposit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount text := 'Rp ' || to_char(new.amount, 'FM999G999G999');
begin
  -- Pengajuan baru → yang memutuskan.
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'deposit_pending',
      jsonb_build_object(
        'audience', 'role', 'roles', array['finance', 'owner'],
        'title', 'Setoran tunai menunggu konfirmasi',
        'body', v_amount || ' dari ' || coalesce(new.created_by, 'kasir')
      )
    );
    return new;
  end if;

  -- Sudah diputus → yang mengajukan.
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'deposit_reviewed',
      jsonb_build_object(
        'audience', 'email', 'email', new.created_by,
        'title', case new.status
                   when 'approved' then 'Setoran tunai dikonfirmasi ✅'
                   else 'Setoran tunai ditolak' end,
        'body', case new.status
                  when 'approved' then v_amount || ' sudah masuk rekening resto.'
                  else v_amount || ' dikembalikan ke Saldo Cash'
                       || coalesce(' — ' || nullif(trim(new.review_note), ''), '.')
                end
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_deposit_insert on cash_deposits;
create trigger trg_queue_push_deposit_insert
  after insert on cash_deposits
  for each row execute function queue_push_deposit();

drop trigger if exists trg_queue_push_deposit_update on cash_deposits;
create trigger trg_queue_push_deposit_update
  after update of status on cash_deposits
  for each row execute function queue_push_deposit();

create or replace function queue_push_petty()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount text := 'Rp ' || to_char(new.amount, 'FM999G999G999');
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'petty_pending',
      jsonb_build_object(
        'audience', 'role', 'roles', array['finance', 'owner'],
        'title', 'Top up petty cash menunggu persetujuan',
        'body', v_amount || ' dari ' || coalesce(new.created_by, 'kasir')
      )
    );
    return new;
  end if;

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'petty_reviewed',
      jsonb_build_object(
        'audience', 'email', 'email', new.created_by,
        'title', case new.status
                   when 'approved' then 'Top up petty cash disetujui ✅'
                   else 'Top up petty cash ditolak' end,
        'body', case new.status
                  when 'approved' then v_amount || ' sudah masuk saldo petty cash.'
                  else v_amount || ' tidak jadi ditambahkan'
                       || coalesce(' — ' || nullif(trim(new.review_note), ''), '.')
                end
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_petty_insert on petty_cash_entries;
create trigger trg_queue_push_petty_insert
  after insert on petty_cash_entries
  for each row execute function queue_push_petty();

drop trigger if exists trg_queue_push_petty_update on petty_cash_entries;
create trigger trg_queue_push_petty_update
  after update of status on petty_cash_entries
  for each row execute function queue_push_petty();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Langkah berikutnya, di luar berkas ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Deploy Edge Function-nya:
--        supabase functions deploy send-push --project-ref xizpwtycczigjhzxegen
--
-- 2. Pasang Database Webhook di Dashboard → Database → Webhooks:
--        tabel  : push_outbox
--        event  : Insert
--        tipe   : Supabase Edge Function → send-push
--
--    Webhook dipilih, bukan pg_net di dalam trigger, supaya kegagalan
--    jaringan tidak pernah bisa membatalkan transaksi yang menulis
--    pesanannya.
--
-- 3. Periksa hasilnya kapan pun:
--        select event, created_at, sent_at, error, attempts
--        from push_outbox order by created_at desc limit 20;
--
--    Baris ber-sent_at berarti benar-benar terkirim. Yang ber-error
--    menyebutkan sebabnya. Tidak perlu menebak lagi.


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 6 dari 7 — announcement_categories.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pengumuman dibagi dua jenis, dan admin resto boleh mengirim.
--
-- Jalankan SETELAH rilis_setor_petty_inbox.sql. Aman dijalankan
-- berulang kali.
--
-- Sampai sekarang kotak masuk cuma berisi satu jenis pesan: pemberitahuan
-- versi baru, dan hanya Super Admin yang boleh mengirimnya. Dua hal
-- berubah di sini — pengumuman punya jenis, dan pengumuman umum boleh
-- diterbitkan admin resto untuk restonya sendiri.

begin;

-- 'update' = pemberitahuan versi baru, 'general' = pengumuman biasa
-- termasuk promo. Baris lama semuanya pemberitahuan versi, jadi
-- defaultnya itu — dan karena kolomnya baru, seluruh baris lama terisi
-- benar tanpa perlu ditebak satu-satu.
alter table app_announcements
  add column if not exists category text not null default 'update';

alter table app_announcements
  drop constraint if exists app_announcements_category_check;
alter table app_announcements
  add constraint app_announcements_category_check
  check (category in ('update', 'general'));

-- Null berarti untuk semua resto — itulah pengumuman dari Super Admin.
-- Terisi berarti hanya untuk resto itu.
alter table app_announcements
  add column if not exists resto_id text references restaurants (id) on delete cascade;

-- Gambar promo sebagai base64, sependekatan dengan banner promo dan logo
-- resto. Menyimpannya di kolom, bukan di object storage, membuat satu
-- pengumuman tetap satu baris — dan pengumuman yang gambarnya hilang
-- karena berkasnya terhapus terpisah adalah jenis kerusakan yang tidak
-- perlu diciptakan.
alter table app_announcements
  add column if not exists image_base64 text;

create index if not exists idx_announcements_category
  on app_announcements (category, created_at desc);
create index if not exists idx_announcements_resto
  on app_announcements (resto_id);

-- ─────────────────────────────────────────────────────────────────────
-- Siapa boleh menerbitkan apa
-- ─────────────────────────────────────────────────────────────────────
--
-- Super Admin: apa saja, untuk resto mana saja.
--
-- Admin dan Owner: hanya 'general', hanya untuk restonya sendiri.
-- Pemberitahuan versi sengaja tetap milik Super Admin — itu menyangkut
-- APK yang dia terbitkan, dan admin resto tidak punya cara mengetahui
-- versi mana yang sebenarnya sudah rilis.
--
-- Batasnya ditegakkan di sini, bukan hanya di aplikasi: tombol yang
-- disembunyikan cuma menghalangi orang yang memakai aplikasinya.

drop policy if exists "announcements: super_admin write" on app_announcements;
drop policy if exists "announcements: super_admin all" on app_announcements;
create policy "announcements: super_admin all" on app_announcements
  for all using (is_super_admin()) with check (is_super_admin());

drop policy if exists "announcements: resto admin general" on app_announcements;
create policy "announcements: resto admin general" on app_announcements
  for insert
  with check (
    category = 'general'
    and resto_id is not null
    and is_resto_employee(resto_id, array['admin'])
  );

-- Menghapus pengumuman sendiri: yang salah kirim harus bisa ditarik,
-- tapi hanya miliknya sendiri dan hanya yang umum.
drop policy if exists "announcements: resto admin delete own" on app_announcements;
create policy "announcements: resto admin delete own" on app_announcements
  for delete
  using (
    category = 'general'
    and resto_id is not null
    and is_resto_employee(resto_id, array['admin'])
  );

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 7 dari 7 — fix_device_tokens_rls.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pendaftaran token push lewat fungsi, bukan tulis langsung.
--
-- Jalankan SETELAH push_notifications.sql. Aman dijalankan berulang kali.
--
-- Gejalanya: aplikasi mendapat token FCM, tapi menyimpannya ditolak
-- dengan 42501 "new row violates row-level security policy for table
-- device_tokens" — padahal kebijakan INSERT-nya berbunyi `with check
-- (true)`, yang secara logika tidak mungkin gagal.
--
-- Sebabnya bukan kebijakan INSERT-nya. Pendaftarannya berupa upsert,
-- dan `insert ... on conflict do update` mengharuskan Postgres MEMBACA
-- baris yang bentrok lebih dulu — jadi butuh kebijakan SELECT. Tabel ini
-- sengaja dibuat tanpa kebijakan SELECT, karena daftar token tidak perlu
-- terbaca aplikasi. Niatnya benar, akibatnya upsert-nya mustahil lolos.
--
-- Menambahkan kebijakan SELECT akan membuka seluruh daftar token —
-- berikut email karyawan dan resto tempatnya bekerja — kepada siapa pun
-- yang punya anon key, dan kunci itu memang tertanam di dalam APK.
--
-- Jalan keluarnya membalik arah: tabelnya ditutup rapat dari aplikasi,
-- dan pendaftarannya lewat satu fungsi SECURITY DEFINER yang tugasnya
-- cuma itu. Aplikasi tidak lagi bisa membaca, mengubah, atau menghapus
-- baris mana pun — dia hanya bisa menitipkan tokennya sendiri.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tutup akses langsung
-- ─────────────────────────────────────────────────────────────────────
alter table device_tokens enable row level security;

drop policy if exists "device_tokens: public upsert" on device_tokens;
drop policy if exists "device_tokens: update own" on device_tokens;
drop policy if exists "device_tokens: delete own" on device_tokens;
drop policy if exists "device_tokens: insert" on device_tokens;
drop policy if exists "device_tokens: update" on device_tokens;
drop policy if exists "device_tokens: delete" on device_tokens;

revoke all on table device_tokens from anon, authenticated;

-- Tanpa kebijakan apa pun dan tanpa hak akses, tabel ini tidak bisa
-- disentuh dari aplikasi sama sekali. Yang menyentuhnya cuma fungsi di
-- bawah dan Edge Function (service role).

-- ─────────────────────────────────────────────────────────────────────
-- 2. Satu-satunya pintu masuk
-- ─────────────────────────────────────────────────────────────────────

create or replace function register_device_token(
  p_token text,
  p_email text default null,
  p_resto_id text default null,
  p_role text default null,
  p_session_id text default null,
  p_platform text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return;
  end if;

  insert into device_tokens (
    token, email, resto_id, role, session_id, platform, updated_at
  ) values (
    p_token, p_email, p_resto_id, p_role, p_session_id, p_platform, now()
  )
  on conflict (token) do update set
    -- Seluruh kolom ditimpa, bukan digabung. Satu HP bisa berpindah
    -- tangan antar shift, dan pemilik lama yang tertinggal di barisnya
    -- berarti kasir yang sudah logout tetap menerima kabar setoran
    -- penggantinya.
    email = excluded.email,
    resto_id = excluded.resto_id,
    role = excluded.role,
    session_id = excluded.session_id,
    platform = excluded.platform,
    updated_at = now();
end;
$$;

create or replace function unregister_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from device_tokens where token = p_token;
end;
$$;

-- Tamu memakai anon, karyawan yang login memakai authenticated —
-- keduanya harus bisa mendaftarkan perangkatnya.
grant execute on function register_device_token(text, text, text, text, text, text)
  to anon, authenticated;
grant execute on function unregister_device_token(text) to anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memastikan
-- ─────────────────────────────────────────────────────────────────────
-- Setelah berkas ini jalan, aplikasi versi 1.37.0 ke atas akan memakai
-- fungsi di atas. Buka Tes Notifikasi di HP; barisnya harus berbunyi
-- "Push aktif". Lalu:
--
--   select email, role, resto_id, platform, updated_at
--   from device_tokens order by updated_at desc;
