-- KaataGo — perbaiki penolakan RLS saat perangkat mendaftarkan tokennya.
--
-- Gejalanya: aplikasi mendapat token FCM, tapi menyimpannya ditolak
-- dengan 42501 "new row violates row-level security policy for table
-- device_tokens" — jadi tabelnya tetap kosong dan tidak ada notifikasi
-- yang bisa dikirim ke mana pun.
--
-- Aman dijalankan berulang kali.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Lihat dulu keadaannya sekarang
-- ─────────────────────────────────────────────────────────────────────
-- Jalankan bagian ini sendiri kalau ingin tahu sebabnya. Kalau hasilnya
-- kosong, berarti kebijakannya memang tidak pernah terbentuk; kalau ada
-- tapi kolom roles-nya bukan {public} atau memuat anon/authenticated,
-- berarti terbentuk untuk peran yang salah.
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'device_tokens';

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Hak akses tabelnya
-- ─────────────────────────────────────────────────────────────────────
-- RLS menyaring baris, tapi hak akses tabel yang menentukan boleh
-- tidaknya perintahnya dijalankan sama sekali. Keduanya harus ada, dan
-- yang kedua ini mudah terlewat karena tabel yang dibuat lewat SQL
-- Editor tidak selalu mewarisi hak bawaan Supabase.
grant select, insert, update, delete on table device_tokens to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Kebijakannya, ditulis ulang secara tegas
-- ─────────────────────────────────────────────────────────────────────
-- Perannya disebut tegas (to anon, authenticated), tidak lagi
-- mengandalkan bawaan "public". Pelanggan tamu memakai anon, karyawan
-- yang login memakai authenticated — dan keduanya harus bisa
-- mendaftarkan perangkatnya.
alter table device_tokens enable row level security;

drop policy if exists "device_tokens: public upsert" on device_tokens;
drop policy if exists "device_tokens: update own" on device_tokens;
drop policy if exists "device_tokens: delete own" on device_tokens;
drop policy if exists "device_tokens: insert" on device_tokens;
drop policy if exists "device_tokens: update" on device_tokens;
drop policy if exists "device_tokens: delete" on device_tokens;

create policy "device_tokens: insert" on device_tokens
  for insert to anon, authenticated
  with check (true);

-- UPDATE ikut dibuka karena pendaftarannya berupa upsert: token yang
-- sama didaftarkan ulang tiap kali pemiliknya berganti atau restonya
-- ditukar. Tanpa kebijakan UPDATE, pendaftaran kedua dan seterusnya
-- ditolak — dan itu justru yang paling sering terjadi.
create policy "device_tokens: update" on device_tokens
  for update to anon, authenticated
  using (true) with check (true);

create policy "device_tokens: delete" on device_tokens
  for delete to anon, authenticated
  using (true);

-- Membaca daftarnya tetap tertutup untuk aplikasi. Daftar token adalah
-- daftar "ke mana notifikasi bisa dikirim", dan tidak ada layar yang
-- perlu melihatnya. Edge Function membacanya dengan service role, yang
-- melewati RLS.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Bukti bahwa sudah bisa ditulis
-- ─────────────────────────────────────────────────────────────────────
-- Bukan pengganti pengujian dari HP — ini berjalan sebagai postgres,
-- yang melewati RLS. Yang benar-benar membuktikan adalah membuka Tes
-- Notifikasi di aplikasi setelah menjalankan berkas ini.
select count(*) as jumlah_perangkat_terdaftar from device_tokens;
