-- KaataGo — selisih lebih shift kasir jadi titipan yang ditelusuri.
--
-- Jalankan SETELAH cash_variance.sql. Aman diulang.
--
-- Sampai sekarang selisih lebih hanya dijurnal — kredit ke GL Selisih
-- Kasir — lalu berhenti di situ. Tidak ada baris kerjanya, tidak ada
-- yang menutupnya, dan kreditnya menumpuk di 2100003 selamanya.
--
-- Yang lebih berbahaya: Saldo Cash tidak menghitungnya sama sekali.
-- Uangnya ADA di laci, tapi angkanya tidak mengakui — jadi saat kasir
-- menyetorkan seluruh isi laci, setorannya melebihi saldo yang
-- tercatat dan lacinya jadi minus. Itu persis penyakit yang dulu
-- diperbaiki untuk sisi kurang.
--
-- Kenapa tidak langsung diakui pendapatan: selisih lebih paling sering
-- berarti penjualan yang belum diinput. Mengakuinya sebagai pendapatan
-- saat itu juga membuat angkanya terhitung dua kali begitu pesanannya
-- dimasukkan belakangan. Jadi ia dititipkan dulu di 2100003 — memang
-- range titipan, bukan pendapatan — sampai ada yang menelusurinya.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Barisnya bisa berjenis kurang atau lebih
-- ─────────────────────────────────────────────────────────────────────
--
-- Baris yang sudah ada semuanya kurang: sampai commit ini, itu satu-
-- satunya jenis yang pernah dibuat.
alter table cash_variances
  add column if not exists kind text not null default 'kurang';

alter table cash_variances drop constraint if exists cash_variances_kind_check;
alter table cash_variances add constraint cash_variances_kind_check
  check (kind in ('kurang', 'lebih'));

-- Bagaimana barisnya ditutup. Null selama masih terbuka.
--
--   dibayar         — kasir menyerahkan uang sebesar kekurangannya
--   input_penjualan — penjualan yang terlewat sudah dimasukkan, jadi
--                     uangnya sekarang ada penjelasannya
--   pendapatan      — ditelusuri dan tidak ketemu; diakui pendapatan
alter table cash_variances
  add column if not exists resolution text;

alter table cash_variances drop constraint if exists cash_variances_resolution_check;
alter table cash_variances add constraint cash_variances_resolution_check
  check (resolution is null
         or resolution in ('dibayar', 'input_penjualan', 'pendapatan'));

-- ─────────────────────────────────────────────────────────────────────
-- 2. GL Pendapatan Lain-lain
-- ─────────────────────────────────────────────────────────────────────
--
-- Dipakai hanya saat selisih lebih benar-benar tidak ketemu asalnya.
-- Nomornya di rangkaian 195xxxx bersama akun pemasukan lain, bukan
-- 21xxxxx — begitu diakui, ia memang pendapatan.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital', 'cash_variance', 'other_income'));

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'other_income', '1950009', 'GL Pendapatan Lain-lain'
from restaurants r
where not exists (
  select 1 from gl_accounts g
  where g.resto_id = r.id and g.payment_method = 'other_income'
);

-- ─────────────────────────────────────────────────────────────────────
-- 3. Selisih lebih ikut melahirkan barisnya
-- ─────────────────────────────────────────────────────────────────────
create or replace function journal_cash_variance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_selisih bigint := coalesce(new.difference, 0);
  v_saat timestamptz := coalesce(new.closed_at, now());
  v_nama text := coalesce(nullif(btrim(coalesce(new.employee_name, '')), ''),
                          split_part(new.employee_email, '@', 1));
begin
  if new.closed_at is null or old.closed_at is not null then
    return new;
  end if;
  if v_selisih = 0 then
    return new;
  end if;

  select * into v_gl from _gl_account_for(new.resto_id, 'cash_variance');
  if v_gl.gl_code is null or v_gl.gl_code = '' then
    -- GL-nya belum dipetakan. Shiftnya tetap ditutup — menahan
    -- penutupan shift karena pemetaan GL berarti kasir tidak bisa
    -- pulang gara-gara urusan pembukuan.
    return new;
  end if;

  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    new.resto_id,
    (v_saat at time zone 'Asia/Jakarta')::date,
    (v_saat at time zone 'Asia/Jakarta')::time,
    v_gl.gl_code, v_gl.gl_name, 'cash_variance', new.id::text,
    abs(v_selisih),
    case when v_selisih < 0 then 'debit' else 'credit' end,
    case when v_selisih < 0
      then 'Selisih kurang shift ' || v_nama
      else 'Selisih lebih shift ' || v_nama
    end
  );

  -- Keduanya melahirkan baris kerja sekarang. Yang kurang jadi tagihan
  -- atas nama kasirnya; yang lebih jadi titipan yang harus ditelusuri
  -- Finance. Yang membedakan hanya siapa yang menutup dan bagaimana.
  insert into cash_variances (
    resto_id, shift_id, employee_email, employee_name, amount, note, kind)
  values (
    new.resto_id, new.id, new.employee_email, new.employee_name,
    abs(v_selisih), new.note,
    case when v_selisih < 0 then 'kurang' else 'lebih' end)
  on conflict (shift_id) do nothing;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Pelunasan yang lama dijaga agar tetap untuk yang kurang saja
