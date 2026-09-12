-- KaataGo - parameter akses menu per resto, per peran.
--
-- Jalankan kapan saja setelah employees ada. Aman diulang.
--
-- Sampai sekarang peran menentukan segalanya: setiap kasir di setiap
-- merchant melihat menu yang sama persis. Padahal merchantnya tidak
-- sama — ada yang kasirnya memang mencatat pengeluaran, ada yang
-- kasirnya hanya melayani dan tidak boleh menyentuh apa pun selain
-- pesanan.
--
-- Tabel ini menjawab itu: KaataGo Admin menentukan, per resto dan per
-- peran, menu mana yang muncul dan apakah isinya boleh diubah.
--
-- ── Yang TIDAK dilakukan tabel ini ────────────────────────────────────
--
-- Ia tidak memberi hak. RLS tetap lantai keamanannya, dan tidak satu
-- baris pun di sini menyentuhnya. Akibatnya satu arah dan disengaja:
-- parameter ini hanya bisa MEMPERSEMPIT apa yang sudah boleh dilakukan
-- sebuah peran, tidak pernah melebarkan. Memberi kasir menu Mapping GL
-- lewat tabel ini tidak membuat servernya mengizinkan apa pun — yang
-- terjadi cuma layar yang terbuka lalu ditolak.
--
-- Karena itu juga: baris yang TIDAK ADA berarti akses penuh. Merchant
-- yang belum pernah disentuh KaataGo Admin berjalan persis seperti
-- sebelumnya, dan tidak ada satu pun orang yang kehilangan menunya
-- karena fitur ini dipasang.

begin;

create table if not exists menu_access (
  resto_id text not null references restaurants (id) on delete cascade,

  -- 'owner' | 'admin' | 'finance' | 'kasir' | 'chef'
  --
  -- Super Admin sengaja tidak bisa diatur di sini. Ia yang mengatur;
  -- peran yang bisa mengunci dirinya sendiri dari layar pengaturannya
  -- adalah pintu yang kuncinya tertinggal di dalam.
  role text not null,

  -- Nama menunya, apa adanya seperti yang tertulis di aplikasi.
  menu_key text not null,

  -- 'none' | 'view' | 'edit'
  level text not null default 'edit',

  updated_by text,
  updated_at timestamptz not null default now(),

  primary key (resto_id, role, menu_key)
);

alter table menu_access drop constraint if exists menu_access_role_check;
alter table menu_access add constraint menu_access_role_check
  check (role in ('owner', 'admin', 'finance', 'kasir', 'chef'));

alter table menu_access drop constraint if exists menu_access_level_check;
alter table menu_access add constraint menu_access_level_check
  check (level in ('none', 'view', 'edit'));

commit;

begin;

alter table menu_access enable row level security;

-- Dibaca pegawai merchantnya sendiri. Harus: aplikasi di tangan kasir
-- perlu tahu menu apa yang boleh muncul untuknya, dan yang menanyakannya
-- adalah perangkat orang itu.
drop policy if exists "menu_access: staff read" on menu_access;
create policy "menu_access: staff read" on menu_access
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id,
         array['owner', 'admin', 'finance', 'kasir', 'chef'])
  );

-- Ditulis KaataGo Admin saja. Kalau Owner bisa mengaturnya sendiri,
-- parameter ini berhenti jadi parameter dan jadi sekadar preferensi —
-- dan yang dibatasi bisa membatalkan pembatasannya.
drop policy if exists "menu_access: super admin write" on menu_access;
create policy "menu_access: super admin write" on menu_access
  for all using (is_super_admin()) with check (is_super_admin());

commit;
