-- KaataGo - kasir melihat shiftnya sendiri, bukan shift orang lain.
--
-- Jalankan SETELAH cashier_shift.sql dan buka_shift_terkunci.sql.
-- Aman diulang.
--
-- Riwayat shift menyebut nama, jam buka, jam tutup, dan selisih setiap
-- orang yang pernah memegang laci. Untuk Owner dan Finance itu memang
-- gunanya. Untuk sesama kasir, itu catatan kinerja orang lain — siapa
-- yang lacinya pernah kurang, berapa, dan berapa kali — dan tidak ada
-- pekerjaan di meja kasir yang membutuhkannya.
--
-- Yang tetap dilihat kasir: shiftnya sendiri, seluruhnya, termasuk
-- selisihnya. Selisih yang hanya bisa dilihat atasannya adalah tuduhan
-- yang tidak bisa dijawab.
--
-- Satu hal yang harus tetap diketahui kasir tanpa melihat barisnya:
-- bahwa laci sedang dipegang orang lain. Tanpa itu, tombol Buka Shift
-- terpajang, ditekan, lalu ditolak server dengan kalimat yang terbaca
-- sebagai kesalahan aplikasi. Itu dijawab fungsi di bawah, yang
-- menjawab "ada" atau "tidak ada" — tanpa menyebut siapa.

begin;

drop policy if exists "cashier_shifts: read" on cashier_shifts;
create policy "cashier_shifts: read" on cashier_shifts
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin'])
    or (
      is_resto_employee(resto_id, array['kasir'])
      and lower(coalesce(employee_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  );

commit;

-- Selisih kasir mengikuti aturan yang sama, dan alasannya lebih tajam:
-- daftar ini adalah daftar orang yang lacinya pernah kurang, berikut
-- nominalnya. Kasir melihat tanggungannya sendiri — yang memang harus
-- dilihatnya, karena ia yang melunasi.

begin;

drop policy if exists "cash_variances: read" on cash_variances;
create policy "cash_variances: read" on cash_variances
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin'])
    or (
      is_resto_employee(resto_id, array['kasir'])
      and lower(coalesce(employee_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Ada yang sedang memegang laci?
-- ─────────────────────────────────────────────────────────────────────
--
-- Dipakai layar Shift Kasir untuk memutuskan menawarkan tombol Buka
-- Shift atau tidak. Jawabannya sengaja sesempit mungkin: ada atau tidak,
-- dan apakah itu shift orang yang sedang bertanya. Nama pemegangnya
-- tidak ikut — kalau ikut, seluruh pembatasan di atas jadi percuma.

begin;

create or replace function shift_terbuka_ringkas(p_resto_id text)
returns table (ada boolean, milik_saya boolean)
language sql
stable
security definer
set search_path = public
as $fn$
  select
    exists (
      select 1 from cashier_shifts s
      where s.resto_id = p_resto_id and s.closed_at is null
    ),
    exists (
      select 1 from cashier_shifts s
      where s.resto_id = p_resto_id
        and s.closed_at is null
        and lower(coalesce(s.employee_email, ''))
            = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  where is_super_admin()
     or is_resto_employee(p_resto_id,
          array['owner', 'finance', 'admin', 'kasir']);
$fn$;

revoke all on function shift_terbuka_ringkas(text) from public, anon;
grant execute on function shift_terbuka_ringkas(text) to authenticated;

commit;
