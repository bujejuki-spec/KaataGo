-- KaataGo - absensi wajah berlokasi, dan payroll yang menghitung darinya.
--
-- Jalankan kapan saja setelah schema.sql dan resto_location. Aman diulang.
--
-- ── Kenapa pencocokan wajahnya di server ─────────────────────────────
--
-- Yang mudah dibuat adalah aplikasi yang mencocokkan wajah di HP lalu
-- mengirim "cocok" ke server. Itu tidak menahan apa pun: yang bisa
-- mengirim "cocok" bisa mengirimnya tanpa membuka kamera sama sekali,
-- dan seluruh absensi jadi kata-kata aplikasi tentang dirinya sendiri.
--
-- Jadi yang dikirim HP adalah sidik wajahnya — deret angka hasil model
-- di perangkat — dan server yang membandingkannya dengan sidik yang
-- terdaftar. Sidik terdaftarnya sendiri tidak pernah boleh dibaca siapa
-- pun dari aplikasi (lihat RLS di bawah), jadi tidak ada yang bisa
-- mengirim balik sidik orang lain yang dia salin dari layarnya.
--
-- Ini tetap bukan jaminan mutlak — orang yang membongkar aplikasinya
-- masih bisa menyuapkan foto ke modelnya. Yang dijamin cuma satu hal,
-- dan itu yang diminta: absen tidak bisa dititipkan ke teman yang
-- membuka aplikasi dengan akunnya sendiri.
--
-- ── Kenapa jaraknya juga dihitung server ─────────────────────────────
--
-- Alasan yang sama. Titik GPS yang diperiksa di HP adalah titik yang
-- ditentukan HP. Yang diperiksa di sini bukan kejujuran perangkatnya,
-- melainkan bahwa angka yang dikirimnya memang jatuh di sekitar
-- merchant — dan itu tetap menutup cara paling umum orang mengakalinya:
-- absen dari rumah.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Sidik wajah
-- ─────────────────────────────────────────────────────────────────────

begin;

create table if not exists employee_faces (
  resto_id text not null references restaurants (id) on delete cascade,
  employee_email text not null,

  -- Keluaran model pengenal wajah di perangkat. Panjangnya ikut
  -- modelnya (MobileFaceNet: 192), disimpan apa adanya supaya mengganti
  -- model nanti tidak menuntut mengubah bentuk tabelnya.
  embedding double precision[] not null,

  -- Nama model yang menghasilkannya. Sidik dari dua model berbeda tidak
  -- bisa dibandingkan sama sekali — angkanya tetap keluar, dan yang
  -- keluar adalah penolakan yang tidak bisa dijelaskan ke orangnya.
  model text not null default 'mobilefacenet-192',

  -- Foto saat mendaftar, untuk diperiksa manusia kalau ada sengketa.
  foto_url text,

  registered_at timestamptz not null default now(),

  -- Berapa kali wajahnya direset Owner/Admin. Reset yang sering pada
  -- satu orang adalah pola yang pantas dilihat, bukan angka iseng.
  reset_count integer not null default 0,

  primary key (resto_id, employee_email)
);

alter table employee_faces enable row level security;

-- Tidak ada satu pun kebijakan SELECT. Itu disengaja.
--
-- Sidik wajah yang bisa dibaca aplikasi adalah sidik yang bisa dikirim
-- balik sebagai "hasil pemindaian" — dan seluruh gunanya hilang.
-- Satu-satunya yang menyentuhnya adalah fungsi SECURITY DEFINER di
-- bawah, yang membandingkannya tanpa pernah mengembalikan isinya.
--
-- Yang boleh diketahui aplikasi cuma "sudah terdaftar atau belum", dan
-- itu dijawab fungsi tersendiri.
drop policy if exists "employee_faces: none" on employee_faces;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Absensi
-- ─────────────────────────────────────────────────────────────────────

begin;

