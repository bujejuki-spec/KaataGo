-- KaataGo - daftar paket yang boleh dibaca tanpa login.
--
-- Jalankan SETELAH paket_langganan.sql. Aman diulang.
--
-- ── Untuk apa ────────────────────────────────────────────────────────
--
-- Landing page menampilkan harga paket. Kalau harganya diketik ulang di
-- HTML, ia akan benar hari ini dan diam-diam keliru pada hari KaataGo
-- Admin menaikkannya — dan yang menemukannya adalah calon merchant yang
-- membaca satu angka di web lalu melihat angka lain di aplikasi.
--
-- Jadi halamannya membaca dari sini.
--
-- ── Kenapa fungsi, bukan melonggarkan kebijakan tabelnya ─────────────
--
-- Kebijakan `paket: baca` menuntut `auth.uid() is not null`, dan
-- pengunjung landing page memang tidak login. Menurunkan syarat itu
-- jadi `true` memang membuat halamannya jalan — sekaligus membuka
-- SELURUH baris tabelnya ke internet, termasuk `updated_by` yang berisi
-- alamat surel orang yang terakhir mengubah harga.
--
-- Fungsi ini membuka persis lima kolom yang memang untuk dipajang, dan
-- tidak satu pun yang lain.

begin;

create or replace function paket_publik()
returns table (
  kode text,
  nama text,
  keterangan text,
  harga_bulanan bigint,
  urutan integer
)
language sql
stable
security definer
set search_path = public
as $$
  select p.kode, p.nama, p.keterangan, p.harga_bulanan, p.urutan
  from paket_langganan p
  order by p.urutan, p.harga_bulanan;
$$;

-- `anon` memang disengaja: itulah peran pengunjung yang belum login,
-- dan halaman harga tanpa login adalah seluruh gunanya fungsi ini.
grant execute on function paket_publik() to anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from paket_publik();
--
-- Dan dari luar, sebagai pengunjung yang belum login — ini yang
-- benar-benar dipakai landing page:
--
--   curl -s -X POST \
--     'https://xizpwtycczigjhzxegen.supabase.co/rest/v1/rpc/paket_publik' \
--     -H 'apikey: <anon key>' -H 'Content-Type: application/json' -d '{}'
--
-- Yang keluar harus dua baris tanpa satu pun kolom `updated_by`.
