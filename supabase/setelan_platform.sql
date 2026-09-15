-- KaataGo - setelan milik KaataGo sendiri, bukan milik merchant.
--
-- Jalankan kapan saja. Aman diulang.
--
-- ── Untuk apa ────────────────────────────────────────────────────────
--
-- Tautan situs KaataGo di layar Tentang KaataGo dulu ditulis mati di
-- dalam APK. Mengganti alamatnya — pindah domain, pindah hosting —
-- berarti merilis APK baru, dan HP yang belum memperbarui tetap
-- membuka alamat lama selamanya. Justru HP-HP itulah yang paling perlu
-- diarahkan ke tempat yang benar.
--
-- ── Kenapa bukan tabel `settings` ────────────────────────────────────
--
-- `settings` adalah setelan pembayaran PER MERCHANT — satu baris per
-- resto, dijaga Admin dan Finance resto itu. Tautan situs KaataGo bukan
-- milik merchant mana pun, dan menaruhnya di sana berarti memilih satu
-- resto secara acak untuk menampungnya.
--
-- ── Siapa yang boleh apa ─────────────────────────────────────────────
--
-- Baca: siapa pun, termasuk yang belum login. Layar Tentang KaataGo
-- bisa dibuka dari halaman login, dan yang membukanya sering justru
-- orang yang belum punya akun.
--
-- Ubah: KaataGo Admin saja. Tautan yang bisa diubah merchant adalah
-- tautan yang bisa diarahkan ke halaman palsu yang meminta kata sandi —
-- dari dalam aplikasi resmi, dengan kepercayaan penuh pembacanya.

begin;

create table if not exists setelan_platform (
  kunci text primary key,
  nilai text not null,
  updated_at timestamptz not null default now(),
  updated_by text
);

-- Tautan harus https.
--
-- Diperiksa di basis data, bukan cuma di layar editornya: tautan
-- `http://` atau `javascript:` yang lolos ke sini dibuka apa adanya oleh
-- setiap HP yang membaca layar Tentang.
alter table setelan_platform drop constraint if exists setelan_platform_tautan_https;
alter table setelan_platform add constraint setelan_platform_tautan_https
  check (kunci not like 'tautan_%' or nilai ~ '^https://[^\s]+$');

alter table setelan_platform enable row level security;

drop policy if exists "setelan_platform: baca" on setelan_platform;
create policy "setelan_platform: baca" on setelan_platform
  for select using (true);

drop policy if exists "setelan_platform: super admin ubah" on setelan_platform;
create policy "setelan_platform: super admin ubah" on setelan_platform
  for all using (is_super_admin()) with check (is_super_admin());

grant select on setelan_platform to anon, authenticated;
grant insert, update, delete on setelan_platform to authenticated;

-- Nilai awalnya alamat yang sekarang tertulis di APK, supaya memasang
-- berkas ini tidak mengubah apa pun yang dilihat orang.
insert into setelan_platform (kunci, nilai)
values ('tautan_situs', 'https://bujejuki-spec.github.io/KaataGo-LandingPage/')
on conflict (kunci) do nothing;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from setelan_platform;
--
-- Dan dari luar, sebagai pengunjung yang belum login:
--
--   curl -s 'https://xizpwtycczigjhzxegen.supabase.co/rest/v1/setelan_platform?kunci=eq.tautan_situs' \
--     -H 'apikey: <anon key>'