create table if not exists attendance (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,
  employee_email text not null,

  -- Tanggal WIB, bukan UTC. Absen jam tujuh pagi WIB adalah hari itu;
  -- disimpan UTC ia jatuh ke tanggal kemarin, dan rekap bulanannya
  -- meleset satu hari untuk setiap orang yang masuk pagi.
  tanggal date not null,

  -- 'hadir' | 'izin' | 'sakit' | 'cuti' | 'alpa'
  status text not null default 'hadir'
    check (status in ('hadir', 'izin', 'sakit', 'cuti', 'alpa')),

  masuk_at timestamptz,
  masuk_lat double precision,
  masuk_lng double precision,
  masuk_jarak_m integer,
  masuk_skor double precision,
  masuk_foto_url text,

  pulang_at timestamptz,
  pulang_lat double precision,
  pulang_lng double precision,
  pulang_jarak_m integer,
  pulang_skor double precision,
  pulang_foto_url text,

  -- Diisi saat tidak masuk.
  alasan text,
  bukti_url text,

  -- Hari ini memotong gaji atau tidak.
  --
  -- Disimpan di barisnya, bukan disimpulkan dari statusnya saat
  -- menghitung gaji. Aturannya berubah — sakit berhari-hari yang
  -- awalnya dipotong bisa dimaafkan kemudian — dan gaji bulan lalu yang
  -- ikut berubah sendiri karena aturannya diganti adalah angka yang
  -- tidak bisa dipertanggungjawabkan ke siapa pun.
  potong_gaji boolean not null default false,

  diputuskan_oleh text,
  created_at timestamptz not null default now(),

  -- Satu baris per orang per hari. Tanpa ini, tombol yang ditekan dua
  -- kali karena jaringannya lambat menjadi dua kali hadir — dan orang
  -- itu dibayar untuk hari yang sama dua kali.
  unique (resto_id, employee_email, tanggal)
);

create index if not exists idx_attendance_resto_tgl
  on attendance (resto_id, tanggal);

alter table attendance enable row level security;

-- Karyawan membaca absensinya sendiri. Atasan membaca semuanya.
--
-- Kasir tidak boleh melihat absensi kasir lain: jam datang dan jam
-- pulang orang lain bukan urusan yang perlu beredar di antara semua
-- orang yang memegang HP, dan yang menumpuk dari situ adalah
-- perbandingan yang tidak ada gunanya bagi pekerjaannya.
drop policy if exists "attendance: read" on attendance;
create policy "attendance: read" on attendance
  for select using (
    is_super_admin()
    or lower(employee_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

-- Ditulis lewat fungsi, bukan langsung.
--
-- Baris absensi yang bisa disisipkan aplikasi adalah baris yang bisa
-- disisipkan tanpa wajah, tanpa GPS, dan bertanggal kapan saja.
drop policy if exists "attendance: insert" on attendance;

-- Atasan boleh membetulkan keputusan potong gaji dan statusnya.
drop policy if exists "attendance: atasan ubah" on attendance;
create policy "attendance: atasan ubah" on attendance
  for update using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  ) with check (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Aturan gaji
-- ─────────────────────────────────────────────────────────────────────

begin;

create table if not exists payroll_settings (
  resto_id text primary key references restaurants (id) on delete cascade,

  -- Tanggal gajian. Periodenya berakhir sehari sebelum tanggal ini di
  -- bulan berikutnya: gajian tanggal 25 berarti periode 26 Mei - 25 Juni.
  tanggal_gajian integer not null default 25
    check (tanggal_gajian between 1 and 28),

  -- Hari kerja dalam satu periode. Inilah pembagi gaji sebulan, bukan
  -- jumlah hari kalender — yang libur memang tidak dibayar per hari,
  -- dan membaginya dengan 30 membuat potongan sehari jadi lebih kecil
  -- daripada yang disepakati.
  hari_kerja_periode integer not null default 25
    check (hari_kerja_periode between 1 and 31),

  -- Persen dari gaji pokok. Nol berarti merchant ini memang tidak
  -- memotongnya.
  bpjs_kesehatan_persen numeric(5, 2) not null default 0
    check (bpjs_kesehatan_persen >= 0 and bpjs_kesehatan_persen <= 100),
  bpjs_tk_persen numeric(5, 2) not null default 0
    check (bpjs_tk_persen >= 0 and bpjs_tk_persen <= 100),

  -- Sejauh mana dari titik merchant absen masih diterima.
  --
  -- Bawaannya 150 meter, bukan 20. GPS ponsel di dalam ruko berdinding
  -- beton meleset puluhan meter dengan sendirinya, dan radius yang
  -- terlalu rapat menolak orang yang benar-benar berdiri di dapur.
  radius_absen_m integer not null default 150
    check (radius_absen_m between 20 and 5000),

  updated_at timestamptz not null default now(),
  updated_by text
);

alter table payroll_settings enable row level security;

drop policy if exists "payroll_settings: baca" on payroll_settings;
create policy "payroll_settings: baca" on payroll_settings
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id,
         array['owner', 'admin', 'finance', 'kasir', 'chef'])
  );

