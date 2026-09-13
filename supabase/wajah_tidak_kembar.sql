-- KaataGo - wajah yang didaftarkan tidak boleh kembar dengan rekannya.
--
-- Jalankan SETELAH absensi_payroll.sql. Aman diulang.
--
-- ── Kegagalan yang perlu ditutup ─────────────────────────────────────
--
-- Ada dua cara pengenal wajah bisa salah, dan keduanya sangat berbeda
-- akibatnya.
--
-- Yang MENOLAK semua orang langsung ketahuan: pagi pertama, tidak ada
-- satu pun yang bisa absen, dan telepon berdering sebelum jam sembilan.
--
-- Yang MENERIMA semua orang tidak pernah ketahuan. Absensinya terisi
-- rapi tiap hari, tidak ada yang mengeluh, dan gaji dihitung dari
-- catatan yang sebetulnya tidak membuktikan apa pun. Baru terlihat saat
-- ada sengketa — dan waktu itu sudah berbulan-bulan lewat.
--
-- Sebabnya bisa model yang kualitasnya buruk, model yang tertukar, atau
-- model yang menghasilkan sidik nyaris seragam untuk gambar apa pun.
-- Tidak satu pun bisa dilihat dari membaca berkasnya.
--
-- ── Penjaganya ───────────────────────────────────────────────────────
--
-- Saat mendaftarkan wajah, sidiknya dibandingkan dengan wajah karyawan
-- lain di merchant yang sama. Kalau terlalu mirip dengan salah satunya,
-- pendaftarannya ditolak.
--
-- Satu penjaga, dua gunanya:
--
--   1. Karyawan yang mendaftarkan wajah rekannya — sengaja atau karena
--      ponselnya dipegang orang lain — tertolak.
--   2. Model yang menghasilkan sidik seragam gagal di pendaftaran
--      KEDUA, bukan diam-diam meloloskan absen selamanya. Kegagalan
--      yang tidak terlihat berubah jadi kegagalan yang berbunyi.
--
-- Ambangnya lebih longgar daripada ambang absen. Menolak absen orang
-- yang wajahnya memang sedang berbeda cuma menyuruhnya mengulang;
-- menolak pendaftaran orang yang wajahnya kebetulan mirip saudaranya
-- mengunci dia dari fiturnya sampai ada yang turun tangan.

begin;

create or replace function _ambang_kembar()
returns double precision language sql immutable as
$$ select 0.90::double precision $$;

revoke all on function _ambang_kembar() from public, anon;

create or replace function daftar_wajah(
  p_resto_id text,
  p_embedding double precision[],
  p_model text default 'mobilefacenet-192',
  p_foto_url text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_kembar record;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       array['owner', 'admin', 'finance', 'kasir', 'chef']) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  if p_embedding is null or array_length(p_embedding, 1) is null then
    raise exception 'Sidik wajahnya kosong. Ulangi pemindaian.';
  end if;

  if exists (select 1 from employee_faces
             where resto_id = p_resto_id
               and lower(employee_email) = lower(v_email)) then
    raise exception 'Wajahmu sudah terdaftar. Minta Owner atau Admin '
                    'mereset dulu kalau memang perlu didaftar ulang.';
  end if;

  -- Dibandingkan dengan rekan satu merchant, dan yang paling mirip yang
  -- dilaporkan. Hanya sidik dari model yang sama yang dibandingkan:
  -- sidik dari dua model berbeda memang tidak sebanding, dan
  -- membandingkannya menghasilkan penolakan yang tidak bisa dijelaskan.
  select employee_email,
         _mirip_wajah(embedding, p_embedding) as skor
    into v_kembar
  from employee_faces
  where resto_id = p_resto_id
    and model = coalesce(p_model, 'mobilefacenet-192')
  order by _mirip_wajah(embedding, p_embedding) desc
  limit 1;

  if v_kembar.employee_email is not null
     and v_kembar.skor >= _ambang_kembar() then
    -- Emailnya TIDAK disebut. Yang mendaftar tidak perlu tahu wajah
    -- siapa yang mirip dengannya, dan menyebutkannya membocorkan siapa
    -- saja yang sudah terdaftar kepada siapa pun yang mau memancingnya.
    raise exception 'Wajah ini terlalu mirip dengan karyawan lain yang '
                    'sudah terdaftar. Minta Owner atau Admin memeriksanya.';
  end if;

  insert into employee_faces (
    resto_id, employee_email, embedding, model, foto_url)
  values (p_resto_id, lower(v_email), p_embedding,
          coalesce(p_model, 'mobilefacenet-192'), p_foto_url);
end;
$fn$;

revoke all on function daftar_wajah(text, double precision[], text, text)
  from public, anon;
grant execute on function daftar_wajah(text, double precision[], text, text)
  to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
-- Sesudah dua orang mendaftar, kemiripan antarwajah di satu merchant
-- seharusnya jauh di bawah ambangnya. Yang mendekati 1 untuk semua
-- pasangan berarti modelnya tidak membedakan siapa pun:
--
--   select a.employee_email, b.employee_email,
--          round(_mirip_wajah(a.embedding, b.embedding)::numeric, 3) as mirip
--   from employee_faces a join employee_faces b
--     on a.resto_id = b.resto_id and a.employee_email < b.employee_email
--   where a.resto_id = '<resto_id>';
