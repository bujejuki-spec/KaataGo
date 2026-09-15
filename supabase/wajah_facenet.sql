-- KaataGo - wajah dicocokkan dengan model terlatih, dan didaftarkan
-- hanya setelah orangnya menyetujuinya.
--
-- Jalankan SETELAH wajah_geometri.sql. Aman diulang.
--
-- ── Kenapa cara yang lama harus dibuang ──────────────────────────────
--
-- Cara sebelumnya membandingkan BENTUK wajah: titik kontur dari ML Kit,
-- diluruskan di garis mata dan diseragamkan skalanya. Angka ambangnya
-- saya pasang berdasarkan vektor buatan, bukan wajah sungguhan.
--
-- Begitu ada tiga wajah asli di basis data, ia terbantah seketika:
--
--   kaatatemanjajan  vs  kahfi.gamal22     0,8849
--   ethereumluther   vs  kahfi.gamal22     0,8646
--   ethereumluther   vs  kaatatemanjajan   0,8478
--
-- Tiga orang yang BERBEDA, semuanya jauh di atas ambang "yakin" 0,72 —
-- jadi mereka tidak cuma lolos, mereka lolos tanpa ditandai ragu. Dalam
-- satuan jarak antarmata, wajah mereka cuma berselisih 3-5%, kira-kira
-- sebesar goyangan kontur ML Kit antara dua foto orang yang SAMA di
-- cahaya yang berbeda.
--
-- Tidak ada celah yang bisa disetel di situ. Penyeragaman skalanya
-- membuang justru apa yang membedakan orang, dan yang tersisa cuma
-- "berbentuk wajah" — dan semua orang berbentuk wajah.
--
-- Yang menggantikannya FaceNet: model terlatih, 128 angka, dijalankan
-- di ponsel lewat TensorFlow Lite. Fotonya tidak ke mana-mana; yang
-- masuk model adalah piksel di RAM, yang keluar 128 angka.
--
-- ── Sidik lama tidak bisa dibandingkan dengan yang baru ──────────────
--
-- Dua cara yang berbeda menghasilkan angka yang tidak sebanding sama
-- sekali. Membandingkannya tetap mengeluarkan bilangan — dan bilangan
-- itulah yang paling berbahaya, karena ia terlihat seperti jawaban.
--
-- Jadi wajah yang terdaftar dengan cara lama DITOLAK di sini, berikut
-- pesan yang menyuruh mendaftar ulang. Bukan dibiarkan lewat.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Ambangnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Angka 0,40 bukan tebakan: itu ambang kosinus yang dipakai aplikasi
-- asal modelnya sendiri setelah diuji. Sidik FaceNet TIDAK dinormalkan
-- panjangnya, jadi yang dipakai kosinus, bukan jarak Euclid.
--
-- Keduanya berdiri sebagai fungsi tersendiri supaya bisa disetel dari
-- SQL Editor begitu terlihat sebaran nyatanya — tanpa membangun ulang
-- aplikasi dan tanpa menunggu semua merchant memperbaruinya.

-- Di bawah ini absennya DITOLAK.
create or replace function _ambang_facenet()
returns double precision language sql immutable as
$$ select 0.40::double precision $$;

-- Di bawah ini diterima tapi DITANDAI ragu, supaya atasannya memeriksa
-- fotonya sendiri.
--
-- Ada pita di antara "jelas orangnya" dan "jelas bukan", dan menolak
-- semua yang jatuh di situ berarti mengunci orang dari pekerjaannya
-- karena cahaya pagi yang berbeda. Yang ragu dicatat, bukan ditolak.
create or replace function _ambang_facenet_yakin()
returns double precision language sql immutable as
$$ select 0.55::double precision $$;

-- Ambang "terlalu mirip dengan rekan" yang mengikuti modelnya.
--
-- Fungsi bernama BARU, bukan _ambang_kembar() dengan parameter tambahan.
-- `create or replace` dengan daftar parameter yang berbeda tidak menimpa
-- apa pun — ia membuat fungsi KEDUA dengan nama yang sama, dan mana
-- yang terpanggil kemudian bergantung pada pencocokan tipe.
create or replace function _ambang_kembar_model(p_model text)
returns double precision
language sql
stable
as $$
  select case
    when coalesce(p_model, '') like 'facenet-%' then 0.75::double precision
    else _ambang_kembar()
  end;
$$;