-- Yang menetapkan gaji hanya Owner dan Finance.
--
-- Admin sengaja tidak. Ia mengurus operasional merchant, dan besaran
-- gaji bukan angka yang perlu bisa diubah oleh setiap orang yang bisa
-- menambah menu.
drop policy if exists "payroll_settings: ubah" on payroll_settings;
create policy "payroll_settings: ubah" on payroll_settings
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  );

create table if not exists employee_payroll (
  resto_id text not null references restaurants (id) on delete cascade,
  employee_email text not null,

  gaji_pokok bigint not null default 0 check (gaji_pokok >= 0),

  -- Tunjangan tetap yang tidak ikut dipotong kehadiran.
  tunjangan bigint not null default 0 check (tunjangan >= 0),

  bank_name text,
  account_number text,
  account_holder text,

  updated_at timestamptz not null default now(),
  updated_by text,

  primary key (resto_id, employee_email)
);

alter table employee_payroll enable row level security;

-- Karyawan boleh melihat barisnya sendiri — itu slip gajinya. Gaji
-- orang lain tidak.
drop policy if exists "employee_payroll: baca" on employee_payroll;
create policy "employee_payroll: baca" on employee_payroll
  for select using (
    is_super_admin()
    or lower(employee_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    or is_resto_employee(resto_id, array['owner', 'finance'])
  );

drop policy if exists "employee_payroll: ubah" on employee_payroll;
create policy "employee_payroll: ubah" on employee_payroll
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Jarak dan kemiripan
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Jarak dua titik bumi dalam meter.
--
-- Haversine, bukan PostGIS. Yang dibutuhkan cuma "masih di sekitar
-- merchant atau tidak" pada jarak ratusan meter; menambah satu ekstensi
-- ke basis data demi ketelitian sentimeter yang tidak dipakai siapa pun
-- adalah ongkos yang dibayar tiap kali basis datanya dipindah.
create or replace function _jarak_meter(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) *
    power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- Kemiripan kosinus dua sidik wajah, -1 sampai 1.
--
-- Nol panjang dijaga: sidik yang seluruhnya nol — yang keluar dari
-- model saat gambarnya gagal dibaca — akan membagi dengan nol, dan
-- galat pembagian di tengah absen pagi hari terbaca sebagai aplikasi
-- yang rusak.
create or replace function _mirip_wajah(
  a double precision[], b double precision[])
returns double precision
language sql
immutable
as $$
  select case
    when a is null or b is null or array_length(a, 1) is distinct from array_length(b, 1)
      then -1
    when sqrt(coalesce((select sum(x * x) from unnest(a) x), 0)) = 0
      or sqrt(coalesce((select sum(y * y) from unnest(b) y), 0)) = 0
      then -1
    else (
      select sum(x * y)
      from unnest(a, b) as t(x, y)
    ) / (
      sqrt((select sum(x * x) from unnest(a) x)) *
      sqrt((select sum(y * y) from unnest(b) y))
    )
  end;
$$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 5. Mendaftarkan wajah
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Sudah terdaftar atau belum. Ini satu-satunya hal tentang sidiknya yang
-- boleh diketahui aplikasi.
create or replace function wajah_terdaftar(p_resto_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from employee_faces
    where resto_id = p_resto_id
      and lower(employee_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- Didaftarkan sendiri, sekali.
--
-- Pendaftaran ulang ditolak, dan itu inti seluruh fiturnya: kalau
-- siapa pun bisa mendaftar ulang kapan saja, titip absen cuma butuh
-- mendaftar ulang dengan wajah temannya pagi itu lalu mengembalikannya
-- sore hari. Yang bisa membuka kuncinya cuma Owner dan Admin.
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

  insert into employee_faces (
    resto_id, employee_email, embedding, model, foto_url)
  values (p_resto_id, lower(v_email), p_embedding,
          coalesce(p_model, 'mobilefacenet-192'), p_foto_url);
end;
$fn$;

-- Jejak siapa yang pernah membuka kuncinya.
create table if not exists employee_face_resets (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null,
  employee_email text not null,
  oleh text,
  created_at timestamptz not null default now()
);

alter table employee_face_resets enable row level security;

drop policy if exists "face_resets: atasan" on employee_face_resets;
create policy "face_resets: atasan" on employee_face_resets
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

-- Membuka kuncinya. Owner dan Admin saja.
create or replace function reset_wajah(p_resto_id text, p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'admin'])) then
    raise exception 'Hanya Owner dan Admin yang bisa mereset wajah.';
  end if;

  -- Hitungannya dibawa ke baris berikutnya lewat tabel terpisah supaya
  -- tidak hilang saat barisnya dihapus. Reset yang sering pada satu
  -- orang adalah pola yang pantas dilihat.
  insert into employee_face_resets (resto_id, employee_email, oleh)
  values (p_resto_id, lower(p_email), auth.jwt() ->> 'email');

  delete from employee_faces
  where resto_id = p_resto_id and lower(employee_email) = lower(p_email);
end;
$fn$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 6. Absen
-- ─────────────────────────────────────────────────────────────────────

begin;

-- Ambang kemiripan.
--
-- 0,75 pada kosinus MobileFaceNet: cukup longgar untuk orang yang sama
-- dengan rambut basah dan masker dilepas buru-buru, cukup rapat untuk
-- menolak orang lain. Ditulis sebagai konstanta di satu tempat supaya
-- menyetelnya nanti tidak menuntut mencarinya di dua fungsi.
create or replace function _ambang_wajah()
returns double precision language sql immutable as $$ select 0.75::double precision $$;

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
  v_jarak double precision;
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

  -- Jaraknya disebut angka, bukan cuma "terlalu jauh". Yang berdiri 30
  -- meter di luar radius dan yang absen dari rumah menerima penolakan
  -- yang sama, dan cuma yang pertama yang bisa memperbaikinya sendiri.
  if v_jarak > coalesce(v_setelan.radius_absen_m, 150) then
    raise exception 'Kamu % meter dari %. Absen hanya bisa dalam radius % meter.',
      round(v_jarak), coalesce(v_resto.name, 'merchant'),
      coalesce(v_setelan.radius_absen_m, 150);
  end if;

  select * into v_wajah from employee_faces
  where resto_id = p_resto_id and lower(employee_email) = v_email;

  if v_wajah is null then
    raise exception 'Wajahmu belum terdaftar. Daftarkan dulu di menu Absensi.';
  end if;

  v_skor := _mirip_wajah(v_wajah.embedding, p_embedding);

  if v_skor < _ambang_wajah() then
    raise exception 'Wajahnya tidak cocok dengan yang terdaftar. '
                    'Pastikan wajahmu terlihat jelas dan cahayanya cukup.';
  end if;

  if p_pulang then
    update attendance
    set pulang_at = v_sekarang,
        pulang_lat = p_lat,
        pulang_lng = p_lng,
        pulang_jarak_m = round(v_jarak),
        pulang_skor = v_skor,
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
      masuk_foto_url)
    values (
      p_resto_id, v_email, v_tanggal, 'hadir',
      v_sekarang, p_lat, p_lng, round(v_jarak), v_skor, p_foto_url)
    -- Hari yang sudah diajukan sebagai izin lalu ternyata masuk juga
    -- berubah jadi hadir. Yang tidak berubah: absen masuk yang sudah
    -- ada, supaya jam datang yang tercatat tetap jam datang pertama.
    on conflict (resto_id, employee_email, tanggal) do update
      set status = 'hadir',
          masuk_at = coalesce(attendance.masuk_at, excluded.masuk_at),
          masuk_lat = coalesce(attendance.masuk_lat, excluded.masuk_lat),
          masuk_lng = coalesce(attendance.masuk_lng, excluded.masuk_lng),
          masuk_jarak_m =
            coalesce(attendance.masuk_jarak_m, excluded.masuk_jarak_m),
          masuk_skor = coalesce(attendance.masuk_skor, excluded.masuk_skor),
          masuk_foto_url =
            coalesce(attendance.masuk_foto_url, excluded.masuk_foto_url),
          potong_gaji = false,
          alasan = null;
  end if;

  return query select round(v_jarak)::integer, v_skor, v_sekarang;