-- ─────────────────────────────────────────────────────────────────────
create or replace function settle_cash_variance(
  p_id uuid,
  p_note text default null)
returns cash_variances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row cash_variances;
  v_gl record;
  v_saat timestamptz := now();
  v_hasil cash_variances;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  select * into v_row from cash_variances where id = p_id;
  if v_row is null then
    raise exception 'Tagihan selisihnya tidak ditemukan.';
  end if;

  -- Yang lebih tidak dibayar siapa-siapa. Tanpa penjaga ini, tombol
  -- Bayar Selisih akan mencatat kasir "melunasi" uang yang justru
  -- berlebih — dan jurnalnya menggandakan kreditnya, bukan menutupnya.
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
         settled_at = v_saat,
         settled_by = v_email,
         settle_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id
  returning * into v_hasil;

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
      'Pelunasan selisih kasir ' ||
        coalesce(nullif(btrim(coalesce(v_row.employee_name, '')), ''),
                 split_part(v_row.employee_email, '@', 1))
    );
  end if;

  return v_hasil;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5. Menelusuri selisih lebih
-- ─────────────────────────────────────────────────────────────────────
--
-- Dua jalan keluar, dan keduanya sama-sama mendebit GL Selisih Kasir
-- sebesar titipannya — titipannya memang dilepas.
--
--   input_penjualan  Penjualan yang terlewat sudah dimasukkan. Pesanan
--                    itu membawa jurnal pendapatannya sendiri, jadi di
--                    sini cukup melepas titipannya. Tidak ada kredit
--                    tandingan; kalau ada, pendapatannya terhitung dua
--                    kali — persis yang ingin dihindari.
--
--   pendapatan       Sudah ditelusuri dan tidak ketemu. Baru di sini
--                    uangnya diakui sebagai pendapatan lain-lain.
create or replace function resolve_cash_overage(
  p_id uuid,
  p_cara text,
  p_note text default null)
returns cash_variances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row cash_variances;
  v_gl record;
  v_gl_income record;
  v_saat timestamptz := now();
  v_hasil cash_variances;
  v_nama text;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if p_cara not in ('input_penjualan', 'pendapatan') then
    raise exception 'Cara penyelesaiannya tidak dikenali.';
  end if;

  select * into v_row from cash_variances where id = p_id;
  if v_row is null then
    raise exception 'Selisihnya tidak ditemukan.';
  end if;

  if v_row.kind <> 'lebih' then
    raise exception 'Ini selisih kurang; tutup lewat Bayar Selisih.';
  end if;

  -- Sengaja tanpa 'admin'. Yang memutuskan uang tak dikenal menjadi
  -- pendapatan adalah yang menanggung pembukuannya, dan admin merchant
  -- bukan pemegang buku.
  if not is_resto_employee(v_row.resto_id, array['owner', 'finance']) then
    raise exception 'Hanya Owner dan Finance yang boleh menyelesaikan '
                    'selisih lebih.';
  end if;

  if v_row.status = 'settled' then
    raise exception 'Selisih ini sudah diselesaikan.';
  end if;

  update cash_variances
     set status = 'settled',
         resolution = p_cara,
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
      v_row.amount, 'debit',
      case when p_cara = 'input_penjualan'
        then 'Selisih lebih shift ' || v_nama || ' — penjualannya sudah diinput'
        else 'Selisih lebih shift ' || v_nama || ' — diakui pendapatan'
      end
    );
  end if;

  if p_cara = 'pendapatan' then
    select * into v_gl_income from _gl_account_for(v_row.resto_id, 'other_income');
    if v_gl_income.gl_code is not null and v_gl_income.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        v_row.resto_id,
        (v_saat at time zone 'Asia/Jakarta')::date,
        (v_saat at time zone 'Asia/Jakarta')::time,
        v_gl_income.gl_code, v_gl_income.gl_name,
        'cash_variance', v_row.id::text,
        v_row.amount, 'credit',
        'Selisih lebih shift ' || v_nama || ' yang tidak ditemukan asalnya'
      );
    end if;
  end if;

  return v_hasil;
end;
$$;

commit;