revoke all on function _ambang_facenet() from public, anon;
revoke all on function _ambang_facenet_yakin() from public, anon;
revoke all on function _ambang_kembar_model(text) from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- Satu pintu untuk memilih cara membandingkan
-- ─────────────────────────────────────────────────────────────────────

create or replace function _mirip(
  a double precision[], b double precision[], p_model text)
returns double precision
language sql
immutable
as $$
  select case
    when coalesce(p_model, '') like 'facenet-%' then _mirip_wajah(a, b)
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
    when coalesce(p_model, '') like 'facenet-%' then _ambang_facenet()
    when coalesce(p_model, '') like 'geometri-%' then _ambang_geo()
    else _ambang_wajah()
  end;
$$;

create or replace function _ambang_yakin(p_model text)
returns double precision
language sql
stable
as $$
  select case
    when coalesce(p_model, '') like 'facenet-%' then _ambang_facenet_yakin()
    when coalesce(p_model, '') like 'geometri-%' then _ambang_geo_yakin()
    else _ambang_wajah()
  end;
$$;

revoke all on function _mirip(double precision[], double precision[], text)
  from public, anon;
revoke all on function _ambang(text) from public, anon;
revoke all on function _ambang_yakin(text) from public, anon;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Persetujuan sebelum wajahnya didaftarkan
-- ─────────────────────────────────────────────────────────────────────
--
-- Wajah adalah data pribadi yang bersifat spesifik menurut UU 27/2022.
-- Mengambilnya tanpa persetujuan yang sah bukan cuma soal etika, dan
-- persetujuan yang sah berarti orangnya tahu untuk apa dipakai,
-- disimpan di mana, berapa lama, dan bagaimana mencabutnya.
--
-- Yang dicatat bukan cuma "sudah setuju", melainkan VERSI teks yang dia
-- setujui berikut waktunya. Kalau suatu hari syaratnya berubah, yang
-- pernah menyetujui teks lama tetap tercatat menyetujui teks lama —
-- dan tanpa versinya, catatan persetujuan tidak membuktikan apa pun
-- karena tidak ada yang tahu dia menyetujui apa.

begin;

alter table employee_faces
  add column if not exists setuju_versi text,
  add column if not exists setuju_at timestamptz;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Sidik dari cara yang lama dibuang
-- ─────────────────────────────────────────────────────────────────────
--
-- Bukan sekadar kebersihan. Sidik itu sudah tidak bisa dibandingkan
-- dengan apa pun — jadi ia data biometrik yang tersimpan tanpa satu pun
-- kegunaan, dan data semacam itu tidak boleh menganggur di basis data.
--
-- Membuangnya juga yang membuat orangnya BISA mendaftar ulang:
-- daftar_wajah() menolak siapa pun yang barisnya masih ada, dan tanpa
-- ini tiga orang terjebak di antara absen yang ditolak dan pendaftaran
-- yang ditolak.
--
-- Foto acuannya ikut hilang dari layar sampai mereka mendaftar ulang.
-- Berkasnya sendiri masih di penyimpanan, jadi tidak ada bukti sengketa
-- yang lenyap.

begin;

delete from employee_faces where model not like 'facenet-%';

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Mendaftarkan wajah
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Daftar parameternya bertambah satu, jadi yang lama dibuang lebih
-- dulu — lihat catatan di _ambang_kembar_model() di atas.
-- Dua-duanya dibuang, yang berparameter empat maupun yang lima.
--
-- Yang lima memang sudah bernama sama dan bertipe sama, tapi versi
-- terdahulunya punya nilai bawaan — dan `create or replace` MENOLAK
-- mencabut nilai bawaan dari fungsi yang sudah ada. Galatnya menyebut
-- DROP FUNCTION dengan jelas, tapi ia baru muncul saat berkas ini
-- dijalankan ulang, bukan saat pertama kali.
drop function if exists daftar_wajah(text, double precision[], text, text);
drop function if exists daftar_wajah(text, double precision[], text, text, text);