end;
$fn$;

create or replace function absen_masuk(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text default null)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language sql
security definer
set search_path = public
as $$
  select * from _absen(p_resto_id, p_embedding, p_lat, p_lng, p_foto_url, false);
$$;

create or replace function absen_pulang(
  p_resto_id text,
  p_embedding double precision[],
  p_lat double precision,
  p_lng double precision,
  p_foto_url text default null)
returns table (jarak_m integer, skor double precision, waktu timestamptz)
language sql
security definer
set search_path = public
as $$
  select * from _absen(p_resto_id, p_embedding, p_lat, p_lng, p_foto_url, true);
$$;

-- Tidak masuk, berikut alasannya.
--
-- Tidak butuh wajah maupun GPS: yang sedang sakit di rumah memang tidak
-- bisa berdiri di depan merchant, dan menuntutnya begitu berarti
-- menuntut orang sakit datang hanya untuk menyatakan dirinya tidak
-- datang.
create or replace function ajukan_tidak_masuk(
  p_resto_id text,
  p_tanggal date,
  p_status text,
  p_alasan text,
  p_bukti_url text default null)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if v_email = '' then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       array['owner', 'admin', 'finance', 'kasir', 'chef']) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  if p_status not in ('izin', 'sakit', 'cuti') then
    raise exception 'Statusnya harus izin, sakit, atau cuti.';
  end if;

  if p_tanggal > (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Belum bisa mengajukan untuk tanggal yang belum tiba.';
  end if;

  -- Hari yang sudah terlanjur absen masuk tidak bisa diubah jadi izin
  -- oleh yang bersangkutan sendiri. Kalau memang keliru, atasannya yang
  -- membetulkan — dan itu meninggalkan jejak siapa yang mengubahnya.
  if exists (select 1 from attendance
             where resto_id = p_resto_id
               and lower(employee_email) = v_email
               and tanggal = p_tanggal
               and masuk_at is not null) then
    raise exception 'Hari itu sudah tercatat masuk. Minta Admin yang '
                    'membetulkannya.';
  end if;

  insert into attendance (
    resto_id, employee_email, tanggal, status, alasan, bukti_url)
  values (p_resto_id, v_email, p_tanggal, p_status, p_alasan, p_bukti_url)
  on conflict (resto_id, employee_email, tanggal) do update
    set status = excluded.status,
        alasan = excluded.alasan,
        bukti_url = coalesce(excluded.bukti_url, attendance.bukti_url);
end;
$fn$;

revoke all on function absen_masuk(text, double precision[], double precision,
  double precision, text) from public, anon;
revoke all on function absen_pulang(text, double precision[], double precision,
  double precision, text) from public, anon;
grant execute on function absen_masuk(text, double precision[], double precision,
  double precision, text) to authenticated;
grant execute on function absen_pulang(text, double precision[], double precision,
  double precision, text) to authenticated;
grant execute on function ajukan_tidak_masuk(text, date, text, text, text)
  to authenticated;
grant execute on function daftar_wajah(text, double precision[], text, text)
  to authenticated;
grant execute on function reset_wajah(text, text) to authenticated;
grant execute on function wajah_terdaftar(text) to authenticated;

-- Pembantu absen. Ia sudah memeriksa wajah, jarak, dan keanggotaan
-- sendiri, jadi tidak ada yang jebol lewat sini — tapi permukaan yang
-- tidak dibutuhkan sebaiknya tidak ada. absen_masuk dan absen_pulang
-- tetap bisa memanggilnya: SECURITY DEFINER berjalan sebagai pemiliknya.
revoke all on function _absen(text, double precision[], double precision,
  double precision, text, boolean) from public, anon, authenticated;
revoke all on function _ambang_wajah() from public, anon;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 7. Rekap gaji satu periode
-- ─────────────────────────────────────────────────────────────────────
--
-- Dihitung di server, sekali jalan, untuk seluruh karyawan.
--
-- Menghitungnya di aplikasi berarti menarik seluruh baris absensi satu
-- bulan ke sebuah HP lalu menjumlahkannya di sana — dan dua perangkat
-- yang menjumlahkan sendiri akan suatu hari menyebut dua angka gaji
-- yang berbeda untuk orang yang sama. Angka gaji bukan tempat yang
-- pantas untuk perbedaan semacam itu.

begin;

create or replace function rekap_payroll(
  p_resto_id text,
  p_mulai date,
  p_akhir date)
returns table (
  employee_email text,
  nama text,
  peran text,
  gaji_pokok bigint,
  tunjangan bigint,
  hari_kerja integer,
  hadir integer,
  izin integer,
  sakit integer,
  cuti integer,
  alpa integer,
  hari_potong integer,
  potongan_absen bigint,
  potongan_bpjs_kesehatan bigint,
  potongan_bpjs_tk bigint,
  gaji_bersih bigint,
  bank_name text,
  account_number text,
  account_holder text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_setelan record;
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'finance'])) then
    raise exception 'Hanya Owner dan Finance yang bisa membuka payroll.';
  end if;

  select * into v_setelan from payroll_settings where resto_id = p_resto_id;

  return query
  with orang as (
    select e.email, e.name, e.role
    from employees e
    where e.resto_id = p_resto_id
      and coalesce(e.active, true)
      and e.role <> 'super_admin'
  ),
  hitung as (
    select a.employee_email as em,
           count(*) filter (where a.status = 'hadir')::integer as h,
           count(*) filter (where a.status = 'izin')::integer as i,
           count(*) filter (where a.status = 'sakit')::integer as s,
           count(*) filter (where a.status = 'cuti')::integer as c,
           count(*) filter (where a.status = 'alpa')::integer as al,
           count(*) filter (where a.potong_gaji)::integer as p
    from attendance a
    where a.resto_id = p_resto_id
      and a.tanggal between p_mulai and p_akhir
    group by 1
  )
  select o.email,
         coalesce(o.name, o.email),
         o.role,
         coalesce(ep.gaji_pokok, 0),
         coalesce(ep.tunjangan, 0),
         coalesce(v_setelan.hari_kerja_periode, 25),
         coalesce(g.h, 0),
         coalesce(g.i, 0),
         coalesce(g.s, 0),
         coalesce(g.c, 0),
         coalesce(g.al, 0),
         coalesce(g.p, 0),
         -- Potongan dibulatkan ke bawah, sejalan dengan seluruh angka
         -- rupiah di aplikasi ini. Dibulatkan ke atas, yang menanggung
         -- selisihnya karyawan.
         floor(coalesce(ep.gaji_pokok, 0)::numeric
               / greatest(coalesce(v_setelan.hari_kerja_periode, 25), 1)
               * least(coalesce(g.p, 0),
                       coalesce(v_setelan.hari_kerja_periode, 25))
              )::bigint,
         floor(coalesce(ep.gaji_pokok, 0)::numeric
               * coalesce(v_setelan.bpjs_kesehatan_persen, 0) / 100)::bigint,
         floor(coalesce(ep.gaji_pokok, 0)::numeric
               * coalesce(v_setelan.bpjs_tk_persen, 0) / 100)::bigint,
         -- Tidak pernah minus. Potongan yang melebihi gajinya sendiri —
         -- tidak masuk sebulan penuh berikut BPJS — akan menghasilkan
         -- angka merah yang dibaca sebagai utang karyawan ke merchant,
         -- dan itu bukan yang dimaksud siapa pun.
         greatest(
           coalesce(ep.gaji_pokok, 0) + coalesce(ep.tunjangan, 0)
           - floor(coalesce(ep.gaji_pokok, 0)::numeric
                   / greatest(coalesce(v_setelan.hari_kerja_periode, 25), 1)
                   * least(coalesce(g.p, 0),
                           coalesce(v_setelan.hari_kerja_periode, 25))
                  )::bigint
           - floor(coalesce(ep.gaji_pokok, 0)::numeric
                   * coalesce(v_setelan.bpjs_kesehatan_persen, 0) / 100)::bigint
           - floor(coalesce(ep.gaji_pokok, 0)::numeric
                   * coalesce(v_setelan.bpjs_tk_persen, 0) / 100)::bigint,
           0)::bigint,
         ep.bank_name,
         ep.account_number,
         ep.account_holder
  from orang o
  left join employee_payroll ep
         on ep.resto_id = p_resto_id
        and lower(ep.employee_email) = lower(o.email)
  left join hitung g on lower(g.em) = lower(o.email)
  order by o.name nulls last, o.email;
