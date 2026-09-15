-- KaataGo - peran HR.
--
-- Jalankan SETELAH peran_karyawan.sql. Aman diulang.
--
-- ── Apa yang ditambahkan ─────────────────────────────────────────────
--
-- Satu peran baru yang mengurus orang, bukan uang dan bukan dapur:
-- Kelola Karyawan, Absensi (miliknya sendiri), dan Absensi Karyawan.
--
-- ── Yang SENGAJA tidak diberikan ─────────────────────────────────────
--
-- HR tidak menyentuh gaji. Tidak `payroll_settings`, tidak
-- `employee_payroll`, tidak rekap payroll — itu tetap milik Owner dan
-- Finance.
--
-- Godaannya besar, karena absensi dan payroll memang berdampingan di
-- satu layar dan orang yang mengurus kehadiran terasa "seharusnya" juga
-- mengurus gaji. Tapi keduanya dipisah justru supaya yang mencatat
-- kehadiran bukan orang yang sama dengan yang menentukan bayarannya.
-- Memberi keduanya ke satu orang berarti dia bisa menandai seorang
-- rekan alpa lalu memotong gajinya, sendirian, tanpa satu pun mata
-- kedua.
--
-- Kalau suatu hari HR memang harus memegang payroll, itu keputusan
-- tersendiri yang pantas ditimbang lagi — bukan sesuatu yang ikut
-- terbawa karena berkas ini kebetulan mengubah daftar peran.
--
-- ── Kenapa daftarnya ditulis ulang, bukan ditambahi ──────────────────
--
-- Tiap kebijakan di bawah dibuang lalu dibuat ulang dengan daftar
-- lengkapnya. Menambahkan peran ke policy yang sudah ada tidak bisa
-- dilakukan sepotong di Postgres, dan menulis setengahnya menghasilkan
-- kebijakan yang kehilangan peran lama — yang berarti Admin kehilangan
-- aksesnya diam-diam pada hari berkas ini dijalankan.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. 'hr' jadi peran yang sah
-- ─────────────────────────────────────────────────────────────────────

