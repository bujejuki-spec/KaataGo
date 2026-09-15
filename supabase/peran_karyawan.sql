-- KaataGo - daftar peran karyawan berdiri di satu tempat.
--
-- Jalankan SEBELUM wajah_facenet.sql, wajah_pratinjau.sql, peran_hr.sql,
-- dan hentikan_langganan.sql — keempatnya memanggil fungsi ini. Aman
-- diulang.
--
-- ── Kenapa berdiri sendiri ───────────────────────────────────────────
--
-- Fungsi-fungsi absensi menyebut daftar peran yang sama berulang kali:
-- _absen(), daftar_wajah(), cocokkan_wajah(), keadaan_langganan().
-- Diketik ulang di tiap tempat, menambah satu peran berarti menemukan
-- semuanya — dan yang terlewat tidak pernah berbunyi. Ia cuma berarti
-- peran baru itu tidak bisa absen, ketahuan berminggu-minggu kemudian
-- dari orangnya sendiri.
--
-- ── Kenapa berkasnya terpisah, bukan ikut peran_hr.sql ───────────────
--
-- Karena berkas yang mendefinisikannya harus berjalan LEBIH DULU
-- daripada semua yang memakainya, dan peran_hr.sql berdiri di tengah
-- urutan. Menaruhnya di sana membuat berkas sebelumnya memanggil
-- fungsi yang belum ada — galat yang saya buat sendiri, dan yang
-- menemukannya bukan tes melainkan orang yang menjalankan query-nya.

begin;

create or replace function peran_karyawan()
returns text[]
language sql
immutable
as $$
  select array['owner', 'admin', 'finance', 'kasir', 'chef', 'hr'];
$$;

revoke all on function peran_karyawan() from public, anon;
grant execute on function peran_karyawan() to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select peran_karyawan();
--
-- Yang benar: enam peran, termasuk 'hr'.
