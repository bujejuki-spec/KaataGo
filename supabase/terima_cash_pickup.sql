-- KaataGo - serah terima cash pickup, dan dua akun GL untuknya.
--
-- Jalankan SETELAH setor_dan_pickup.sql dan tutup_buku_harian.sql.
-- Aman diulang.
--
-- Sampai sekarang cash pickup diperlakukan sama dengan setoran bank:
-- uang keluar laci, lalu langsung dianggap mendarat di Total Saldo. Itu
-- tidak benar, dan ketidakbenarannya persis di bagian yang paling mahal.
--
-- Uang yang dijemput petugas sedang TIDAK berada di mana pun yang bisa
-- ditunjuk: ia bukan lagi di laci, dan belum juga di tangan perusahaan.
-- Menganggapnya sudah sampai berarti tidak ada satu pun angka di
-- aplikasi ini yang bisa menjawab pertanyaan "mana uang yang dijemput
-- Selasa lalu dan tidak pernah diserahkan?". Pertanyaannya tidak bisa
-- ditanyakan, jadi jawabannya tidak pernah dicari.
--
-- Sekarang uangnya singgah di akun tersendiri:
--
--   laci  --(kasir/admin buat pickup)-->  GL Cash Pickup
--   GL Cash Pickup  --(Finance/Owner terima)-->  GL Saldo Cash Perusahaan
--
-- Saldo GL Cash Pickup yang tidak nol adalah daftar pekerjaan: uang yang
-- sudah dibawa pergi dan belum diakui diterima siapa pun.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Dua jenis akun GL baru
-- ─────────────────────────────────────────────────────────────────────

begin;

alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'qris_static', 'transfer', 'petty_cash',
     'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance', 'other_income',
     'cash_pickup', 'company_cash', 'company_bank'));

-- Cash Pickup sederet dengan akun titipan lain (21xxxxx): isinya bukan
-- milik siapa pun sampai serah terimanya selesai.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'cash_pickup', '2100004', 'GL Cash Pickup'
from restaurants r
on conflict (resto_id, payment_method) do nothing;

-- Saldo Cash Perusahaan sederet dengan GL Total Saldo (199xxxx): ini
-- uang yang benar-benar sudah dipegang perusahaan.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'company_cash', '1990002', 'GL Saldo Cash Perusahaan'
from restaurants r
on conflict (resto_id, payment_method) do nothing;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Kolom serah terimanya
-- ─────────────────────────────────────────────────────────────────────
--
-- Terpisah dari kolom review yang sudah ada, dan memang harus terpisah:
-- review menjawab "setorannya sah atau tidak", serah terima menjawab
-- "uangnya sudah ada di tangan kami". Menumpuk keduanya di satu kolom
-- membuat pickup yang disetujui tapi belum diserahkan tidak bisa
-- dibedakan dari yang sudah.

begin;

alter table cash_deposits add column if not exists received_at timestamptz;
alter table cash_deposits add column if not exists received_by text;

-- Nama karyawan yang menerima, dibekukan saat itu juga. Membacanya dari
-- `employees` setiap kali berarti tanda terima berubah isinya kalau
-- orangnya berganti nama atau keluar.
alter table cash_deposits add column if not exists received_by_name text;

-- Yang benar-benar dihitung saat diterima. Boleh berbeda dari nominal
-- yang dicatat kasir — dan kalau berbeda, itu justru temuannya. Angka
-- yang dipaksa sama dengan catatan awal tidak pernah bisa menemukan
-- apa pun.
alter table cash_deposits add column if not exists received_amount bigint;

-- Nomor segel yang dibaca penerima, dan bukti terimanya.
alter table cash_deposits add column if not exists received_seal text;
alter table cash_deposits add column if not exists receipt_proof text;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Pickup singgah di GL Cash Pickup, bukan langsung ke Total Saldo
-- ─────────────────────────────────────────────────────────────────────

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
  v_sebut text := case when v_pickup then 'Cash pickup' else 'Setor tunai' end;
