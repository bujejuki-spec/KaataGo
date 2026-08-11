-- KaataGo — peran Owner + satu orang mengelola banyak resto
-- (jalankan SETELAH semua migrasi sebelumnya; ini satu-satunya yang
-- perlu dijalankan untuk rilis ini).
--
-- Tiga hal sekaligus:
--
--   1. Peran baru 'owner' yang memegang semua menu Chef, Kasir, Admin,
--      dan Finance.
--   2. Satu email boleh terdaftar di lebih dari satu resto. Sebelumnya
--      `employees.email` adalah kunci utama, jadi satu orang hanya bisa
--      menjadi karyawan di satu tempat — pemilik dua cabang terpaksa
--      punya dua alamat email.
--   3. Owner otomatis lolos setiap pemeriksaan peran, tanpa perlu
--      menyebutkan 'owner' di puluhan policy satu per satu.
--
-- Aman dijalankan berulang kali.

begin;

-- ── 1. Peran owner ───────────────────────────────────────────────────
alter table employees drop constraint if exists employees_role_check;
alter table employees add constraint employees_role_check
  check (role in ('admin', 'kasir', 'chef', 'super_admin', 'finance', 'owner'));

-- ── 2. Satu email, banyak resto ──────────────────────────────────────
-- Kunci utamanya berpindah dari email saja ke pasangan (email, resto_id):
-- keanggotaan seseorang memang melekat pada restonya, bukan pada dirinya
-- semata. Baris yang sudah ada tidak tersentuh — masing-masing tetap sah
-- sebagai satu pasangan.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'employees'::regclass
      and contype = 'p'
      and conname = 'employees_pkey'
      and (select count(*) from unnest(conkey)) = 1
  ) then
    alter table employees drop constraint employees_pkey;
    alter table employees add constraint employees_pkey primary key (email, resto_id);
  end if;
end $$;

-- Pencarian karyawan selalu lewat email, dan sekarang bisa mengembalikan
-- beberapa baris sekaligus.
create index if not exists idx_employees_email on employees(email);

-- ── 3. Owner lolos setiap pemeriksaan peran ──────────────────────────
-- Diletakkan di dalam is_resto_employee, bukan disebar ke tiap policy.
-- Menambahkan 'owner' ke puluhan array peran berarti setiap policy baru
-- di masa depan berpeluang lupa menyertakannya — dan lupa di sini
-- bentuknya adalah Owner yang tiba-tiba kehilangan akses ke satu layar
-- tanpa sebab yang jelas.
create or replace function is_resto_employee(
  p_resto_id text,
  p_roles text[] default array['admin','kasir','chef']
)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from employees e
    where e.email = auth.jwt()->>'email'
      and e.resto_id = p_resto_id
      and e.active = true
      and (e.role = any(p_roles) or e.role = 'owner')
  );
$$;

-- ── 4. Policy `employees` tidak perlu disentuh ───────────────────────
-- Aturan yang ada (lihat super_admin.sql) sudah mengizinkan seseorang
-- membaca barisnya sendiri — itulah yang dipakai aplikasi untuk mengetahui
-- resto mana saja yang dia pegang — serta memberi admin dan super_admin
-- hak mengelola. Owner ikut lolos lewat perubahan is_resto_employee di
-- atas, jadi menambah policy baru di sini hanya akan menduplikasi aturan
-- yang sudah benar.

commit;
