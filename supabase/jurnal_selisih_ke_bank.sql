-- KaataGo - selisih kasir yang dilunasi transfer ikut masuk Saldo Bank.
--
-- Jalankan SETELAH saldo_perusahaan.sql dan cash_variance_lebih.sql.
-- Aman diulang.
--
-- Kasir yang menombok kekurangan lacinya boleh membayar dengan dua cara:
-- menyerahkan uang tunai — yang langsung masuk laci lagi — atau
-- mentransfernya. Yang kedua mendarat di rekening merchant, persis
-- seperti penjualan QRIS dan transfer pelanggan.
--
-- Sampai sekarang jurnalnya berhenti di GL Selisih Kasir: titipannya
-- dilepas, tapi tidak ada satu baris pun yang menyebut ke mana uangnya
-- pergi. Di layar Saldo & Pengeluaran ia memang ikut Saldo Non Cash,
-- jadi angkanya terlihat — tapi Saldo Bank Perusahaan, yang dihitung
-- dari jurnal, tidak pernah tahu uang itu ada.
--
-- Sesudah berkas ini, semua yang mendarat di rekening punya barisnya di
-- sana: penjualan non-tunai, setoran kasir yang disetujui, setoran dari
-- kas perusahaan, top up modal non-tunai, dan pelunasan selisih lewat
-- transfer.
--
-- ── Yang TIDAK ikut, dan kenapa ─────────────────────────────────────
--
-- Selisih LEBIH yang diakui sebagai pendapatan lain-lain tidak masuk
-- Saldo Bank. Uangnya tidak pernah ditransfer siapa pun — ia lembaran
-- yang berlebih di laci kasir, dan sampai disetor atau dijemput, ia
-- tetap di laci. Mencatatnya sebagai uang rekening berarti Saldo Bank
-- menyebut uang yang bisa dipegang tangan di tempat lain.
--
-- Perjalanannya ke rekening tetap ada, lewat jalur yang sudah berjalan:
-- setoran kasir, atau cash pickup.

begin;

create or replace function settle_cash_variance(
  p_id uuid,
  p_note text default null,
  p_method text default 'cash')
returns cash_variances
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row cash_variances;
  v_gl record;
  v_bank record;
  v_saat timestamptz := now();
  v_hasil cash_variances;
  v_nama text;
  v_cara text := coalesce(nullif(btrim(coalesce(p_method, '')), ''), 'cash');
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if v_cara not in ('cash', 'transfer') then
    raise exception 'Cara pembayarannya tidak dikenali.';
  end if;

  select * into v_row from cash_variances where id = p_id;
  if v_row is null then
    raise exception 'Tagihan selisihnya tidak ditemukan.';
  end if;

  if v_row.kind <> 'kurang' then
    raise exception 'Selisih lebih tidak dibayar; telusuri lewat '
                    'resolve_cash_overage.';
  end if;

  if not is_resto_employee(v_row.resto_id, array['owner', 'finance', 'admin']) then
    raise exception 'Hanya Owner, Finance, dan Admin yang boleh mencatat '
                    'pembayaran selisih.';
  end if;

  if v_row.status = 'settled' then
    raise exception 'Selisih ini sudah dilunasi.';
  end if;

  update cash_variances
     set status = 'settled',
         resolution = 'dibayar',
         settle_method = v_cara,
         settled_at = v_saat,
         settled_by = v_email,
         settle_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id
  returning * into v_hasil;

  v_nama := coalesce(nullif(btrim(coalesce(v_row.employee_name, '')), ''),
                     split_part(v_row.employee_email, '@', 1));

  select * into v_gl from _gl_account_for(v_row.resto_id, 'cash_variance');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      v_row.resto_id,
      (v_saat at time zone 'Asia/Jakarta')::date,
      (v_saat at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name, 'cash_variance', v_row.id::text,
      v_row.amount, 'credit',
      'Pelunasan selisih kasir ' || v_nama ||
        case when v_cara = 'transfer' then ' (transfer)' else ' (tunai)' end
    );
  end if;

  -- Dibayar transfer: uangnya mendarat di rekening merchant.
  --
  -- Yang dibayar tunai tidak ikut — lembarannya kembali ke laci, dan
  -- laci sudah menghitungnya lewat jalurnya sendiri.
  if v_cara = 'transfer' then
    select * into v_bank from _gl_account_for(v_row.resto_id, 'company_bank');
    if v_bank.gl_code is not null and v_bank.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        v_row.resto_id,
        (v_saat at time zone 'Asia/Jakarta')::date,
        (v_saat at time zone 'Asia/Jakarta')::time,
        v_bank.gl_code, v_bank.gl_name, 'cash_variance', v_row.id::text,
        v_row.amount, 'credit',
        'Pelunasan selisih ' || v_nama || ' masuk rekening'
      );
    end if;
  end if;

  return v_hasil;
end;
$fn$;

grant execute on function settle_cash_variance(uuid, text, text) to authenticated;

commit;

-- Pelunasan transfer yang sudah terlanjur tercatat sebelum berkas ini.
--
-- Barisnya di GL Selisih Kasir sudah benar dan tidak disentuh; yang
-- ditambahkan cuma sisi rekeningnya, yang memang belum pernah ada.
-- Aman diulang: yang sudah punya barisnya dilewati.

begin;

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  v.resto_id,
  (v.settled_at at time zone 'Asia/Jakarta')::date,
  (v.settled_at at time zone 'Asia/Jakarta')::time,
  a.gl_code,
  a.gl_name,
  'cash_variance',
  v.id::text,
  v.amount,
  'credit',
  'Pelunasan selisih ' ||
    coalesce(nullif(btrim(coalesce(v.employee_name, '')), ''),
             split_part(v.employee_email, '@', 1)) || ' masuk rekening'
from cash_variances v
join gl_accounts a
  on a.resto_id = v.resto_id
 and a.payment_method = 'company_bank'
 and coalesce(a.gl_code, '') <> ''
where v.kind = 'kurang'
  and v.status = 'settled'
  and v.settle_method = 'transfer'
  and v.settled_at is not null
  and not exists (
    select 1 from gl_journal_entries j
    where j.resto_id = v.resto_id
      and j.reference_type = 'cash_variance'
      and j.reference_id = v.id::text
      and j.gl_code = a.gl_code
  );

commit;
