-- KaataGo - mencocokkan wajah dari bentuknya, tanpa model terlatih.
--
-- Jalankan SETELAH absensi_payroll.sql dan wajah_tidak_kembar.sql.
-- Aman diulang.
--
-- ── Kenapa bukan kosinus ─────────────────────────────────────────────
--
-- Sidik dari model terlatih adalah vektor abstrak, dan kemiripan
-- kosinus memang alat yang tepat untuknya.
--
-- Yang dikirim aplikasi sekarang bukan itu: ia deretan KOORDINATA titik
-- wajah yang sudah diluruskan dan diseragamkan skalanya. Kosinus atas
-- koordinat semacam itu mendekati 1 untuk siapa pun — karena semua
-- wajah memang berbentuk wajah, dan arah vektornya nyaris sama meski
-- orangnya berbeda. Yang dibandingkan berhenti berarti apa-apa, dan
-- semua orang lolos.
--
-- Yang benar jarak bentuknya: seberapa jauh tiap titik bergeser dari
-- titik pasangannya. Itu yang dihitung di bawah.
--
-- ── Ambangnya bisa disetel tanpa merilis APK ─────────────────────────
--
-- Angka di bawah ini tebakan awal yang belum diuji pada wajah
-- sungguhan. Keduanya sengaja berdiri sebagai fungsi tersendiri supaya
-- bisa disetel dari SQL Editor begitu terlihat kenyataannya — tanpa
-- membangun ulang aplikasi dan tanpa menunggu semua merchant
-- memperbaruinya.
--
-- Cara menyetelnya ada di bagian "Memeriksanya" di bawah.

begin;

-- Seberapa jauh pergeseran yang masih dianggap orang yang sama.
--
-- Satuannya jarak antarmata: 0,30 berarti pergeseran rata-rata sebesar
-- 30% jarak antarmata sudah dianggap orang lain.
create or replace function _skala_geo()
returns double precision language sql immutable as
$$ select 0.30::double precision $$;

-- Di bawah ini absennya DITOLAK.
create or replace function _ambang_geo()
returns double precision language sql immutable as
$$ select 0.60::double precision $$;

-- Di bawah ini absennya diterima tapi DITANDAI ragu, supaya atasannya
-- memeriksa fotonya.
--
-- Ada pita di antara "jelas orangnya" dan "jelas bukan" — dan menolak
-- semua yang jatuh di situ berarti mengunci orang dari pekerjaannya
-- karena cahaya pagi yang berbeda. Yang ragu dicatat, bukan ditolak.
create or replace function _ambang_geo_yakin()
returns double precision language sql immutable as
$$ select 0.72::double precision $$;

revoke all on function _skala_geo() from public, anon;
revoke all on function _ambang_geo() from public, anon;
revoke all on function _ambang_geo_yakin() from public, anon;

-- Kemiripan dua bentuk wajah, 0 sampai 1.
--
-- Akar rata-rata kuadrat pergeseran tiap titik, lalu dibalik jadi
-- kemiripan. Panjang yang berbeda berarti tidak sebanding sama sekali —
-- dijawab 0, bukan dipaksa dibandingkan sebagian.
create or replace function _mirip_geometri(
  a double precision[], b double precision[])
returns double precision
language sql
immutable
as $$
  select case
    when a is null or b is null
      or array_length(a, 1) is distinct from array_length(b, 1)
      or coalesce(array_length(a, 1), 0) = 0
      then 0
    else greatest(0, 1 - sqrt((
      select avg((x - y) * (x - y)) from unnest(a, b) as t(x, y)
    )) / _skala_geo())
  end;
$$;

-- Satu pintu untuk dua cara membandingkan.
--
-- Mana yang dipakai ditentukan nama modelnya, bukan ditebak dari isi
-- vektornya. Sidik dari dua cara berbeda tidak sebanding, dan
-- membandingkannya menghasilkan penolakan yang tidak bisa dijelaskan ke
-- orangnya.
create or replace function _mirip(
  a double precision[], b double precision[], p_model text)
returns double precision
language sql
immutable
as $$
  select case
    when coalesce(p_model, '') like 'geometri-%' then _mirip_geometri(a, b)
    else _mirip_wajah(a, b)
  end;
$$;

create or replace function _ambang(p_model text)
returns double precision
language sql
stable
as $$
  select case
    when coalesce(p_model, '') like 'geometri-%' then _ambang_geo()
    else _ambang_wajah()
  end;
$$;

revoke all on function _mirip(double precision[], double precision[], text)
  from public, anon;