end;
$fn$;

-- Slip gaji karyawan sendiri.
--
-- Fungsi terpisah, bukan rekap yang disaring: rekapnya menolak siapa
-- pun selain Owner dan Finance, dan melonggarkan syarat itu supaya
-- karyawan bisa masuk berarti melonggarkannya untuk seluruh baris
-- sekaligus.
create or replace function slip_gaji_saya(
  p_resto_id text,
  p_mulai date,
  p_akhir date)
returns table (
  gaji_pokok bigint,
  tunjangan bigint,
  hari_kerja integer,
  hadir integer,
  izin integer,
  sakit integer,
  cuti integer,
  alpa integer,
  hari_potong integer,
  potongan_absen bigint,
  potongan_bpjs_kesehatan bigint,
  potongan_bpjs_tk bigint,
  gaji_bersih bigint,
  bank_name text,
  account_number text,
  account_holder text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_setelan record;
  v_gaji record;
  v_h record;
  v_potong_absen bigint;
  v_bpjs_kes bigint;
  v_bpjs_tk bigint;
begin
  if v_email = '' then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       array['owner', 'admin', 'finance', 'kasir', 'chef']) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  select * into v_setelan from payroll_settings where resto_id = p_resto_id;
  select * into v_gaji from employee_payroll
  where resto_id = p_resto_id and lower(employee_email) = v_email;

  select count(*) filter (where status = 'hadir')::integer as h,
         count(*) filter (where status = 'izin')::integer as i,
         count(*) filter (where status = 'sakit')::integer as s,
         count(*) filter (where status = 'cuti')::integer as c,
         count(*) filter (where status = 'alpa')::integer as al,
         count(*) filter (where potong_gaji)::integer as p
    into v_h
  from attendance
  where resto_id = p_resto_id
    and lower(employee_email) = v_email
    and tanggal between p_mulai and p_akhir;

  v_potong_absen := floor(coalesce(v_gaji.gaji_pokok, 0)::numeric
    / greatest(coalesce(v_setelan.hari_kerja_periode, 25), 1)
    * least(coalesce(v_h.p, 0), coalesce(v_setelan.hari_kerja_periode, 25))
  )::bigint;
  v_bpjs_kes := floor(coalesce(v_gaji.gaji_pokok, 0)::numeric
    * coalesce(v_setelan.bpjs_kesehatan_persen, 0) / 100)::bigint;
  v_bpjs_tk := floor(coalesce(v_gaji.gaji_pokok, 0)::numeric
    * coalesce(v_setelan.bpjs_tk_persen, 0) / 100)::bigint;

  return query select
    coalesce(v_gaji.gaji_pokok, 0)::bigint,
    coalesce(v_gaji.tunjangan, 0)::bigint,
    coalesce(v_setelan.hari_kerja_periode, 25),
    coalesce(v_h.h, 0), coalesce(v_h.i, 0), coalesce(v_h.s, 0),
    coalesce(v_h.c, 0), coalesce(v_h.al, 0), coalesce(v_h.p, 0),
    v_potong_absen, v_bpjs_kes, v_bpjs_tk,
    greatest(coalesce(v_gaji.gaji_pokok, 0) + coalesce(v_gaji.tunjangan, 0)
             - v_potong_absen - v_bpjs_kes - v_bpjs_tk, 0)::bigint,
    v_gaji.bank_name, v_gaji.account_number, v_gaji.account_holder;
