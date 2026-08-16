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
-- BAGIAN 1 dari 27 — employee_surrogate_key.sql
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
-- BAGIAN 2 dari 27 — promo_banner.sql
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
-- BAGIAN 3 dari 27 — rilis_setor_petty_inbox.sql
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
-- Daftarnya sengaja sama persis di semua berkas yang menyentuh batasan
-- ini, bukan hanya sepanjang yang dibutuhkan berkas ini sendiri.
--
-- Sebelumnya tiap berkas menuliskan daftar sepanjang zamannya, dan
-- itu berjalan baik tepat satu kali — saat dijalankan berurutan pada
-- database kosong. Menjalankan ulang berkas yang lebih tua sesudah
-- yang lebih baru berarti menyempitkan daftarnya lagi, dan barisan
-- akun yang terlanjur dibuat berkas yang lebih baru langsung
-- melanggarnya:
--
--   check constraint "gl_accounts_payment_method_check" is violated
--   by some row
--
-- Padahal tidak ada satu pun data yang salah. Yang salah adalah
-- batasannya yang mundur. Satu daftar untuk semua menutup itu.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount'));

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
-- BAGIAN 4 dari 27 — customer_cash_payment.sql
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
-- BAGIAN 5 dari 27 — push_notifications.sql
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
-- BAGIAN 6 dari 27 — announcement_categories.sql
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
-- BAGIAN 7 dari 27 — fix_device_tokens_rls.sql
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


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 8 dari 27 — push_trigger_pg_net.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — panggil Edge Function langsung dari database, tanpa webhook.
--
-- Jalankan SETELAH fix_device_tokens_rls.sql. Aman dijalankan berulang
-- kali.
--
-- Rencana semula memakai Database Webhook, tapi tipe "Supabase Edge
-- Function" tidak tersedia di Dashboard proyek ini. pg_net melakukan hal
-- yang sama dari sisi database, dan sebetulnya lebih sedikit bagian yang
-- bisa rusak: satu tempat yang mengatur, bukan dua.
--
-- pg_net mengirim permintaannya secara asinkron — dititipkan ke antrean,
-- bukan ditunggu. Itu penting: transaksi yang menulis pesanan tidak
-- boleh menunggu jaringan pihak lain, dan kegagalan mengirim notifikasi
-- tidak boleh membatalkan pesanan yang sah.

begin;

create extension if not exists pg_net with schema extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Alamat dan kunci pemanggilnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan di tabel, bukan ditanam di badan fungsi: kunci yang tertanam
-- di definisi fungsi ikut terbaca siapa pun yang boleh melihat skema.
-- Tabel ini tidak punya kebijakan RLS satu pun, jadi tidak bisa disentuh
-- dari aplikasi — yang membacanya cuma trigger di bawah, yang berjalan
-- sebagai pemiliknya.
create table if not exists push_config (
  id int primary key default 1,
  function_url text not null,
  secret text not null,
  constraint push_config_single_row check (id = 1)
);

alter table push_config enable row level security;
revoke all on table push_config from anon, authenticated;

insert into push_config (id, function_url, secret) values (
  1,
  'https://xizpwtycczigjhzxegen.supabase.co/functions/v1/send-push',
  'fBFcxm-9uT-rQ3ha8I29_i4Y4xm_vq3a-oE1gOFEHhM'
)
on conflict (id) do update set
  function_url = excluded.function_url,
  secret = excluded.secret;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Pemicunya
-- ─────────────────────────────────────────────────────────────────────

