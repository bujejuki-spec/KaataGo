-- KaataGo - jurnal cash pickup diperbaiki, dan jalur Suspense dipulihkan.
--
-- Jalankan SETELAH terima_cash_pickup.sql. Aman diulang.
--
-- Tiga kekeliruan, dan dua di antaranya saya buat sendiri di
-- terima_cash_pickup.sql.
--
-- ── 1. Arah debit-kreditnya terbalik ─────────────────────────────────
--
-- Seluruh pembukuan aplikasi ini memakai satu arah: uang MENINGGALKAN
-- sebuah akun dicatat debit, uang MASUK ke sebuah akun dicatat kredit.
-- Itu yang dipakai setoran tunai, petty cash, dan semuanya.
--
-- Jurnal pickup yang saya tulis memakai arah kebalikannya. Saya
-- menyalinnya dari cash_deposit.sql — berkas lama yang memang berarah
-- sebaliknya dan sudah lama digantikan rilis_setor_petty_inbox.sql.
-- Akibatnya panah dan warnanya terbaca terbalik di Jurnal GL, dan itu
-- persis yang terlihat.
--
-- ── 2. Jalur Suspense ikut tertimpa ──────────────────────────────────
--
-- terima_cash_pickup.sql menulis ulang log_cash_deposit_journal
-- seluruhnya, dan yang ditulis ulang itu versi LAMA. Jadi sejak
-- dijalankan, setoran bank biasa berhenti singgah di GL Suspense
-- Setoran dan langsung masuk Total Saldo — persetujuan Finance jadi
-- tidak punya bekas apa pun di pembukuan.
--
-- ── 3. Pickup yang ditolak dilepas dari akun yang salah ──────────────
--
-- Pickup masuk lewat GL Cash Pickup, tapi penolakannya melepas titipan
-- dari GL Suspense Setoran — akun yang tidak pernah menerima uang itu.
-- Hasilnya persis seperti yang dibilang: tidak balance. GL Suspense
-- jadi minus sebesar pickup yang ditolak, dan GL Cash Pickup menyimpan
-- uang yang sudah kembali ke laci.
--
-- Sesudah berkas ini, alurnya:
--
--   setor  : Cash (debit) → Suspense (kredit)
--            disetujui  : Suspense (debit) → Total Saldo (kredit)
--            ditolak    : Suspense (debit) → Cash (kredit)
--
--   pickup : Cash (debit) → GL Cash Pickup (kredit)
--            diterima   : GL Cash Pickup (debit) → Saldo Cash Perusahaan (kredit)
--            ditolak    : GL Cash Pickup (debit) → Cash (kredit)

begin;

create or replace function log_cash_deposit_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cash_gl record;
  v_lawan record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_pickup boolean := coalesce(new.method, 'setor') = 'pickup';
begin
  -- Uang meninggalkan laci → debit GL Cash. Sama untuk keduanya.
  select * into v_cash_gl from _gl_account_for(new.resto_id, 'cash');
  if v_cash_gl.gl_code is not null and v_cash_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_cash_gl.gl_code, v_cash_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit',
      case when v_pickup
           then 'Cash pickup #' || v_ref || ' (menunggu serah terima)'
           else 'Setor tunai #' || v_ref || ' (menunggu approval)' end
    );
  end if;

  -- Dan singgah: setoran di GL Suspense, pickup di GL Cash Pickup.
  -- Keduanya titipan, bedanya siapa yang harus menyelesaikannya.
  select * into v_lawan from _gl_account_for(
    new.resto_id, case when v_pickup then 'cash_pickup' else 'suspense' end);
  if v_lawan.gl_code is not null and v_lawan.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_lawan.gl_code, v_lawan.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit',
      case when v_pickup
           then 'Dijemput petugas #' || v_ref
           else 'Titipan setoran #' || v_ref end
    );
  end if;

  return new;
end;
$fn$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Disetujui atau ditolak: dilepas dari akun yang memang menerimanya
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function log_cash_deposit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_titipan_gl record;
  v_target_gl record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_pickup boolean := coalesce(new.method, 'setor') = 'pickup';
  v_sebut text := case when v_pickup then 'Cash pickup' else 'Setoran' end;
  v_target text;
  v_note text;