end;
$fn$;

grant execute on function rekap_payroll(text, date, date) to authenticated;
grant execute on function slip_gaji_saya(text, date, date) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from rekap_payroll('<resto_id>', '2026-08-26', '2026-09-25');
--   select employee_email, tanggal, status, masuk_at, masuk_jarak_m
--   from attendance where resto_id = '<resto_id>' order by tanggal desc;

-- ─────────────────────────────────────────────────────────────────────
-- 8. Ember penyimpanan foto absen dan surat sakit
-- ─────────────────────────────────────────────────────────────────────
--
-- TIDAK publik, berbeda dari ember foto menu.
--
-- Isinya foto wajah karyawan dan surat keterangan sakit — dua hal yang
-- tidak boleh bisa dibuka siapa pun yang kebetulan menebak URL-nya.
-- Foto menu memang dipasang di etalase; ini tidak.
--
-- Nama berkasnya `<resto_id>/<jenis>/<email>_<waktu>.jpg`, dan segmen
-- pertama itu yang dipakai policy menentukan siapa boleh menulis.
-- Tanpa itu, karyawan merchant mana pun bisa menimpa berkas merchant
-- lain.

insert into storage.buckets (id, name, public)
values ('absensi', 'absensi', false)
on conflict (id) do update set public = false;