begin
  -- Uang tunai meninggalkan laci → kredit GL Cash. Sama untuk keduanya:
  -- yang berbeda bukan lacinya, melainkan ke mana uangnya pergi.
  select * into v_cash_gl from _gl_account_for(new.resto_id, 'cash');
  if v_cash_gl.gl_code is not null and v_cash_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_cash_gl.gl_code, v_cash_gl.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'credit', v_sebut || ' #' || v_ref
    );
  end if;

  -- Setoran mendarat di rekening. Pickup belum mendarat di mana pun —
  -- ia sedang dibawa orang, dan itulah yang dicatat GL Cash Pickup.
  select * into v_lawan from _gl_account_for(
    new.resto_id, case when v_pickup then 'cash_pickup' else 'total_balance' end);
  if v_lawan.gl_code is not null and v_lawan.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_date, v_time,
      v_lawan.gl_code, v_lawan.gl_name, 'cash_deposit', new.id::text,
      new.amount, 'debit',
      case when v_pickup
           then 'Dijemput petugas #' || v_ref
           else 'Terima setoran tunai #' || v_ref end
    );
  end if;

  return new;
end;
$fn$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Serah terimanya
-- ─────────────────────────────────────────────────────────────────────
--
-- Hanya Finance dan Owner. Yang membuat pickup adalah kasir atau admin;
-- kalau ia juga yang menyatakan uangnya sudah diterima, tidak ada satu
-- pun tangan kedua di sepanjang jalannya uang itu.

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

  -- Namanya dibekukan di barisnya. Tanda terima yang isinya ikut
  -- berubah saat orangnya berganti nama bukan tanda terima.
  select e.name into v_nama
  from employees e
  where lower(e.email) = lower(v_email)
    and e.resto_id = v_row.resto_id
  limit 1;

  update cash_deposits set
    received_at = now(),
    received_by = v_email,
    received_by_name = coalesce(nullif(btrim(v_nama), ''), v_email),
    received_amount = p_amount,
    received_seal = nullif(btrim(coalesce(p_seal, '')), ''),
    receipt_proof = p_proof,
    picked_up_by = coalesce(nullif(btrim(picked_up_by), ''), btrim(p_officer))
  where id = p_id
  returning * into v_row;

  v_ref := upper(substr(v_row.id::text, 1, 8));

  -- Uang meninggalkan titipan → kredit GL Cash Pickup.
  select * into v_gl_pickup from _gl_account_for(v_row.resto_id, 'cash_pickup');
  if v_gl_pickup.gl_code is not null and v_gl_pickup.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      v_row.resto_id, v_date, v_time,
      v_gl_pickup.gl_code, v_gl_pickup.gl_name, 'cash_deposit',
      v_row.id::text, p_amount, 'credit', 'Serah terima pickup #' || v_ref
    );
  end if;

  -- Dan sampai di perusahaan → debit GL Saldo Cash Perusahaan.
  select * into v_gl_kas from _gl_account_for(v_row.resto_id, 'company_cash');
  if v_gl_kas.gl_code is not null and v_gl_kas.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      v_row.resto_id, v_date, v_time,
      v_gl_kas.gl_code, v_gl_kas.gl_name, 'cash_deposit',
      v_row.id::text, p_amount, 'debit',
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

-- ─────────────────────────────────────────────────────────────────────
-- 5. Tutup buku: Admin ikut
-- ─────────────────────────────────────────────────────────────────────
--
-- Menutup hari adalah pekerjaan operasional — memastikan shiftnya sudah
-- ditutup dan angkanya sudah berhenti bergerak. Yang tetap tidak
-- dipegang admin adalah rekonsiliasi mutasi bank: itu pemeriksaan, dan
-- pemeriksaan tidak dipegang orang yang sehari-hari memegang lacinya.

begin;

drop policy if exists "daily_settlements: finance write" on daily_settlements;
create policy "daily_settlements: finance write" on daily_settlements
  for all using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin'])
  ) with check (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin'])
  );

commit;
