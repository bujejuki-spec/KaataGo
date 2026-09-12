-- KaataGo - setoran tunai yang disetujui mendarat di Saldo Bank
-- Perusahaan, bukan di GL Total Saldo.
--
-- Jalankan SETELAH saldo_perusahaan.sql. Aman diulang.
--
-- Perjalanan uang laci sekarang punya satu tujuan yang jelas untuk tiap
-- caranya, dan tidak ada lagi tempat singgah yang tidak bisa ditunjuk:
--
--   setor ke rekening
--     laci → GL Suspense Setor Tunai → (disetujui) → Saldo Bank Perusahaan
--
--   cash pickup
--     laci → GL Cash Pickup → (diterima) → Saldo Cash Perusahaan
--
-- Sebelumnya setoran yang disetujui dikreditkan ke GL Total Saldo — akun
-- payung yang menampung segalanya. Selama Saldo Perusahaan belum ada,
-- itu satu-satunya tempat yang masuk akal. Sekarang ada dua kantong yang
-- benar-benar menyebut di mana uangnya berada, dan uang rekening punya
-- namanya sendiri.
--
-- GL Total Saldo tidak dihapus dan barisnya yang lama tidak disentuh. Ia
-- berhenti menerima setoran BARU; setoran lama tetap berdiri di sana,
-- karena menghapusnya berarti menghapus uang yang benar-benar pernah
-- masuk.

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
  -- `terima_pickup`, berikut jumlah yang benar-benar dihitung penerima.
  if v_pickup and new.received_at is not null then
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
    -- Setoran bank → uang rekening. Pickup → uang tunai perusahaan.
    v_target := case when v_pickup then 'company_cash' else 'company_bank' end;
    v_note := v_sebut || ' #' || v_ref || ' masuk ' ||
      case when v_pickup then 'kas perusahaan' else 'rekening' end;
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

-- Setoran yang sudah disetujui sebelum berkas ini.
--
-- saldo_perusahaan.sql sempat menuliskan sisi rekeningnya sebagai baris
-- TAMBAHAN di samping GL Total Saldo, jadi sebagian setoran mungkin
-- sudah punya barisnya. Yang belum dilengkapi di sini; yang sudah
-- dilewati.

begin;

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  d.resto_id,
  (d.reviewed_at at time zone 'Asia/Jakarta')::date,
  (d.reviewed_at at time zone 'Asia/Jakarta')::time,
  a.gl_code,
  a.gl_name,
  'cash_deposit',
  d.id::text,
  d.amount,
  'credit',
  'Setoran #' || upper(substr(d.id::text, 1, 8)) || ' masuk rekening'
from cash_deposits d
join gl_accounts a
  on a.resto_id = d.resto_id
 and a.payment_method = 'company_bank'
 and coalesce(a.gl_code, '') <> ''
where d.status = 'approved'
  and coalesce(d.method, 'setor') = 'setor'
  and d.reviewed_at is not null
  and not exists (
    select 1 from gl_journal_entries j
    where j.resto_id = d.resto_id
      and j.reference_type = 'cash_deposit'
      and j.reference_id = d.id::text
      and j.gl_code = a.gl_code
  );

commit;