create or replace function daftar_wajah(
  p_resto_id text,
  p_embedding double precision[],
  -- Tidak satu pun berparameter bawaan, dan itu disengaja.
  --
  -- Postgres menuntutnya begitu parameter terakhir wajib: yang tanpa
  -- bawaan tidak boleh berdiri setelah yang punya bawaan.
  --
  -- Tapi bukan cuma menuruti aturan bahasanya. Bawaan di sini berarti
  -- panggilan berparameter empat punya tempat mendarat — dan tempat
  -- mendaratnya adalah versi lama yang tidak memeriksa persetujuan sama
  -- sekali. Aplikasi selalu mengirim kelimanya, jadi tidak ada yang
  -- hilang dengan mewajibkannya.
  p_model text,
  p_foto_url text,
  p_setuju_versi text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_model text := coalesce(p_model, 'facenet-128-v1');
  v_kembar record;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       peran_karyawan()) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  -- Persetujuannya diperiksa di SERVER, bukan cuma di layar.
  --
  -- Kotak centang di aplikasi menghalangi orang yang memakai aplikasi.
  -- Ia tidak menghalangi apa pun yang memanggil fungsi ini langsung —
  -- dan wajah yang masuk lewat jalan itu adalah wajah yang tersimpan
  -- tanpa ada yang pernah menyetujuinya.
  if coalesce(trim(p_setuju_versi), '') = '' then
    raise exception 'Pendaftaran wajah butuh persetujuanmu dulu. Baca '
                    'syarat penggunaan datanya lalu centang setuju.';
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
  -- pernah membuat siapa pun mengeluh — persis yang terjadi pada cara
  -- lama, dan yang menemukannya bukan pemeriksaan ini melainkan seorang
  -- manusia yang menatap dua foto bersebelahan.
  --
  -- Hanya dibandingkan dengan sidik dari model yang SAMA. Sidik dari
  -- model berbeda tidak sebanding, dan membandingkannya menghasilkan
  -- penolakan yang tidak bisa dijelaskan ke orangnya.
  select employee_email,
         _mirip(embedding, p_embedding, v_model) as skor
    into v_kembar
  from employee_faces
  where resto_id = p_resto_id and model = v_model
  order by _mirip(embedding, p_embedding, v_model) desc
  limit 1;

  if v_kembar.employee_email is not null
     and v_kembar.skor >= _ambang_kembar_model(v_model) then
    raise exception 'Wajah ini terlalu mirip dengan karyawan lain yang '
                    'sudah terdaftar. Minta Owner atau Admin memeriksanya.';
  end if;

  insert into employee_faces (
    resto_id, employee_email, embedding, model, foto_url,
    setuju_versi, setuju_at)
  values (p_resto_id, lower(v_email), p_embedding, v_model, p_foto_url,
          trim(p_setuju_versi), now());
end;
$fn$;

revoke all on function daftar_wajah(
  text, double precision[], text, text, text) from public, anon;
grant execute on function daftar_wajah(
  text, double precision[], text, text, text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Absen menolak sidik yang tidak sebanding
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Yang memanggil dibuang lebih dulu, baru yang dipanggil — dan
-- keduanya dibuang karena versi terdahulunya berparameter bawaan, yang
-- tidak bisa dicabut oleh `create or replace`.
drop function if exists absen_masuk(text, double precision[],
  double precision, double precision, text, text);
drop function if exists absen_pulang(text, double precision[],
  double precision, double precision, text, text);
drop function if exists _absen(text, double precision[], double precision,
  double precision, text, boolean, text);

create or replace function _absen(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_pulang boolean,
  -- TANPA nilai bawaan, dan itu disengaja.
  --
  -- Dengan `default null`, panggilan berparameter enam cocok ke DUA
  -- fungsi sekaligus — yang lama dan yang ini — dan Postgres menolaknya:
  -- "function _absen(...) is not unique". Yang kena bukan berkas ini
  -- melainkan absensi_payroll.sql yang dijalankan lebih dulu di bundel
  -- gabungan, jadi galatnya muncul jauh sebelum baris ini terbaca dan
  -- seluruh sisa bundelnya batal.
  p_model text)
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
       peran_karyawan()) then
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

  -- Admin dan Finance tidak diikat radius: satu kantor pusat bisa
  -- mengurus beberapa merchant, dan mengikat mereka ke titik salah
  -- satunya berarti menyuruh mereka pergi ke sana tiap pagi untuk
  -- pekerjaan yang tidak dikerjakan di sana. Titik GPS-nya TETAP
  -- dicatat; yang dilepas penolakannya, bukan pencatatannya.
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

  -- Sidik dari cara yang berbeda TIDAK dibandingkan.
  --
  -- Membandingkannya tetap mengeluarkan bilangan, dan bilangan itulah
  -- yang paling berbahaya: ia terlihat seperti jawaban. Yang wajahnya
  -- terdaftar dengan cara lama disuruh mendaftar ulang, bukan diadu
  -- dengan angka yang tidak berarti apa-apa.
  if p_model is not null and coalesce(v_wajah.model, '') <> p_model then
    raise exception 'Wajahmu terdaftar dengan cara pengenalan yang lama '
                    'dan tidak bisa dibandingkan dengan yang sekarang. '
                    'Minta Owner atau Admin mereset wajahmu lewat Kelola '
                    'Karyawan, lalu daftarkan ulang.';
  end if;

  v_skor := _mirip(v_wajah.embedding, p_embedding, v_wajah.model);

  if v_skor < _ambang(v_wajah.model) then
    raise exception 'Wajahnya tidak cocok dengan yang terdaftar. '
                    'Hadapkan wajahmu lurus ke kamera dengan cahaya yang '
                    'cukup, lalu coba lagi.';
  end if;

  -- Diterima, tapi belum tentu meyakinkan.
  v_ragu := v_skor < _ambang_yakin(v_wajah.model);

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
  double precision, text, boolean, text) from public, anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pintu absennya meneruskan nama modelnya
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Urutannya penting. Yang memanggil dibuang lebih dulu, baru yang
-- dipanggil: membuang _absen() lama selagi absen_masuk() lama masih
-- menyebutnya adalah galat ketergantungan, dan galat itu membatalkan
-- seluruh berkas ini di tengah jalan.
drop function if exists absen_masuk(text, double precision[],
  double precision, double precision, text);
