-- KaataGo - KaataGo Admin bisa membuka berkas di ember `absensi`.
--
-- Jalankan SETELAH absensi_payroll.sql. Aman diulang.
--
-- ── Apa yang keliru ──────────────────────────────────────────────────
--
-- Kebijakan baca ember ini cuma menanyakan `is_resto_employee(...)`.
-- KaataGo Admin bukan karyawan resto mana pun — dia yang mengurus
-- semuanya dari luar — jadi jawabannya selalu tidak.
--
-- Akibatnya jatuh persis di tempat yang paling salah: bukti transfer
-- langganan diunggah ke ember ini, dan yang wajib memeriksanya sebelum
-- menyetujui pembayaran adalah KaataGo Admin. Yang dia lihat "Gagal
-- dimuat", dan satu-satunya jalan yang tersisa menyetujui pembayaran
-- tanpa pernah melihat buktinya.
--
-- Kebijakan tulis dan ubah sengaja TIDAK diubah. KaataGo Admin tidak
-- perlu menaruh atau menimpa berkas di ember milik merchant, dan hak
-- yang tidak dibutuhkan sebaiknya tidak ada.
--
-- ── Sebatas map bukti transfer, bukan seluruh ember ──────────────────
--
-- Ember ini menyimpan dua hal yang sangat berbeda. Bukti transfer, yang
-- memang urusan KaataGo Admin. Dan foto wajah karyawan berikut surat
-- keterangan sakitnya, yang sama sekali bukan.
--
-- Jalurnya sudah memisahkan keduanya sejak awal: bukti transfer selalu
-- `<resto>/langganan/...`, sedangkan foto absen dan surat sakit ada di
-- map lain. Jadi haknya diikat ke map itu.
--
-- Membuka seluruh ember memang lebih ringkas ditulis, dan akibatnya
-- pengelola KaataGo bisa membuka wajah tiap karyawan tiap merchant
-- tanpa satu pun dari mereka tahu. Tidak ada yang membutuhkan itu untuk
-- menyetujui pembayaran.

begin;

drop policy if exists "absensi: baca atasan" on storage.objects;
create policy "absensi: baca atasan" on storage.objects
  for select using (
    bucket_id = 'absensi'
    and (
      -- Disebut lengkap dengan skemanya. Policy pada storage.objects
      -- tidak dijalankan PostgREST melainkan layanan Storage, yang
      -- menyambung dengan search_path-nya sendiri — dan nama tanpa
      -- skema di sana bisa tidak ditemukan. Galatnya baru muncul saat
      -- seseorang benar-benar membuka gambarnya, bukan saat policy-nya
      -- dibuat.
      (public.is_super_admin()
        and (storage.foldername(name))[2] = 'langganan')
      or public.is_resto_employee((storage.foldername(name))[1],
           array['owner', 'admin', 'finance'])
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select policyname, coalesce(qual, with_check)
--   from pg_policies
--   where schemaname = 'storage' and tablename = 'objects'
--     and policyname like 'absensi%';
--
-- Yang benar: kebijakan SELECT menyebut is_super_admin() BERIKUT
-- syarat map 'langganan'-nya, dan dua kebijakan lainnya tidak menyebut
-- is_super_admin() sama sekali.