revoke all on function _ambang(text) from public, anon;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Absen memakai cara yang sesuai modelnya
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Ditandai saat kemiripannya jatuh di pita ragu-ragu.
--
-- Bukan penolakan, dan bukan pula dibiarkan lewat begitu saja: baris
-- yang ditandai muncul menonjol di layar Absensi Karyawan berikut foto
-- acuan dan foto absennya bersebelahan, supaya yang memutuskan gaji
-- bisa melihat sendiri dalam dua detik.
alter table attendance add column if not exists masuk_ragu boolean
  not null default false;
alter table attendance add column if not exists pulang_ragu boolean
  not null default false;

create or replace function _absen(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_pulang boolean)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_resto record;
  v_setelan record;
  v_wajah record;
  v_skor double precision;
  v_ragu boolean;
  v_jarak double precision;
  v_peran text;
  v_wajib_dekat boolean;
  v_tanggal date := (now() at time zone 'Asia/Jakarta')::date;
  v_sekarang timestamptz := now();
begin
  if v_email = '' then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       array['owner', 'admin', 'finance', 'kasir', 'chef']) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  select latitude, longitude, name into v_resto
  from restaurants where id = p_resto_id;

  if v_resto.latitude is null or v_resto.longitude is null then
    raise exception 'Titik lokasi merchant belum disetel. Minta Admin '
                    'menyetelnya di menu Profil Merchant dulu.';
  end if;

  if p_lat is null or p_lng is null then
    raise exception 'Lokasimu tidak terbaca. Nyalakan GPS lalu coba lagi.';
  end if;

  select * into v_setelan from payroll_settings where resto_id = p_resto_id;

  v_jarak := _jarak_meter(v_resto.latitude, v_resto.longitude, p_lat, p_lng);

  -- Admin dan Finance tidak diikat radius.
  --
  -- Radiusnya ada supaya kasir dan dapur benar-benar berada di merchant
  -- saat menyatakan dirinya masuk. Admin dan Finance sering tidak: satu
  -- kantor pusat bisa mengurus beberapa merchant sekaligus, dan
  -- mengikat mereka ke titik salah satu merchant berarti menyuruh
  -- mereka pergi ke sana tiap pagi untuk pekerjaan yang tidak dikerjakan
  -- di sana.
  --
  -- Titik GPS-nya TETAP dicatat. Yang dilepas cuma penolakannya, bukan
  -- pencatatannya — kalau suatu hari ada yang perlu ditelusuri, yang
  -- dibutuhkan justru titik itu.
  select e.role into v_peran
  from employees e
  where e.resto_id = p_resto_id and lower(e.email) = v_email
  limit 1;

  v_wajib_dekat := coalesce(v_peran, '') not in ('admin', 'finance');

  if v_wajib_dekat and v_jarak > coalesce(v_setelan.radius_absen_m, 150) then
    raise exception 'Kamu % meter dari %. Absen hanya bisa dalam radius % meter.',
      round(v_jarak), coalesce(v_resto.name, 'merchant'),
      coalesce(v_setelan.radius_absen_m, 150);
  end if;

  select * into v_wajah from employee_faces
  where resto_id = p_resto_id and lower(employee_email) = v_email;

  if v_wajah is null then
    raise exception 'Wajahmu belum terdaftar. Daftarkan dulu di menu Absensi.';
  end if;

  v_skor := _mirip(v_wajah.embedding, p_embedding, v_wajah.model);

  if v_skor < _ambang(v_wajah.model) then
    raise exception 'Wajahnya tidak cocok dengan yang terdaftar. '
                    'Hadapkan wajahmu lurus ke kamera dengan cahaya yang '
                    'cukup, lalu coba lagi.';
  end if;

  -- Diterima, tapi belum tentu meyakinkan.
  v_ragu := coalesce(v_wajah.model, '') like 'geometri-%'
            and v_skor < _ambang_geo_yakin();

  if p_pulang then
    update attendance
    set pulang_at = v_sekarang,
        pulang_lat = p_lat,
        pulang_lng = p_lng,
        pulang_jarak_m = round(v_jarak),
        pulang_skor = v_skor,
        pulang_ragu = v_ragu,
        pulang_foto_url = coalesce(p_foto_url, pulang_foto_url)
    where resto_id = p_resto_id
      and lower(employee_email) = v_email
      and tanggal = v_tanggal
      and masuk_at is not null;

    if not found then
      raise exception 'Belum ada absen masuk hari ini.';
    end if;
  else
    insert into attendance (
      resto_id, employee_email, tanggal, status,
      masuk_at, masuk_lat, masuk_lng, masuk_jarak_m, masuk_skor,
      masuk_ragu, masuk_foto_url)
    values (
      p_resto_id, v_email, v_tanggal, 'hadir',
      v_sekarang, p_lat, p_lng, round(v_jarak), v_skor, v_ragu, p_foto_url)
    on conflict (resto_id, employee_email, tanggal) do update
      set status = 'hadir',
          masuk_at = coalesce(attendance.masuk_at, excluded.masuk_at),
          masuk_lat = coalesce(attendance.masuk_lat, excluded.masuk_lat),
          masuk_lng = coalesce(attendance.masuk_lng, excluded.masuk_lng),
          masuk_jarak_m =
            coalesce(attendance.masuk_jarak_m, excluded.masuk_jarak_m),
          masuk_skor = coalesce(attendance.masuk_skor, excluded.masuk_skor),
          masuk_ragu = coalesce(attendance.masuk_ragu, excluded.masuk_ragu),
          masuk_foto_url =
            coalesce(attendance.masuk_foto_url, excluded.masuk_foto_url),
          potong_gaji = false,
          alasan = null;
  end if;

  return query select round(v_jarak)::integer, v_skor, v_sekarang;