drop function if exists absen_pulang(text, double precision[],
  double precision, double precision, text);

-- Yang berparameter lama dibuang: ia memanggil jalur tanpa pemeriksaan
-- model, dan jalan memutar yang tidak dipakai sebaiknya tidak tertinggal.
drop function if exists _absen(text, double precision[], double precision,
  double precision, text, boolean);

create or replace function absen_masuk(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_model text)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language sql
security definer
set search_path = public
as $$
  select * from _absen(p_resto_id, p_embedding, p_lat, p_lng,
                       p_foto_url, false, p_model);
$$;

create or replace function absen_pulang(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text,
  p_model text)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language sql
security definer
set search_path = public
as $$
  select * from _absen(p_resto_id, p_embedding, p_lat, p_lng,
                       p_foto_url, true, p_model);
$$;

revoke all on function absen_masuk(text, double precision[], double precision,
  double precision, text, text) from public, anon;
revoke all on function absen_pulang(text, double precision[], double precision,
  double precision, text, text) from public, anon;
grant execute on function absen_masuk(text, double precision[], double precision,
  double precision, text, text) to authenticated;
grant execute on function absen_pulang(text, double precision[], double precision,
  double precision, text, text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Wajah yang masih memakai cara lama — semuanya harus didaftar ulang:
--
--      select resto_id, employee_email, model from employee_faces
--      where model not like 'facenet-%';
--
-- 2. Sesudah beberapa orang mendaftar ulang, kemiripan ANTARKARYAWAN
--    adalah ujian yang dulu gagal. Dengan FaceNet, angka orang yang
--    berbeda seharusnya jauh di bawah 0,40 — bukan 0,85 seperti dulu:
--
--      select a.employee_email, b.employee_email,
--             round(_mirip(a.embedding, b.embedding, a.model)::numeric, 3)
--      from employee_faces a join employee_faces b
--        on a.resto_id = b.resto_id and a.employee_email < b.employee_email
--      where a.model like 'facenet-%' and b.model like 'facenet-%';
--
--    Kalau angkanya masih tinggi, JANGAN naikkan ambangnya — berarti
--    ada yang keliru di sisi aplikasi, dan menaikkan ambang cuma
--    menyembunyikannya sampai ada yang absen atas nama orang lain.
--
-- 3. Sebaran skor absen orangnya sendiri:
--
--      select round(masuk_skor::numeric, 2) as skor, count(*)
--      from attendance where masuk_skor is not null group by 1 order by 1;
--
--    - Banyak yang ditolak padahal orangnya benar → turunkan _ambang_facenet()
--    - Ada yang lolos padahal bukan orangnya      → naikkan _ambang_facenet()
--
-- 4. Persetujuan tercatat berikut versinya:
--
--      select employee_email, setuju_versi, setuju_at from employee_faces;