begin
  if new.status = old.status or old.status <> 'pending' then
    return new;
  end if;

  -- Pickup yang baru saja diterima menulis jurnalnya sendiri di
  -- `terima_pickup`, berikut jumlah yang benar-benar dihitung penerima —
  -- yang boleh berbeda dari yang dicatat kasir. Kalau trigger ini ikut
  -- bekerja, uang yang sama tercatat dua kali, dan yang kedua memakai
  -- angka yang salah.
  --
  -- Diperiksa lewat `received_at`, bukan dengan mematikan triggernya:
  -- mematikan trigger menuntut kunci tabel yang menahan seluruh kasir
  -- yang sedang mencatat setoran.
  if coalesce(new.method, 'setor') = 'pickup' and new.received_at is not null then
    return new;
  end if;

  -- Dilepas dari akun tempat uangnya singgah — dan itu bergantung pada
  -- caranya keluar laci, bukan pada satu akun yang dipakai semuanya.
  select * into v_titipan_gl from _gl_account_for(
    new.resto_id, case when v_pickup then 'cash_pickup' else 'suspense' end);
  if v_titipan_gl.gl_code is not null and v_titipan_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_titipan_gl.gl_code, v_titipan_gl.gl_name, 'cash_deposit',
      new.id::text, new.amount, 'debit',
      'Titipan ' || lower(v_sebut) || ' #' || v_ref || ' dilepas'
    );
  end if;

  if new.status = 'approved' then
    -- Pickup yang disetujui lewat jalur ini jarang terjadi — serah
    -- terimanya punya fungsinya sendiri. Tetap diarahkan ke akun yang
    -- benar supaya tidak ada jalan yang meninggalkan jurnal timpang.
    v_target := case when v_pickup then 'company_cash' else 'total_balance' end;
    v_note := v_sebut || ' #' || v_ref || ' disetujui';
  else
    -- Ditolak: uangnya kembali menjadi tanggung jawab laci kasir.
    v_target := 'cash';
    v_note := v_sebut || ' #' || v_ref || ' ditolak, kembali ke kas';
  end if;

  select * into v_target_gl from _gl_account_for(new.resto_id, v_target);
  if v_target_gl.gl_code is not null and v_target_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_target_gl.gl_code, v_target_gl.gl_name, 'cash_deposit',
      new.id::text, new.amount, 'credit', v_note
    );
  end if;

  return new;
end;
$fn$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Serah terimanya, dengan arah yang benar
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function terima_pickup(
  p_id uuid,
  p_amount bigint,
  p_officer text,
  p_proof text,
  p_seal text default null
)
returns cash_deposits
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row cash_deposits;
  v_nama text;
  v_gl_pickup record;
  v_gl_kas record;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_time time := (now() at time zone 'Asia/Jakarta')::time;
  v_ref text;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  select * into v_row from cash_deposits where id = p_id;
  if not found then
    raise exception 'Pickup tidak ditemukan.';
  end if;

  if not (is_super_admin()
          or is_resto_employee(v_row.resto_id, array['owner', 'finance'])) then
    raise exception 'Hanya Finance dan Owner yang bisa menerima cash pickup.';
  end if;

  if coalesce(v_row.method, 'setor') <> 'pickup' then
    raise exception 'Yang ini setoran bank, bukan cash pickup.';
  end if;

  if v_row.received_at is not null then
    raise exception 'Pickup ini sudah diterima.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Jumlah yang diterima wajib diisi.';
  end if;

  if coalesce(btrim(p_officer), '') = '' then
    raise exception 'Nama petugas yang menyerahkan wajib diisi.';
  end if;

  if coalesce(btrim(p_proof), '') = '' then
    raise exception 'Bukti terima wajib dilampirkan.';
  end if;

  select e.name into v_nama
  from employees e
  where lower(e.email) = lower(v_email)
    and e.resto_id = v_row.resto_id
  limit 1;

  -- Statusnya ikut jadi 'approved' supaya pickup yang sudah diserahkan
  -- berhenti terhitung sebagai pengajuan yang menunggu keputusan.
  -- Jurnalnya ditulis di bawah, bukan oleh trigger review — trigger itu
  -- sudah tahu harus mundur begitu `received_at` terisi.
  update cash_deposits set
    received_at = now(),
    received_by = v_email,
    received_by_name = coalesce(nullif(btrim(v_nama), ''), v_email),
    received_amount = p_amount,
    received_seal = nullif(btrim(coalesce(p_seal, '')), ''),
    receipt_proof = p_proof,
    status = 'approved',
    reviewed_by = v_email,
    reviewed_at = now(),
    picked_up_by = coalesce(nullif(btrim(picked_up_by), ''), btrim(p_officer))
  where id = p_id
  returning * into v_row;

  v_ref := upper(substr(v_row.id::text, 1, 8));

  -- Uang meninggalkan titipan → debit GL Cash Pickup.
  select * into v_gl_pickup from _gl_account_for(v_row.resto_id, 'cash_pickup');
  if v_gl_pickup.gl_code is not null and v_gl_pickup.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      v_row.resto_id, v_date, v_time,
      v_gl_pickup.gl_code, v_gl_pickup.gl_name, 'cash_deposit',
      v_row.id::text, p_amount, 'debit', 'Serah terima pickup #' || v_ref
    );
  end if;

  -- Dan sampai di perusahaan → kredit GL Saldo Cash Perusahaan.
  select * into v_gl_kas from _gl_account_for(v_row.resto_id, 'company_cash');
  if v_gl_kas.gl_code is not null and v_gl_kas.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      v_row.resto_id, v_date, v_time,
      v_gl_kas.gl_code, v_gl_kas.gl_name, 'cash_deposit',
      v_row.id::text, p_amount, 'credit',
      'Terima cash pickup #' || v_ref ||
      case when p_amount <> v_row.amount
           then ' (dicatat ' || to_char(v_row.amount, 'FM999G999G999G999') || ')'
           else '' end
    );
  end if;

  return v_row;
end;
$fn$;

revoke all on function terima_pickup(uuid, bigint, text, text, text)
  from public, anon;
grant execute on function terima_pickup(uuid, bigint, text, text, text)
  to authenticated;

commit;
