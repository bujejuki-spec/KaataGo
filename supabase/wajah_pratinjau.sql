-- KaataGo - memeriksa wajahnya sebelum fotonya diunggah.
--
-- Jalankan SETELAH wajah_facenet.sql. Aman diulang.
--
-- ── Apa yang diperbaiki ──────────────────────────────────────────────
--
-- Urutan lamanya: pindai wajah, unggah fotonya, baru absen. Penolakan
-- datang di langkah ketiga — sesudah fotonya terlanjur naik.
--
-- Untuk yang absennya ditolak karena bukan orangnya, itu berarti foto
-- wajahnya sudah tersimpan di penyimpanan merchant padahal absennya
-- tidak pernah jadi. Untuk yang ditolak karena cahaya pagi, itu berarti
-- menunggu unggahan selesai cuma untuk dikabari harus mengulang.
--
-- Fungsi ini memindahkan penolakannya ke depan, sejajar dengan
-- pemeriksaan mata terpejam dan wajah miring yang memang sudah terjadi
-- di HP sebelum apa pun dikirim.
--
-- ── Kenapa tidak dicocokkan di HP saja ───────────────────────────────
--
-- Karena untuk mencocokkan di HP, HP harus memegang sidik wajah yang
-- terdaftar — dan sidik yang bisa diunduh aplikasi adalah sidik yang
-- bisa dikirim balik sebagai "hasil pemindaian". Absennya berhenti
-- membuktikan ada orang di depan kamera.
--
-- Itu sebabnya `employee_faces` sengaja tidak punya satu pun kebijakan
-- SELECT, dan itu tidak dilonggarkan di sini. Yang dikirim ke server
-- cuma 128 angka hasil pindaian, jauh lebih ringan daripada satu foto.
--
-- ── Kenapa jawabannya cuma ya atau tidak ─────────────────────────────
--
-- Skornya TIDAK dikembalikan, dan ini bukan kepelitan.
--
-- Fungsi yang menjawab "0,38" untuk satu tebakan dan "0,41" untuk
-- tebakan berikutnya adalah alat untuk menaiki bukit: siapa pun bisa
-- mengubah-ubah angkanya sedikit demi sedikit sambil melihat skornya
-- naik, sampai lolos tanpa pernah menghadap kamera. Yang menjawab "ya"
-- atau "tidak" tidak memberi arah untuk didaki.
--
-- ── Ini kenyamanan, bukan penjagaan ──────────────────────────────────
--
-- Yang menentukan sah tidaknya absen tetap pemeriksaan di dalam
-- _absen(). Fungsi ini boleh dilewati sepenuhnya oleh siapa pun yang
-- memanggil absen_masuk() langsung — dan tidak ada yang hilang kalau
-- dilewati, karena _absen() memeriksa hal yang sama sekali lagi.

begin;

create or replace function cocokkan_wajah(
  p_resto_id text,
  p_embedding double precision[],
  p_model text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_wajah record;
begin
  if v_email = '' then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
       array['owner', 'admin', 'finance', 'kasir', 'chef']) then
    raise exception 'Kamu bukan karyawan merchant ini.';
  end if;

  if p_embedding is null or array_length(p_embedding, 1) is null then
    raise exception 'Sidik wajahnya kosong. Ulangi pemindaian.';
  end if;

  select * into v_wajah from employee_faces
  where resto_id = p_resto_id and lower(employee_email) = v_email;

  -- Belum terdaftar bukan urusan fungsi ini. Yang menjawabnya layar
  -- absensi, dan menjawabnya di sini cuma memindahkan pesan yang sama
  -- ke tempat yang lebih membingungkan.
  if v_wajah is null then
    return false;
  end if;

  if coalesce(v_wajah.model, '') <> coalesce(p_model, '') then
    return false;
  end if;

  return _mirip(v_wajah.embedding, p_embedding, v_wajah.model)
         >= _ambang(v_wajah.model);
end;
$fn$;

revoke all on function cocokkan_wajah(text, double precision[], text)
  from public, anon;
grant execute on function cocokkan_wajah(text, double precision[], text)
  to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select proname, prorettype::regtype
--   from pg_proc where proname = 'cocokkan_wajah';
--
-- Yang benar: satu baris, dan tipe kembaliannya `boolean` — bukan
-- `double precision`. Kalau suatu hari ia berubah jadi mengembalikan
-- skor, bacalah lagi catatan "kenapa jawabannya cuma ya atau tidak" di
-- atas sebelum melanjutkan.