-- Menulis: karyawan merchant itu sendiri, peran apa pun. Semua orang
-- absen, termasuk Owner.
drop policy if exists "absensi: tulis karyawan" on storage.objects;
create policy "absensi: tulis karyawan" on storage.objects
  for insert with check (
    bucket_id = 'absensi'
    -- Disebut lengkap dengan skemanya. Policy pada storage.objects
    -- tidak dijalankan PostgREST melainkan layanan Storage, yang
    -- menyambung dengan search_path-nya sendiri — dan nama tanpa skema
    -- di sana bisa tidak ditemukan. Galatnya baru muncul saat seseorang
    -- benar-benar mengunggah, bukan saat policy-nya dibuat.
    and public.is_resto_employee((storage.foldername(name))[1],
          array['owner', 'admin', 'finance', 'kasir', 'chef'])
  );

-- Membaca: yang memeriksa absensi, bukan semua karyawan.
--
-- Kasir tidak perlu bisa membuka foto wajah dan surat sakit rekannya.
-- Yang membutuhkannya saat memutuskan potong gaji adalah Owner, Admin,
-- dan Finance — dan itu memang pekerjaan mereka.
drop policy if exists "absensi: baca atasan" on storage.objects;
create policy "absensi: baca atasan" on storage.objects
  for select using (
    bucket_id = 'absensi'
    and public.is_resto_employee((storage.foldername(name))[1],
          array['owner', 'admin', 'finance'])
  );