end;
$fn$;

revoke all on function _absen(text, double precision[], double precision,
  double precision, text, boolean) from public, anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pendaftaran ikut memakai cara yang sesuai
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function daftar_wajah(
  p_resto_id text,
  p_embedding double precision[],
  p_model text default 'geometri-mlkit-v1',
  p_foto_url text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_model text := coalesce(p_model, 'geometri-mlkit-v1');
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

  -- Terlalu mirip dengan rekan satu merchant berarti salah satu dari
  -- dua hal, dan keduanya harus dihentikan di sini: wajah orang lain
  -- yang didaftarkan, atau cara pencocokan yang tidak membedakan siapa
  -- pun. Yang kedua adalah kegagalan paling berbahaya, karena ia tidak
  -- pernah membuat siapa pun mengeluh.
  select employee_email,
         _mirip(embedding, p_embedding, v_model) as skor
    into v_kembar
  from employee_faces
  where resto_id = p_resto_id and model = v_model
  order by _mirip(embedding, p_embedding, v_model) desc
  limit 1;

  if v_kembar.employee_email is not null
     and v_kembar.skor >= _ambang_kembar() then
    raise exception 'Wajah ini terlalu mirip dengan karyawan lain yang '
                    'sudah terdaftar. Minta Owner atau Admin memeriksanya.';
  end if;

  insert into employee_faces (
    resto_id, employee_email, embedding, model, foto_url)
  values (p_resto_id, lower(v_email), p_embedding, v_model, p_foto_url);
end;
$fn$;

revoke all on function daftar_wajah(text, double precision[], text, text)
  from public, anon;
grant execute on function daftar_wajah(text, double precision[], text, text)
  to authenticated;

-- Foto acuan yang terdaftar, untuk disandingkan dengan foto absennya.
--
-- Fungsi tersendiri karena `employee_faces` sengaja tidak punya satu pun
-- kebijakan SELECT: sidik yang bisa dibaca aplikasi adalah sidik yang
-- bisa dikirim balik sebagai hasil pemindaian. Yang dibuka di sini cuma
-- URL fotonya, dan cuma untuk yang memang memeriksa absensi.
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
         or is_resto_employee(p_resto_id, array['owner', 'admin', 'finance'])
         or lower(f.employee_email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

grant execute on function foto_acuan_wajah(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya, dan menyetel ambangnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Angka ambang di atas belum diuji pada wajah sungguhan. Sesudah
-- beberapa hari absen berjalan, lihat sebarannya:
--
--   select round(masuk_skor::numeric, 2) as skor, count(*)
--   from attendance
--   where resto_id = '<resto_id>' and masuk_skor is not null
--   group by 1 order by 1;
--
-- Yang diharapkan: gumpalan tinggi di atas 0,75 (orangnya sendiri), dan
-- nyaris kosong di bawah 0,60.
--
--   - Banyak yang ditolak padahal orangnya benar → turunkan _ambang_geo()
--   - Ada yang lolos padahal bukan orangnya      → naikkan _ambang_geo()
--
-- Kemiripan antarkaryawan seharusnya jauh di bawah ambangnya. Yang
-- mendekati 1 untuk semua pasangan berarti caranya tidak membedakan
-- siapa pun, dan absensinya tidak membuktikan apa-apa:
--
--   select a.employee_email, b.employee_email,
--          round(_mirip(a.embedding, b.embedding, a.model)::numeric, 3)
--   from employee_faces a join employee_faces b
--     on a.resto_id = b.resto_id and a.employee_email < b.employee_email
--   where a.resto_id = '<resto_id>';