alter table employees drop constraint if exists employees_role_check;
alter table employees add constraint employees_role_check
  check (role in ('admin', 'kasir', 'chef', 'super_admin', 'finance',
                 'owner', 'hr'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Kelola Karyawan
-- ─────────────────────────────────────────────────────────────────────

begin;

drop policy if exists "employees: read own, resto admin, or super_admin"
  on employees;
create policy "employees: read own, resto admin, or super_admin" on employees
  for select using (
    email = auth.jwt() ->> 'email'
    or is_super_admin()
    or (resto_id is not null
        and is_resto_employee(resto_id, array['admin', 'hr']))
  );

drop policy if exists "employees: admin or super_admin insert" on employees;
create policy "employees: admin or super_admin insert" on employees
  for insert with check (
    is_super_admin()
    or (resto_id is not null
        and is_resto_employee(resto_id, array['admin', 'hr']))
  );

drop policy if exists "employees: admin or super_admin update" on employees;
create policy "employees: admin or super_admin update" on employees
  for update using (
    is_super_admin()
    or (resto_id is not null
        and is_resto_employee(resto_id, array['admin', 'hr']))
  );

drop policy if exists "employees: admin or super_admin delete" on employees;
create policy "employees: admin or super_admin delete" on employees
  for delete using (
    is_super_admin()
    or (resto_id is not null
        and is_resto_employee(resto_id, array['admin', 'hr']))
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Absensi karyawan
-- ─────────────────────────────────────────────────────────────────────

begin;

drop policy if exists "attendance: read" on attendance;
create policy "attendance: read" on attendance
  for select using (
    is_super_admin()
    or lower(employee_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance', 'hr'])
  );

drop policy if exists "attendance: atasan ubah" on attendance;
create policy "attendance: atasan ubah" on attendance
  for update using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance', 'hr'])
  );

-- Setelan absensi ikut terbaca: radiusnya dipakai layar absensi untuk
-- menjelaskan kenapa seseorang ditolak, dan tanggal gajiannya menentukan
-- periode mana yang ditampilkan di Absensi Karyawan.
drop policy if exists "payroll_settings: baca" on payroll_settings;
create policy "payroll_settings: baca" on payroll_settings
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id,
         array['owner', 'admin', 'finance', 'kasir', 'chef', 'hr'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Foto absensi
-- ─────────────────────────────────────────────────────────────────────

begin;

drop policy if exists "absensi: baca atasan" on storage.objects;
create policy "absensi: baca atasan" on storage.objects
  for select using (
    bucket_id = 'absensi'
    and (
      (public.is_super_admin()
        and (storage.foldername(name))[2] = 'langganan')
      or public.is_resto_employee((storage.foldername(name))[1],
           array['owner', 'admin', 'finance', 'hr'])
    )
  );

-- HR ikut menaruh berkas, karena dia juga absen seperti karyawan lain.
drop policy if exists "absensi: tulis karyawan" on storage.objects;
create policy "absensi: tulis karyawan" on storage.objects
  for insert with check (
    bucket_id = 'absensi'
    and public.is_resto_employee((storage.foldername(name))[1],
          array['owner', 'admin', 'finance', 'kasir', 'chef', 'hr'])
  );

drop policy if exists "absensi: ubah karyawan" on storage.objects;
create policy "absensi: ubah karyawan" on storage.objects
  for update using (
    bucket_id = 'absensi'
    and public.is_resto_employee((storage.foldername(name))[1],
          array['owner', 'admin', 'finance', 'kasir', 'chef', 'hr'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 5. HR ikut absen, dan ikut mereset wajah
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Daftar peran di dalam fungsi-fungsi absensi ditulis ulang. Yang
-- diubah cuma daftarnya; sisanya persis seperti di wajah_facenet.sql
-- dan wajah_pratinjau.sql.
create or replace function reset_wajah(p_resto_id text, p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- Yang boleh menghapus wajah orang lain: yang memang mengurus orang.
  --
  -- Wajah yang bisa direset siapa saja adalah wajah yang bisa
  -- dipindahkan diam-diam ke orang lain — dan sesudah dipindahkan,
  -- absennya tetap terlihat sah.
  if not (is_super_admin()
          or is_resto_employee(p_resto_id,
               array['owner', 'admin', 'finance', 'hr'])) then
    raise exception 'Cuma Owner, Admin, Finance, atau HR yang bisa '
                    'mereset wajah karyawan.';
  end if;

  -- Hitungannya dibawa ke baris berikutnya lewat tabel terpisah supaya
  -- tidak hilang saat barisnya dihapus. Reset yang sering pada satu
  -- orang adalah pola yang pantas dilihat.
  insert into employee_face_resets (resto_id, employee_email, oleh)
  values (p_resto_id, lower(p_email), auth.jwt() ->> 'email');

  delete from employee_faces
  where resto_id = p_resto_id and lower(employee_email) = lower(p_email);
end;
$fn$;

revoke all on function reset_wajah(text, text) from public, anon;
grant execute on function reset_wajah(text, text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 6. Foto acuan ikut terbuka untuk HR
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function foto_acuan_wajah(p_resto_id text)
returns table (employee_email text, foto_url text, registered_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select f.employee_email, f.foto_url, f.registered_at
  from employee_faces f
  where f.resto_id = p_resto_id
    and (is_super_admin()
         or is_resto_employee(p_resto_id,
              array['owner', 'admin', 'finance', 'hr'])
         or lower(f.employee_email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

grant execute on function foto_acuan_wajah(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. 'hr' sah sebagai peran:
--
--      select pg_get_constraintdef(oid) from pg_constraint
--      where conname = 'employees_role_check';
--
-- 2. HR ada di empat kebijakan employees, dua kebijakan attendance, dan
--    tiga kebijakan ember absensi:
--
--      select tablename, policyname, cmd
--      from pg_policies
--      where coalesce(qual, with_check) like '%hr%'
--      order by tablename, cmd;
--
-- 3. HR TIDAK ada di payroll. Yang keluar harus kosong:
--
--      select policyname from pg_policies
--      where tablename in ('employee_payroll')
--        and coalesce(qual, with_check) like '%''hr''%';