-- Menimpa berkas yang sudah ada.
--
-- PERHATIAN untuk yang menyentuh kode pengunggahnya nanti: JANGAN
-- memakai `upsert: true` di ember ini. Layanan Storage MEMBACA baris
-- objeknya lebih dulu untuk memutuskan sisip-atau-timpa, dan Kasir
-- maupun Chef sengaja tidak punya hak baca di sini — isinya foto wajah
-- dan surat sakit rekan-rekannya. Yang mereka terima 403 sebelum sempat
-- menulis apa pun, dan galatnya tidak menyebut izin sama sekali.
--
-- Nama berkasnya sudah memuat milidetik, jadi tidak ada yang perlu
-- ditimpa. Kebijakan ini tetap ada untuk berkas lama.
drop policy if exists "absensi: ubah karyawan" on storage.objects;
create policy "absensi: ubah karyawan" on storage.objects
  for update using (
    bucket_id = 'absensi'
    and public.is_resto_employee((storage.foldername(name))[1],
          array['owner', 'admin', 'finance', 'kasir', 'chef'])
  );

-- Menghapus sengaja tidak diberikan ke siapa pun.
--
-- Foto absen adalah bukti. Yang bisa menghapusnya adalah yang bisa
-- menghapus bukti bahwa dirinya tidak berada di tempat kerja — dan
-- seluruh guna menyimpannya hilang di situ.