create or replace function notify_push_outbox()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_config push_config;
begin
  select * into v_config from push_config where id = 1;
  if v_config.function_url is null then
    return new;
  end if;

  -- Barisnya dikirim utuh dalam bentuk yang sama dengan yang dikirim
  -- Database Webhook, supaya Edge Function-nya tidak perlu tahu dari
  -- mana panggilannya datang.
  perform net.http_post(
    url := v_config.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-kaata-hook-secret', v_config.secret
    ),
    body := jsonb_build_object(
      'record', jsonb_build_object(
        'id', new.id,
        'resto_id', new.resto_id,
        'event', new.event,
        'payload', new.payload
      )
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_push_outbox on push_outbox;
create trigger trg_notify_push_outbox
  after insert on push_outbox
  for each row execute function notify_push_outbox();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memastikan
-- ─────────────────────────────────────────────────────────────────────
-- Buat satu pesanan, lalu:
--
--   select event, created_at, sent_at, error from push_outbox
--   order by created_at desc limit 5;
--
-- sent_at terisi berarti benar-benar terkirim. Kalau masih kosong,
-- lihat antrean pg_net-nya — di situ tercatat jawaban HTTP-nya:
--
--   select id, created, status_code, content from net._http_response
--   order by created desc limit 5;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 9 dari 27 — payment_gateway.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — QRIS sungguhan lewat Xendit.
--
-- Jalankan SETELAH customer_cash_payment.sql. Aman dijalankan berulang
-- kali.
--
-- Sampai sekarang QRIS-nya simulasi: kodenya dibangkitkan sendiri dan
-- yang menandai lunas adalah tombol yang ditekan pelanggan. Berkas ini
-- menyiapkan sisi database untuk pembayaran yang benar-benar terjadi —
-- tagihannya dibuat di server, dan yang menyatakannya lunas adalah
-- webhook dari Xendit, bukan siapa pun yang memegang HP.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tagihan yang dibuat di penyedia
-- ─────────────────────────────────────────────────────────────────────

-- Satu baris per tagihan, bukan kolom tambahan di `orders`.
--
-- Sebuah pesanan bisa punya lebih dari satu tagihan: QR yang kedaluwarsa
-- sebelum dibayar harus dibuatkan yang baru, dan yang lama tetap perlu
-- tercatat — kalau ternyata dibayar juga di detik terakhir, webhooknya
-- datang menyebut tagihan yang mana.
create table if not exists payment_charges (
  id uuid primary key default gen_random_uuid(),

  order_id uuid not null references orders (id) on delete cascade,
  resto_id text references restaurants (id) on delete cascade,

  provider text not null default 'xendit',

  -- Pengenal yang kita kirim ke penyedia, dan yang dikembalikan lagi di
  -- webhooknya. Unik, karena itulah yang dipakai mencocokkan kembali.
  reference_id text not null unique,

  -- Pengenal milik penyedia.
  provider_charge_id text,

  -- Isi QR-nya. Disimpan supaya layar yang dibuka ulang menampilkan QR
  -- yang sama persis, bukan membuat tagihan baru tiap kali orangnya
  -- kembali ke layar itu.
  qr_string text,

  amount bigint not null,
  status text not null default 'pending',
  expires_at timestamptz,
  paid_at timestamptz,

  -- Jawaban mentah dari penyedia, apa adanya. Saat ada selisih uang,
  -- inilah satu-satunya keterangan yang tidak bisa dibantah.
  raw jsonb,

  created_at timestamptz not null default now()
);

alter table payment_charges
  drop constraint if exists payment_charges_status_check;
alter table payment_charges add constraint payment_charges_status_check
  check (status in ('pending', 'paid', 'expired', 'failed'));

create index if not exists payment_charges_order_idx on payment_charges (order_id);
create index if not exists payment_charges_status_idx on payment_charges (status, created_at desc);

alter table payment_charges enable row level security;

-- Tidak ada kebijakan apa pun untuk aplikasi. Yang membuat tagihan dan
-- yang menandainya lunas sama-sama Edge Function dengan service role.
-- Membiarkan aplikasi menulis ke sini berarti membiarkan siapa pun yang
-- memegang anon key menyatakan tagihannya sendiri lunas.
revoke all on table payment_charges from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Pelunasan, hanya dari webhook
-- ─────────────────────────────────────────────────────────────────────

-- Dipanggil Edge Function penerima webhook. Satu fungsi, satu tugas:
-- menandai tagihan dan pesanannya lunas, sekali saja.
--
-- Webhook penyedia bisa datang dua kali untuk pembayaran yang sama —
-- itu perilaku normal, bukan kesalahan. Tanpa penjagaan di sini,
-- pesanan yang sama akan masuk jurnal dua kali dan pemasukan hari itu
-- tercatat dobel.
create or replace function settle_gateway_payment(
  p_reference_id text,
  p_provider_charge_id text default null,
  p_raw jsonb default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_charge payment_charges;
begin
  select * into v_charge from payment_charges
  where reference_id = p_reference_id for update;

  if v_charge.id is null then
    return 'tagihan tidak dikenal';
  end if;

  if v_charge.status = 'paid' then
    return 'sudah lunas sebelumnya';
  end if;

  update payment_charges set
    status = 'paid',
    paid_at = now(),
    provider_charge_id = coalesce(p_provider_charge_id, provider_charge_id),
    raw = coalesce(p_raw, raw)
  where id = v_charge.id;

  -- Pesanannya sendiri hanya disentuh kalau memang masih menunggu.
  -- Pesanan yang sudah dilunasi lewat jalan lain — misalnya pelanggan
  -- akhirnya membayar tunai di kasir — tidak boleh ikut tertimpa.
  update orders set payment_status = 'paid'
  where id = v_charge.order_id and payment_status = 'pending';

  return 'lunas';
end;
$$;

-- Tidak diberikan ke anon maupun authenticated. Hanya service role, yang
-- memang melewati pemeriksaan hak akses.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Langkah berikutnya, di luar berkas ini
-- ─────────────────────────────────────────────────────────────────────
--
--   supabase secrets set --project-ref xizpwtycczigjhzxegen \
--     XENDIT_SECRET_KEY='xnd_development_...' \
--     XENDIT_CALLBACK_TOKEN='...'
--
--   supabase functions deploy create-qris    --project-ref xizpwtycczigjhzxegen
--   supabase functions deploy xendit-webhook --project-ref xizpwtycczigjhzxegen --no-verify-jwt
--
-- Lalu daftarkan URL webhooknya di Dashboard Xendit → Settings →
-- Callbacks → QR Code payment:
--
--   https://xizpwtycczigjhzxegen.supabase.co/functions/v1/xendit-webhook
--
-- Memeriksa hasilnya kapan pun:
--
--   select reference_id, amount, status, expires_at, paid_at
--   from payment_charges order by created_at desc limit 20;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 10 dari 27 — gateway_settlement.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pencairan dana dari payment gateway.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang pesanan QRIS dicatat penuh dan seketika ke GL QRIS,
-- seolah uangnya langsung ada di rekening. Dengan gateway sungguhan itu
-- tidak benar dua kali:
--
--   1. Yang benar-benar masuk rekening adalah nominal DIKURANGI MDR
--      (sekitar 0,7%).
--   2. Masuknya BARU T+1 atau T+2, bukan saat pelanggan membayar.
--
-- Kalau dibiarkan, GL QRIS akan terus bertambah tanpa pernah cocok
-- dengan mutasi bank mana pun, dan selisihnya menumpuk tiap hari sampai
-- tidak ada yang berani menutup buku.
--
-- Yang berubah di sini bukan pencatatan pemasukannya — itu tetap seperti
-- sekarang. GL QRIS-nya sendiri yang berubah arti: bukan "uang di
-- rekening", melainkan "uang yang ditahan penyedia dan akan cair".
-- Berkas ini menambahkan kejadian keduanya: saat dananya benar-benar
-- cair.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Akun biaya MDR
-- ─────────────────────────────────────────────────────────────────────

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount'));

-- ─────────────────────────────────────────────────────────────────────
-- 2. Catatan pencairan
-- ─────────────────────────────────────────────────────────────────────

-- Bruto, biaya, dan neto disimpan ketiganya, walaupun yang satu bisa
-- dihitung dari dua lainnya.
--
-- Ini bukan penyimpanan berlebih: yang tertulis di mutasi bank adalah
-- neto, yang tertulis di laporan penyedia adalah bruto dan biaya, dan
-- saat keduanya tidak cocok — pembulatan, biaya tambahan, penyesuaian —
-- yang dibutuhkan justru ketiganya apa adanya. Menghitung ulang salah
-- satunya berarti menghapus bukti bahwa mereka pernah berbeda.
create table if not exists gateway_settlements (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  settled_on date not null default (now() at time zone 'Asia/Jakarta')::date,

  gross_amount bigint not null,
  fee_amount bigint not null default 0,
  net_amount bigint not null,

  provider text not null default 'xendit',
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists gateway_settlements_resto_idx
  on gateway_settlements (resto_id, settled_on desc);

alter table gateway_settlements enable row level security;

drop policy if exists "gateway_settlements: finance read" on gateway_settlements;
create policy "gateway_settlements: finance read" on gateway_settlements
  for select using (is_resto_employee(resto_id, array['finance', 'admin']));

-- Hanya Finance yang mencatatnya. Ini bukan pengajuan yang butuh
-- persetujuan seperti setoran tunai — Finance sedang menyalin apa yang
-- sudah terjadi di rekening, bukan meminta sesuatu terjadi.
drop policy if exists "gateway_settlements: finance write" on gateway_settlements;
create policy "gateway_settlements: finance write" on gateway_settlements
  for all using (is_resto_employee(resto_id, array['finance']))
  with check (is_resto_employee(resto_id, array['finance']));

-- ─────────────────────────────────────────────────────────────────────
-- 3. Jurnalnya
-- ─────────────────────────────────────────────────────────────────────

-- Tiga kaki, dan ketiganya harus seimbang:
--
--   GL QRIS         debit  bruto   uang meninggalkan penampungan penyedia
--   GL Total Saldo  credit neto    yang benar-benar masuk rekening
--   GL Biaya MDR    credit biaya   potongan penyedia, diakui sebagai beban
--
-- Debit = uang keluar dari akun, credit = uang masuk ke akun — konvensi
-- yang sama dengan seluruh jurnal KaataGo lainnya.
create or replace function log_gateway_settlement_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_qris_gl record;
  v_total_gl record;
  v_fee_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  select * into v_qris_gl from _gl_account_for(new.resto_id, 'qris');
  if v_qris_gl.gl_code is not null and v_qris_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_qris_gl.gl_code, v_qris_gl.gl_name, 'gateway_settlement', new.id::text,
      new.gross_amount, 'debit', 'Pencairan gateway #' || v_ref
    );
  end if;

  select * into v_total_gl from _gl_account_for(new.resto_id, 'total_balance');
  if v_total_gl.gl_code is not null and v_total_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_total_gl.gl_code, v_total_gl.gl_name, 'gateway_settlement', new.id::text,
      new.net_amount, 'credit', 'Dana gateway masuk rekening #' || v_ref
    );
  end if;

  -- Biaya nol tidak dijurnal sama sekali. Baris bernilai nol bukan
  -- keterangan, cuma derau yang harus dilewati mata setiap kali.
  if new.fee_amount > 0 then
    select * into v_fee_gl from _gl_account_for(new.resto_id, 'gateway_fee');
    if v_fee_gl.gl_code is not null and v_fee_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        new.resto_id, v_date, v_time,
        v_fee_gl.gl_code, v_fee_gl.gl_name, 'gateway_settlement', new.id::text,
        new.fee_amount, 'credit', 'Biaya MDR pencairan #' || v_ref
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_gateway_settlement on gateway_settlements;
create trigger trg_log_gateway_settlement
  after insert on gateway_settlements
  for each row execute function log_gateway_settlement_journal();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- Isi nomor GL untuk "GL Biaya MDR" di Finance → Mapping GL Account.
-- Tanpa itu, biayanya tidak akan tercatat dan jurnal pencairannya jadi
-- timpang sebesar potongan penyedia.
--
-- Memeriksa keseimbangannya kapan pun:
--
--   select reference_id,
--          sum(case when entry_type = 'debit'  then amount else 0 end) as debit,
--          sum(case when entry_type = 'credit' then amount else 0 end) as kredit
--   from gl_journal_entries
--   where reference_type = 'gateway_settlement'
--   group by reference_id;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 11 dari 27 — resto_payment_accounts.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pencairan langsung ke rekening masing-masing resto.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang seluruh pembayaran QRIS masuk ke satu akun penyedia:
-- yang kuncinya terpasang di server. Untuk resto milik sendiri itu tidak
-- masalah. Untuk resto milik orang lain, itu berarti uang mereka mampir
-- dulu ke rekening KaataGo — dan menampung lalu meneruskan dana milik
-- pihak lain bukan sekadar urusan pembukuan.
--
-- Jalan keluarnya sub-akun: tiap resto punya akunnya sendiri di
-- penyedia, dan pembayarannya dibuat atas nama akun itu. Dananya cair
-- langsung ke rekening restonya, tanpa pernah lewat rekening KaataGo.
--
-- Yang disimpan di sini hanya PENGENAL sub-akunnya, bukan kuncinya.
-- Menyimpan secret key milik resto lain berarti satu kebocoran database
-- membuka seluruh akun penyedia mereka sekaligus — kerugian yang bukan
-- milik kita tapi kita yang menyebabkannya.

begin;

create table if not exists resto_payment_accounts (
  resto_id text primary key references restaurants (id) on delete cascade,

  provider text not null default 'xendit',

  -- Pengenal sub-akun di penyedia. Dikirim sebagai header saat membuat
  -- tagihan, dan itu yang menentukan ke rekening siapa dananya cair.
  account_id text not null,

  -- Sekadar catatan supaya Finance tahu ini akun yang mana tanpa harus
  -- membuka dashboard penyedia.
  account_label text,

  active boolean not null default true,
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table resto_payment_accounts enable row level security;

-- Tidak terbaca pelanggan. Tabel `settings` disiarkan realtime ke layar
-- pembayaran pelanggan, jadi pengenal ini sengaja tidak dititipkan di
-- sana — bukan karena rahasia, tapi karena tidak ada gunanya di HP
-- pelanggan dan yang tidak berguna di sana sebaiknya tidak ada di sana.
drop policy if exists "resto_payment_accounts: staff read" on resto_payment_accounts;
create policy "resto_payment_accounts: staff read" on resto_payment_accounts
  for select using (
    is_super_admin() or is_resto_employee(resto_id, array['finance', 'admin'])
  );

drop policy if exists "resto_payment_accounts: staff write" on resto_payment_accounts;
create policy "resto_payment_accounts: staff write" on resto_payment_accounts
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['finance'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Aktifkan xenPlatform di akun Xendit KaataGo (butuh verifikasi
--    badan usaha; di mode uji bisa langsung dicoba).
--
-- 2. Buat sub-akun untuk tiap resto — lewat Dashboard atau API:
--
--      curl -X POST https://api.xendit.co/v2/accounts \
--        -u 'xnd_development_...:' -H 'Content-Type: application/json' \
--        -d '{"email":"resto@contoh.com","type":"OWNED",
--             "public_profile":{"business_name":"Kaata Resto Dago"}}'
--
--    Jawabannya memuat "id" berawalan angka/huruf — itu yang diisikan
--    ke aplikasi lewat Finance → Pengaturan Pembayaran.
--
-- 3. Tiap resto melengkapi rekening banknya sendiri di sub-akun itu.
--    Sampai itu selesai, dananya tertahan di saldo sub-akun — tidak
--    hilang, tapi juga tidak cair.
--
-- Memeriksa resto mana yang sudah terpasang:
--
--   select r.name, a.account_id, a.active
--   from restaurants r
--   left join resto_payment_accounts a on a.resto_id = r.id;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 12 dari 27 — counter_charge.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — tagihan QRIS di meja kasir.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Pesanan yang diinput kasir baru dibuat SETELAH pembayarannya diterima,
-- bukan sebelum — itu urutan yang sudah ada sejak awal, dan mengubahnya
-- berarti membongkar alur checkout beserta pengurangan stoknya. Jadi
-- tagihannya boleh berdiri tanpa pesanan: yang menghubungkannya nanti
-- adalah transaksi yang tercatat sesudahnya.

begin;

alter table payment_charges alter column order_id drop not null;

-- Status tagihan, untuk ditanyakan aplikasi kasir sambil menunggu.
--
-- Lewat fungsi, bukan membaca tabelnya langsung: tabel tagihan tetap
-- tertutup rapat dari aplikasi. Yang boleh diketahui cuma satu kata —
-- sudah dibayar atau belum — dan bukan seluruh isinya.
create or replace function gateway_charge_status(p_reference_id text)
returns text
language sql
security definer
set search_path = public
as $$
  select status from payment_charges where reference_id = p_reference_id;
$$;

grant execute on function gateway_charge_status(text) to anon, authenticated;

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 13 dari 27 — announcement_push.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pengumuman ikut membunyikan HP.
--
-- Selama ini pengumuman hanya duduk di Kotak Masuk. Kotak Masuk baru
-- dilihat orang kalau dia membuka aplikasinya, dan orang membuka
-- aplikasinya kalau ada yang memanggil. Pengumuman yang menunggu
-- dibuka adalah pengumuman yang dibaca seminggu kemudian — atau tidak
-- sama sekali.
--
-- Jangkauannya mengikuti resto_id pengumuman itu sendiri, aturan yang
-- sama dengan yang sudah dipakai saat menampilkannya:
--   resto_id kosong  → dari Super Admin, kabar versi baru, untuk semua
--   resto_id terisi  → dari admin resto itu, hanya perangkat restonya
--                      — pelanggan maupun karyawan, apa pun perannya.
--
-- Jalankan di SQL Editor Supabase.

begin;

create or replace function queue_push_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into push_outbox (resto_id, event, payload) values (
    new.resto_id, 'announcement',
    jsonb_build_object(
      'audience', 'all',
      'title', new.title,
      -- Isi pengumuman bisa sepanjang apa pun; baris notifikasi tidak.
      -- Dipotong di sini supaya yang sampai di layar kunci adalah
      -- kalimat pembuka yang utuh, bukan paragraf yang dipenggal
      -- Android di tempat sembarang.
      'body', case
                when length(new.body) > 160
                  then left(new.body, 157) || '...'
                else new.body
              end
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_queue_push_announcement on app_announcements;
create trigger trg_queue_push_announcement
  after insert on app_announcements
  for each row execute function queue_push_announcement();

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 14 dari 27 — cash_payment_expiry.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pesanan tunai yang tidak dilunasi di kasir hangus sendiri.
--
-- Pelanggan yang memesan dari HP lalu memilih bayar tunai diarahkan ke
-- meja kasir. Sebagian tidak pernah sampai ke sana: berubah pikiran,
-- salah pencet, atau memang tidak berniat datang. Tanpa batas waktu,
-- pesanan itu menetap selamanya di layar Pending Payment dan di dapur —
-- dan tiap hari sisanya bertambah sedikit, sampai layarnya tidak lagi
-- bisa dipakai membaca apa yang benar-benar sedang ditunggu.
--
-- Tiga puluh menit dihitung dari pesanannya dibuat. Angka yang sama
-- ditulis di HP pelanggan (CustomerOrder.paymentWindow) — kalau salah
-- satunya diubah, keduanya harus diubah.
--
-- Butuh pg_cron. Kalau belum aktif: Dashboard → Database → Extensions →
-- cari "pg_cron" → Enable. Aman dijalankan berulang kali.

begin;

create extension if not exists pg_cron with schema extensions;

-- 'expired' — dibatalkan karena tidak dibayar. Dibedakan dari 'pending'
-- supaya hilang dari antrean kasir dan dapur, dan dibedakan dari 'paid'
-- supaya tidak pernah ikut terhitung sebagai pendapatan.
--
-- Daftarnya ditulis lengkap — termasuk 'cancelled' yang baru
-- diperkenalkan berkas lain. Berkas yang menuliskan daftar sepanjang
-- zamannya sendiri berjalan baik tepat sekali: saat dijalankan berurutan
-- di database kosong. Menjalankan ulang yang lebih tua sesudah yang
-- lebih baru menyempitkan daftarnya lagi, dan baris yang terlanjur
-- memakai nilai baru langsung melanggarnya:
--
--   check constraint "orders_payment_status_check" is violated by some row
--
-- Tidak ada satu pun data yang salah di sana. Yang salah adalah
-- batasannya yang mundur.
alter table orders drop constraint if exists orders_payment_status_check;
alter table orders add constraint orders_payment_status_check
  check (payment_status in ('pending', 'paid', 'expired', 'cancelled'));

create or replace function expire_unpaid_cash_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with hangus as (
    update orders
    set payment_status = 'expired'
    where payment_status = 'pending'
      and source = 'customer'
      -- Hanya yang tunai. Pesanan QRIS punya tenggangnya sendiri di sisi
      -- penyedia pembayaran, dan membatalkannya dari sini berarti
      -- membatalkan pesanan yang uangnya mungkin sedang dalam perjalanan.
      and _normalize_payment_method(source, payment_method) = 'cash'
      and created_at <= now() - interval '30 minutes'
    returning 1
  )
  select count(*) into v_count from hangus;
  return v_count;
end;
$$;

-- Tiap menit. Tenggangnya tetap 30 menit — yang diputuskan di sini cuma
-- seberapa cepat pesanan yang sudah lewat tenggang benar-benar hilang
-- dari layar, dan menitan sudah cukup rapat untuk itu.
select cron.unschedule('expire-unpaid-cash-orders')
where exists (
  select 1 from cron.job where jobname = 'expire-unpaid-cash-orders'
);

select cron.schedule(
  'expire-unpaid-cash-orders',
  '* * * * *',
  $$select expire_unpaid_cash_orders();$$
);

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 15 dari 27 — level_groups.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — tiap resto menyusun sendiri kelompok levelnya.
--
-- Jalankan SETELAH product_level_groups.sql. Aman diulang.
--
-- Sebelumnya daftarnya tertanam di dalam aplikasi: lima kelompok tetap
-- (Level Pedas, Level Gula, Level Es, Suhu, Ukuran), sama untuk semua
-- resto. Cukup untuk warung nasi dan kedai kopi, dan langsung kurang
-- untuk yang berikutnya — tingkat kematangan steak, pilihan topping,
-- jenis susu. Resto yang butuh satu kelompok di luar lima itu tidak
-- punya jalan apa pun selain menyuruh pelanggannya mengetik di kolom
-- catatan, yang tidak terbaca sebagai pilihan oleh dapur maupun kasir.
--
-- Produk tetap menyandang NAMA kelompoknya (products.level_groups),
-- bukan id-nya. Sengaja: itu yang sudah tersimpan di ribuan baris
-- produk dan pesanan, dan mengubahnya jadi id berarti membongkar
-- riwayat pesanan yang sudah terjadi hanya demi kerapian.

begin;

create table if not exists level_groups (
  id text primary key,
  resto_id text not null references restaurants (id) on delete cascade,

  -- Namanya yang mengikat produk ke kelompok ini, jadi tidak boleh
  -- kembar di dalam satu resto.
  name text not null,

  options jsonb not null default '[]'::jsonb,

  -- Urutan tampilnya di layar pesan. Kelompok yang paling sering
  -- dipakai pantas berada di atas, dan itu berbeda tiap resto.
  sort_order integer not null default 0,

  created_at timestamptz not null default now(),
  unique (resto_id, name)
);

create index if not exists idx_level_groups_resto on level_groups (resto_id);

alter table level_groups enable row level security;

-- Dibaca siapa saja, termasuk pelanggan tamu yang belum login: tanpa
-- ini dropdown level di layar pesan kosong, dan pesanan pedas tidak
-- bisa dibedakan dari yang tidak.
drop policy if exists "level_groups: public read" on level_groups;
create policy "level_groups: public read" on level_groups
  for select using (true);

drop policy if exists "level_groups: admin write" on level_groups;
create policy "level_groups: admin write" on level_groups
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['admin'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['admin'])
  );

-- ─────────────────────────────────────────────────────────────────────
-- Bibit: lima kelompok yang selama ini tertanam di aplikasi
-- ─────────────────────────────────────────────────────────────────────
--
-- Disemaikan ke tiap resto yang sudah ada, sekali. Tanpa ini semua resto
-- membuka tab Level yang kosong dan produk mereka yang sudah menyandang
-- "Level Pedas" menunjuk kelompok yang tidak ada lagi.
--
-- `on conflict do nothing` yang membuatnya aman diulang: resto yang
-- sudah menyunting "Level Pedas"-nya sendiri tidak dikembalikan ke
-- bentuk bawaan hanya karena berkas ini dijalankan dua kali.

insert into level_groups (id, resto_id, name, options, sort_order)
select
  r.id || ':' || b.name,
  r.id,
  b.name,
  b.options,
  b.sort_order
from restaurants r
cross join (values
  ('Level Pedas',
   '["Tidak Pedas","Sedang","Pedas","Extra Pedas"]'::jsonb, 0),
  ('Level Gula',
   '["Normal","Kurang Manis","Setengah Manis","Tanpa Gula"]'::jsonb, 1),
  ('Level Es',
   '["Normal","Less Ice","No Ice"]'::jsonb, 2),
  ('Suhu',
   '["Panas","Dingin"]'::jsonb, 3),
  ('Ukuran',
   '["Regular","Large"]'::jsonb, 4)
) as b(name, options, sort_order)
on conflict (resto_id, name) do nothing;

commit;

-- Resto yang dibuat SESUDAH ini tetap perlu bibitnya. Pemicu di bawah
-- yang mengurusnya, supaya tidak ada yang harus ingat menjalankan
-- berkas ini lagi tiap kali ada resto baru.
create or replace function seed_level_groups()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into level_groups (id, resto_id, name, options, sort_order)
  select new.id || ':' || b.name, new.id, b.name, b.options, b.sort_order
  from (values
    ('Level Pedas', '["Tidak Pedas","Sedang","Pedas","Extra Pedas"]'::jsonb, 0),
    ('Level Gula', '["Normal","Kurang Manis","Setengah Manis","Tanpa Gula"]'::jsonb, 1),
    ('Level Es', '["Normal","Less Ice","No Ice"]'::jsonb, 2),
    ('Suhu', '["Panas","Dingin"]'::jsonb, 3),
    ('Ukuran', '["Regular","Large"]'::jsonb, 4)
  ) as b(name, options, sort_order)
  on conflict (resto_id, name) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_level_groups on restaurants;
create trigger trg_seed_level_groups
  after insert on restaurants
  for each row execute function seed_level_groups();


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 16 dari 27 — resto_order_types.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — resto menentukan sendiri melayani Dine In, Take Away, atau
-- keduanya.
--
-- Aman dijalankan berulang kali.
--
-- Selama ini kedua pilihan selalu ditawarkan di layar checkout, di
-- semua resto. Padahal tidak semua resto melayani keduanya: gerai food
-- court dan cloud kitchen tidak punya meja sama sekali. Selama
-- pilihannya tetap ada, pesanan yang tidak bisa dilayani tetap masuk —
-- dan yang harus menolaknya adalah orang, di depan pelanggan yang sudah
-- membayar.
--
-- Keduanya true untuk semua resto yang sudah ada. Mematikan salah
-- satunya harus jadi keputusan yang diambil sengaja, bukan akibat kolom
-- baru yang belum sempat diisi.

begin;

alter table restaurants
  add column if not exists dine_in_enabled boolean not null default true;
alter table restaurants
  add column if not exists take_away_enabled boolean not null default true;

-- Resto yang tidak melayani keduanya tidak bisa menerima pesanan apa
-- pun — layar checkoutnya tidak punya satu pun pilihan yang bisa
-- ditekan. Itu bukan konfigurasi, itu resto yang tutup, dan untuk itu
-- sudah ada kolom `active`.
alter table restaurants drop constraint if exists restaurants_order_type_check;
alter table restaurants add constraint restaurants_order_type_check
  check (dine_in_enabled or take_away_enabled);

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 17 dari 27 — product_out_of_stock.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — ketersediaan produk ditandai, bukan dihitung.
--
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang produk hilang dari menu begitu stoknya 0. Itu memaksa
-- tiap resto mengurus angka yang sebagian besar tidak pernah mereka
-- hitung: nasi goreng tidak punya "sisa 7 porsi", yang ada cuma "masih
-- ada" atau "bahannya habis". Resto yang membiarkan stoknya 0 karena
-- angkanya memang tidak relevan justru kehilangan seluruh menunya, dan
-- tidak pernah tahu kenapa.
--
-- Sekarang angka stok jadi catatan biasa — boleh diisi, boleh tidak —
-- dan yang menentukan bisa dipesan atau tidak cuma kolom ini, yang
-- dinyatakan sengaja oleh orang yang tahu keadaan dapurnya.

begin;

alter table products
  add column if not exists out_of_stock boolean not null default false;

-- Stok tidak lagi wajib. Produk yang tidak diisi angkanya bukan produk
-- yang habis — cuma produk yang tidak dihitung.
alter table products alter column stock drop not null;
alter table products alter column stock set default 0;

-- Produk lama dianggap tersedia, termasuk yang stoknya 0.
--
-- Sebagian dari mereka memang benar-benar habis, dan menyalakannya
-- kembali berarti resto harus menandainya lagi satu per satu. Itu
-- disengaja: resto jauh lebih cepat menandai barang yang habis daripada
-- menemukan sendiri kenapa separuh menunya tidak pernah muncul.
update products set out_of_stock = false where out_of_stock is null;

commit;

-- Catatan: fungsi decrement_stock tetap dipakai — angkanya masih
-- berguna buat resto yang memang menghitung. Yang berubah cuma
-- artinya: mencapai nol tidak lagi menyembunyikan produknya.


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 18 dari 27 — discounts.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — diskon: per menu (termasuk bundling) atau minimum belanja.
--
-- Jalankan SETELAH gl_journal.sql dan orders_gl_code.sql. Aman diulang.
--
-- Diskon bukan sekadar angka yang dikurangi di layar kasir. Uang yang
-- tidak jadi diterima tetap harus terlihat di pembukuan — kalau tidak,
-- Penghasilan resto tercatat sebesar harga daftar sementara uang yang
-- masuk lebih kecil, dan selisihnya muncul sebagai kas yang hilang
-- tanpa sebab. Karena itu diskon punya GL-nya sendiri sebagai pengurang
-- pendapatan.

begin;

create table if not exists discounts (
  id text primary key,
  resto_id text not null references restaurants (id) on delete cascade,
  name text not null,

  -- 'products'     → berlaku untuk menu yang disebut di product_ids
  -- 'min_purchase' → berlaku untuk seluruh tagihan yang mencapai ambang
  basis text not null default 'products'
    check (basis in ('products', 'min_purchase')),

  -- 'percent' → value 1..100, 'amount' → value dalam rupiah
  kind text not null default 'percent'
    check (kind in ('percent', 'amount')),
  value integer not null check (value > 0),

  -- Lebih dari satu menu dalam satu aturan: itulah cara bundling
  -- dinyatakan. Potongannya dihitung dari jumlah seluruh menu yang ikut,
  -- bukan per baris — kalau per baris, diskon rupiah tetap akan
  -- terkalikan sebanyak menu yang ikut promo.
  product_ids jsonb not null default '[]'::jsonb,

  min_purchase bigint not null default 0,

  -- '>' atau '>='. Dipilih sendiri karena keduanya berbeda di telinga
  -- pelanggan, dan transaksi yang nilainya pas di batas adalah yang
  -- paling sering jadi perselisihan di meja kasir.
  compare_mode text not null default 'at_least'
    check (compare_mode in ('at_least', 'more_than')),

  -- Masa berlaku. Tanggal, bukan timestamp: resto berpikir dalam hari,
  -- dan "sampai 31 Agustus" berarti sampai tutup toko tanggal 31.
  starts_on date,
  ends_on date,

  active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now(),

  -- Yang berakhir sebelum dimulai bukan promo, itu salah ketik. Ditolak
  -- di sini juga, bukan hanya di formulirnya: aturan yang cuma dijaga
  -- aplikasi akan bocor lewat jalan lain suatu hari.
  constraint discounts_period_check
    check (ends_on is null or starts_on is null or ends_on > starts_on),

  -- Diskon berbasis menu tanpa satu pun menu tidak pernah mengenai apa
  -- pun; diskon minimum belanja dengan ambang nol mengenai semuanya,
  -- termasuk tagihan seribu rupiah.
  constraint discounts_target_check check (
    (basis = 'products' and jsonb_array_length(product_ids) > 0)
    or (basis = 'min_purchase' and min_purchase > 0)
  ),

  constraint discounts_percent_check
    check (kind <> 'percent' or value between 1 and 100)
);

create index if not exists idx_discounts_resto on discounts (resto_id, active);

alter table discounts enable row level security;

-- Dibaca siapa saja termasuk pelanggan tamu: promonya harus terlihat di
-- layar pesan, bukan baru muncul di struk.
drop policy if exists "discounts: public read" on discounts;
create policy "discounts: public read" on discounts for select using (true);

-- Ditulis kasir, admin, dan owner — sesuai menunya.
drop policy if exists "discounts: staff write" on discounts;
create policy "discounts: staff write" on discounts
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['admin', 'kasir', 'owner'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['admin', 'kasir', 'owner'])
  );

-- ─────────────────────────────────────────────────────────────────────
-- Diskon pada pesanan
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan di barisnya sendiri, bukan dihitung ulang saat dibaca.
-- Aturan diskonnya bisa diubah atau dihapus besok, sementara struk
-- pesanan hari ini harus tetap menyebut potongan yang benar-benar
-- diberikan saat itu.

alter table orders add column if not exists discount_amount bigint not null default 0;
alter table orders add column if not exists discount_id text;
alter table orders add column if not exists discount_name text;

-- ─────────────────────────────────────────────────────────────────────
-- GL Diskon
-- ─────────────────────────────────────────────────────────────────────
--
-- Sebagai pengurang pendapatan, bukan sebagai biaya. Diskon tidak
-- pernah menjadi uang yang keluar dari resto — ia adalah uang yang
-- tidak pernah masuk. Mencatatnya sebagai biaya membuat Pengeluaran
-- terlihat naik pada bulan promo, padahal tidak ada satu rupiah pun
-- yang berpindah.

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount'));

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'discount', '2200002', 'GL Diskon Penjualan'
from restaurants r
on conflict (resto_id, payment_method) do nothing;

-- Jenis rujukan baru. Daftarnya ditulis lengkap di tiap berkas yang
-- menyentuhnya — sama alasannya dengan gl_accounts: berkas lama yang
-- dijalankan ulang sesudah yang baru akan menyempitkan daftarnya lagi
-- dan menolak baris yang sudah terlanjur ada.
alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (reference_type in ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit'));

-- Jurnal diskon.
--
-- Ditambahkan sebagai pemicu terpisah, bukan dengan menulis ulang
-- log_order_paid_journal(): fungsi itu sudah ditimpa oleh empat berkas
-- berbeda sepanjang umur proyek ini, dan menimpanya sekali lagi dari
-- sini berarti urutan menjalankan berkas menentukan versi mana yang
-- akhirnya berlaku. Pemicu sendiri tidak punya masalah itu.
--
-- Didebit, bukan dikredit. Kesepakatan aplikasi ini: kredit = uang
-- masuk ke akun itu, debit = uang keluar. Diskon adalah pendapatan yang
-- tidak jadi diterima, jadi ia mengurangi — dan panah di layar Jurnal
-- GL akan menunjuk arah yang sama dengan yang dilihat Finance.
create or replace function log_order_discount_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  if new.payment_status <> 'paid' or coalesce(new.discount_amount, 0) <= 0 then
    return new;
  end if;

  -- Sudah pernah dicatat? Pesanan bisa berpindah status lebih dari
  -- sekali — dilunasi di kasir, lalu diperbaiki cara bayarnya — dan
  -- tiap perpindahan tidak boleh menambah satu baris diskon lagi.
  if exists (
    select 1 from gl_journal_entries
    where reference_type = 'order_discount' and reference_id = new.id::text
  ) then
    return new;
  end if;

  select * into v_gl from _gl_account_for(new.resto_id, 'discount');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id,
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'order_discount', new.id::text, new.discount_amount, 'debit',
      coalesce(nullif(new.discount_name, ''), 'Diskon') || ' — pesanan #' || v_ref
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_order_discount_insert on orders;
create trigger trg_log_order_discount_insert
  after insert on orders
  for each row execute function log_order_discount_journal();

drop trigger if exists trg_log_order_discount_update on orders;
create trigger trg_log_order_discount_update
  after update of payment_status on orders
  for each row execute function log_order_discount_journal();

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 19 dari 27 — promo_banner_period.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — banner promo punya masa berlaku.
--
-- Aman dijalankan berulang kali.
--
-- Sebelumnya banner hanya punya saklar aktif/nonaktif, dan itu berarti
-- ada orang yang harus ingat mematikannya. Promo Ramadan yang masih
-- terpasang di bulan Juli bukan sekadar salah — ia menjanjikan harga
-- yang sudah tidak berlaku kepada orang yang sedang memesan.
--
-- Tanggal, bukan timestamp: resto berpikir dalam hari, dan "sampai 31
-- Agustus" berarti sampai tutup toko tanggal 31.

begin;

alter table promo_banners add column if not exists starts_on date;
alter table promo_banners add column if not exists ends_on date;

alter table promo_banners drop constraint if exists promo_banners_period_check;
alter table promo_banners add constraint promo_banners_period_check
  check (ends_on is null or starts_on is null or ends_on > starts_on);

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 20 dari 27 — default_gl_accounts.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — resto baru langsung punya bagan akun dan tarif pajaknya.
--
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang resto yang baru dibuat lahir tanpa satu pun GL
-- account. Akibatnya bukan sekadar merepotkan: pemicu jurnal melewatkan
-- baris yang GL-nya kosong, jadi transaksi hari-hari pertama benar-benar
-- terjadi, uangnya benar-benar diterima, tapi tidak pernah masuk Jurnal
-- GL. Yang menemukan lubangnya adalah Finance, berminggu-minggu
-- kemudian, saat mencari ke mana perginya penjualan minggu pembukaan.
--
-- Semua yang diisi di sini tetap bisa diubah Finance lewat Mapping GL
-- Account. Yang diberikan cuma titik berangkat yang masuk akal.
--
-- Pengelompokan nomornya:
--
--   195xxxx  Pemasukan (tunai, QRIS, transfer, agregat)
--   196xxxx  Pajak & service
--   198xxxx  Petty cash
--   199xxxx  Total saldo
--   210xxxx  Suspense & pengeluaran
--   220xxxx  Payment gateway & diskon

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tarif bawaan
-- ─────────────────────────────────────────────────────────────────────
--
-- PPN 11% dan service 5% — yang paling lazim dipakai restoran di
-- Indonesia. Nol sebagai bawaan terlihat aman, tapi artinya tiap resto
-- baru menjual dengan harga yang belum memuat pajak sampai ada yang
-- ingat menyetelnya, dan selisih itu tidak bisa ditagih ulang ke
-- pelanggan yang sudah pulang.
--
-- Hanya berlaku untuk resto yang dibuat SESUDAH ini. Resto yang sudah
-- ada tidak disentuh: mengubah tarif pajak resto yang sedang berjalan
-- akan mengubah harga jual seluruh menunya dalam satu perintah.
alter table restaurants alter column ppn_percent set default 11;
alter table restaurants alter column service_percent set default 5;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Bagan akun bawaan
-- ─────────────────────────────────────────────────────────────────────

create or replace function _default_gl_accounts()
returns table (payment_method text, gl_code text, gl_name text)
language sql
immutable
as $$
  values
    -- Pemasukan
    ('cash',             '1950001', 'GL Kas Tunai'),
    ('qris',             '1950002', 'GL Penerimaan QRIS'),
    ('transfer',         '1950003', 'GL Penerimaan Transfer'),
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

-- Akun biaya bawaan. Terpisah dari yang di atas karena pengeluaran
-- memang berkategori banyak, dan tiap resto akan menambah sendiri
-- sesudahnya.
create or replace function _default_expense_gl_accounts()
returns table (gl_code text, gl_name text)
language sql
immutable
as $$
  values
    ('2101001', 'GL Biaya Operasional'),
    ('2101002', 'GL Biaya Bahan Baku'),
    ('2101003', 'GL Biaya Gaji'),
    ('2101004', 'GL Biaya Sewa'),
    ('2101005', 'GL Biaya Listrik & Air'),
    ('2101009', 'GL Biaya Lain-lain');
$$;

create or replace function seed_gl_accounts(p_resto_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- `do nothing`, bukan `do update`: resto yang sudah menyetel
  -- nomornya sendiri tidak boleh dikembalikan ke bawaan hanya karena
  -- berkas ini dijalankan lagi. Yang diisi cuma yang belum ada.
  insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
  select p_resto_id, d.payment_method, d.gl_code, d.gl_name
  from _default_gl_accounts() d
  on conflict (resto_id, payment_method) do nothing;

  insert into expense_gl_accounts (resto_id, gl_code, gl_name)
  select p_resto_id, d.gl_code, d.gl_name
  from _default_expense_gl_accounts() d
  where not exists (
    select 1 from expense_gl_accounts e
    where e.resto_id = p_resto_id and e.gl_code = d.gl_code
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Resto baru langsung terisi
-- ─────────────────────────────────────────────────────────────────────
--
-- Lewat pemicu, bukan lewat aplikasi. Resto bisa dibuat dari layar Super
-- Admin, dari SQL saat memulihkan data, atau dari alat lain nanti — dan
-- yang lahir tanpa bagan akun akan diam-diam kehilangan jurnalnya.
create or replace function seed_gl_accounts_for_new_resto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform seed_gl_accounts(new.id);
  return new;
end;
$$;

drop trigger if exists trg_seed_gl_accounts on restaurants;
create trigger trg_seed_gl_accounts
  after insert on restaurants
  for each row execute function seed_gl_accounts_for_new_resto();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Resto yang sudah ada ikut dilengkapi
-- ─────────────────────────────────────────────────────────────────────
--
-- Hanya yang belum punya. Nomor yang sudah disetel Finance tetap seperti
-- adanya — lihat `do nothing` di atas.
do $$
declare
  r record;
begin
  for r in select id from restaurants loop
    perform seed_gl_accounts(r.id);
  end loop;
end $$;

commit;

-- Memeriksa hasilnya:
--
--   select r.name, count(g.*) as akun
--   from restaurants r
--   left join gl_accounts g on g.resto_id = r.id
--   group by r.name order by akun;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 21 dari 27 — gateway_account_super_admin.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pengenal sub-akun Xendit jadi urusan Super Admin saja.
--
-- Jalankan SETELAH resto_payment_accounts.sql. Aman diulang.
--
-- Sebelumnya Finance resto boleh membaca dan mengubah pengenal ini dari
-- Pengaturan Pembayaran. Itu keliru dari dua sisi.
--
-- Yang pertama: dia tidak punya cara mengetahui nilainya. Sub-akunnya
-- dibuat di akun Xendit milik KaataGo dan pengenalnya ditentukan
-- Xendit — bukan sesuatu yang bisa dicari orang resto di mana pun.
-- Kolom isian yang jawabannya tidak dimiliki siapa pun yang melihatnya
-- hanya mengundang tebakan.
--
-- Yang kedua, dan ini yang berbahaya: salah ketik satu huruf mengirim
-- seluruh pembayaran QRIS resto ini ke sub-akun resto lain. Uangnya
-- tidak hilang — tapi cair ke rekening orang lain, dan yang menemukan
-- selisihnya adalah kedua resto sekaligus, berhari-hari kemudian.
--
-- Batasnya ditegakkan di sini, bukan hanya dengan menyembunyikan
-- kolomnya di aplikasi: kolom yang disembunyikan cuma menghalangi orang
-- yang memakai aplikasinya.
--
-- Edge Function create-qris tetap bisa membacanya — dia memakai service
-- role, yang memang melewati RLS.

begin;

drop policy if exists "resto_payment_accounts: staff read" on resto_payment_accounts;
drop policy if exists "resto_payment_accounts: staff write" on resto_payment_accounts;

drop policy if exists "resto_payment_accounts: super_admin all" on resto_payment_accounts;
create policy "resto_payment_accounts: super_admin all" on resto_payment_accounts
  for all using (is_super_admin()) with check (is_super_admin());

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 22 dari 27 — announcement_audience.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pengumuman resto memilih sasarannya: karyawan, pelanggan,
-- atau keduanya.
--
-- Jalankan SETELAH announcement_categories.sql dan announcement_push.sql.
-- Aman dijalankan berulang kali.
--
-- Sebelumnya satu pengumuman resto pergi ke semua orang yang terkait
-- resto itu. Dua kebutuhan yang sangat berbeda terpaksa memakai jalur
-- yang sama: promo yang justru harus dibaca pelanggan, dan pengumuman
-- internal — jadwal shift, rapat, aturan baru dapur — yang tidak ada
-- urusannya dengan pelanggan dan sering tidak pantas dibaca mereka.
--
-- Tanpa pilihan, yang terjadi bisa ditebak: pengumuman internal berhenti
-- ditulis di sini dan pindah ke grup chat, lalu kotak masuknya kosong
-- dan tidak ada yang membukanya lagi.

begin;

alter table app_announcements
  add column if not exists audience text not null default 'all';

alter table app_announcements drop constraint if exists app_announcements_audience_check;
alter table app_announcements add constraint app_announcements_audience_check
  check (audience in ('employees', 'customers', 'all'));

-- Pengumuman lama tetap 'all' — itu memang perilakunya selama ini, dan
-- mengubahnya surut berarti menyembunyikan kabar yang sudah terlanjur
-- dibaca sebagian orang.

-- ─────────────────────────────────────────────────────────────────────
-- Notifikasinya ikut menyempit
-- ─────────────────────────────────────────────────────────────────────
--
-- Sasaran yang dipilih dititipkan ke antrean push, supaya Edge Function
-- tidak perlu membaca ulang barisnya. Nama audience-nya sendiri
-- ('all') sengaja tidak dipakai ulang untuk ini — itu jenis penerima
-- di antrean push, bukan sasaran pengumuman.
create or replace function queue_push_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into push_outbox (resto_id, event, payload) values (
    new.resto_id, 'announcement',
    jsonb_build_object(
      'audience', 'all',
      'target', coalesce(new.audience, 'all'),
      'title', new.title,
      'body', case
                when length(new.body) > 160
                  then left(new.body, 157) || '...'
                else new.body
              end
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_queue_push_announcement on app_announcements;
create trigger trg_queue_push_announcement
  after insert on app_announcements
  for each row execute function queue_push_announcement();

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 23 dari 27 — kasir_journal_read.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — kasir boleh melihat jurnal dari catatan yang dia buat.
--
-- Aman dijalankan berulang kali.
--
-- Layar Saldo & Pengeluaran memang sudah dibuka untuk kasir: dia
-- mencatat pengeluaran dari petty cash dan mengajukan top up, dan
-- keduanya terlihat di sana. Yang tertinggal cuma satu — mengetuk salah
-- satu catatan untuk melihat jurnalnya.
--
-- Karena hak bacanya berhenti di admin dan finance, jawabannya selalu
-- kosong, dan layarnya menyimpulkan yang paling masuk akal dari data
-- kosong: "akun GL-nya belum dipetakan". Kasir lalu mencari kesalahan
-- pemetaan yang tidak pernah ada, sementara di layar Finance jurnal yang
-- sama muncul lengkap.
--
-- Tidak ada yang baru yang terbuka: barisnya menjelaskan catatan yang
-- sudah boleh dia lihat isinya. Menulis tetap tertutup untuk semua peran
-- — seluruh baris jurnal ditulis oleh pemicu, tidak pernah oleh
-- aplikasi.

begin;

drop policy if exists "gl_journal_entries: finance/admin read" on gl_journal_entries;
drop policy if exists "gl_journal_entries: staff read" on gl_journal_entries;
create policy "gl_journal_entries: staff read" on gl_journal_entries
  for select using (
    is_resto_employee(resto_id, array['admin', 'finance', 'kasir'])
  );

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 24 dari 27 — cancel_order.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pelanggan boleh membatalkan pesanannya sendiri selama
-- pembayarannya belum diterima.
--
-- Jalankan SETELAH cash_payment_expiry.sql. Aman dijalankan berulang.
--
-- Sampai sekarang pesanan yang terlanjur dibuat cuma punya dua jalan
-- keluar: dibayar, atau menunggu tiga puluh menit sampai hangus
-- sendiri. Yang berubah pikiran satu menit setelah memesan tetap
-- terlihat di layar kasir dan di dapur selama setengah jam, dan yang
-- harus menjelaskannya adalah pramusaji.
--
-- Dibatalkan berbeda dari hangus, dan keduanya sengaja dibedakan:
-- 'expired' adalah pesanan yang ditinggalkan, 'cancelled' adalah
-- pesanan yang ditarik. Yang pertama pertanda pelanggan hilang, yang
-- kedua tidak — dan resto yang membaca angkanya nanti berhak tahu
-- bedanya.

begin;

alter table orders drop constraint if exists orders_payment_status_check;
alter table orders add constraint orders_payment_status_check
  check (payment_status in ('pending', 'paid', 'expired', 'cancelled'));

-- Lewat fungsi, bukan UPDATE langsung.
--
-- rls_hardening.sql menutup UPDATE pada orders untuk siapa pun selain
-- karyawan, dan itu benar: tanpa itu, siapa pun yang punya anon key
-- bisa menandai pesanan orang lain sudah dibayar. Pengaman
-- pembatalannya ditanam di dalam fungsi ini, bukan dengan membuka
-- kembali pintunya.
create or replace function cancel_my_order(
  p_order_id uuid,
  p_session_id text default null,
  p_email text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    return 'Pesanan tidak ditemukan.';
  end if;

  -- Miliknya sendiri. Pelanggan yang login dikenali dari emailnya, tamu
  -- dari session id yang tersimpan di HP-nya. Tanpa pemeriksaan ini,
  -- nomor pesanan yang terbaca dari struk orang lain sudah cukup untuk
  -- membatalkan pesanannya.
  if not (
    (p_email is not null and v_order.customer_label = p_email)
    or (p_session_id is not null and v_order.session_id = p_session_id)
  ) then
    return 'Pesanan ini bukan milikmu.';
  end if;

  if v_order.source <> 'customer' then
    return 'Pesanan yang diinput kasir dibatalkan lewat kasir.';
  end if;

  if v_order.payment_status = 'paid' then
    return 'Pesanan sudah dibayar. Hubungi kasir untuk pembatalan.';
  end if;

  if v_order.payment_status <> 'pending' then
    return 'Pesanan ini sudah tidak aktif.';
  end if;

  -- Dapur sudah mulai memasak berarti bahannya sudah terpakai.
  -- Membatalkannya sepihak dari HP memindahkan kerugiannya ke resto,
  -- dan yang menanggungnya bukan pihak yang membuat keputusannya.
  if v_order.kitchen_status <> 'waiting' then
    return 'Pesanan sudah mulai dimasak. Hubungi kasir kalau mau batal.';
  end if;

  update orders set payment_status = 'cancelled' where id = p_order_id;
  return null;
end;
$$;

grant execute on function cancel_my_order(uuid, text, text) to anon, authenticated;

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 25 dari 27 — settled_at_counter.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — menandai pesanan mandiri yang uangnya diterima di meja
-- kasir, alih-alih menebaknya dari cara bayarnya.
--
-- Aman dijalankan berulang kali.
--
-- Riwayat Kasir berisi dua hal: pesanan yang diinput kasir, dan pesanan
-- mandiri pelanggan yang dilunasi di meja kasir. Yang kedua sampai
-- sekarang dikenali dengan menebak — "cara bayarnya tunai berarti
-- dibayar di kasir".
--
-- Tebakan itu benar selama tunai adalah satu-satunya cara melunasi di
-- meja kasir. Sejak layar Pending Payment bisa mengganti cara bayar ke
-- QRIS atau transfer, tebakannya jadi salah: begitu kasir memilih
-- QRIS, cara bayarnya berubah, tebakannya tidak lagi cocok, dan
-- pesanannya menghilang dari Riwayat Kasir — padahal uangnya baru saja
-- diterima orang yang sedang berdiri di sana.
--
-- Uang yang masuk laci tapi tidak muncul di riwayat adalah selisih yang
-- ditemukan saat tutup shift, oleh orang yang tidak tahu sebabnya.
--
-- Yang ditambahkan di sini adalah catatan tegas: siapa yang menerima,
-- dan kapan. Tidak ada lagi yang perlu ditebak.

begin;

alter table orders add column if not exists settled_by text;
alter table orders add column if not exists settled_at timestamptz;

-- Baris lama tidak diisi surut.
--
-- Yang lama semuanya dilunasi tunai — satu-satunya cara yang ada saat
-- itu — jadi tebakan lamanya masih benar untuk mereka, dan aplikasi
-- tetap memakainya sebagai cadangan. Menuliskan nama penerima yang
-- tidak pernah tercatat justru mengarang riwayat.

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 26 dari 27 — discount_min_qty.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — diskon dengan syarat jumlah pembelian.
--
-- Jalankan SETELAH discounts.sql. Aman diulang.
--
-- "Beli 2 Mont Blanc diskon 30%" adalah bentuk promo yang paling sering
-- dipakai resto, dan sampai sekarang tidak bisa dinyatakan: aturan
-- diskon hanya menyebut menunya, tidak berapa banyak. Akibatnya promo
-- yang dimaksudkan untuk mendorong pembelian kedua ikut terpakai oleh
-- yang membeli satu — persis kebalikan dari maksudnya.
--
-- Bawaannya 1, jadi seluruh diskon yang sudah ada berlaku persis
-- seperti sebelumnya.

begin;

alter table discounts add column if not exists min_qty integer not null default 1;

-- Nol atau negatif tidak punya arti; yang dimaksud "tanpa syarat
-- jumlah" adalah 1.
alter table discounts drop constraint if exists discounts_min_qty_check;
alter table discounts add constraint discounts_min_qty_check
  check (min_qty >= 1);

commit;


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 27 dari 27 — discount_product_rules.sql
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — syarat jumlah menempel di tiap menu, bukan di promonya.
--
-- Jalankan SETELAH discounts.sql dan discount_min_qty.sql. Aman diulang.
--
-- min_qty menyimpan satu angka untuk seluruh promo, dan itu terlalu
-- longgar untuk bundling: promo "Nasi Goreng + Es Teh, beli 2" berlaku
-- untuk keranjang berisi dua Nasi Goreng dan segelas kopi. Paket yang
-- dijanjikan spanduknya tidak pernah benar-benar dibeli, tapi restonya
-- tetap membayar potongannya.
--
-- Sekarang tiap menu membawa syaratnya sendiri, dan seluruhnya harus
-- terpenuhi:
--
--   [{"product_id": "abc", "qty": 2, "mode": "exactly"},
--    {"product_id": "def", "qty": 1, "mode": "at_least"}]
--
-- 'exactly' untuk paket yang isinya sudah pasti — tiga ayam bukan lagi
-- paket "2 ayam + 1 nasi", dan kalau tetap diberi potongan, harga
-- paketnya tidak berarti apa-apa.

begin;

alter table discounts add column if not exists product_rules jsonb not null default '[]'::jsonb;

-- Promo yang sudah ada dipindahkan apa adanya: tiap menunya memakai
-- min_qty yang berlaku untuknya selama ini. Yang belum punya aturan
-- saja — supaya menjalankan ulang berkas ini tidak menimpa aturan yang
-- sudah disunting Admin.
update discounts
set product_rules = (
  select jsonb_agg(jsonb_build_object(
    'product_id', id,
    'qty', greatest(coalesce(min_qty, 1), 1),
    'mode', 'at_least'
  ))
  from jsonb_array_elements_text(product_ids) as t(id)
)
where basis = 'products'
  and jsonb_array_length(product_ids) > 0
  and jsonb_array_length(product_rules) = 0;

-- min_qty sengaja TIDAK dihapus. Aplikasi versi 1.45.3 masih
-- membacanya, dan kolom yang hilang membuat layar diskonnya gagal
-- memuat — bukan menampilkan promo tanpa syarat jumlah, tapi tidak
-- menampilkan apa-apa. Dibiarkan sampai versi itu tidak lagi terpasang.

commit;
