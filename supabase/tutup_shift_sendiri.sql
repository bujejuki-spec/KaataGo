-- KaataGo - shift hanya bisa ditutup oleh yang membukanya.
--
-- Jalankan SETELAH saldo_cash_pembanding.sql. Aman diulang.
--
-- Sampai sekarang Owner, Admin, dan Finance boleh menutup shift siapa
-- pun. Niatnya menolong: kasir yang pulang tanpa menutup shift
-- meninggalkan laci yang menggantung, dan seseorang harus bisa
-- menyelesaikannya.
--
-- Tapi yang terjadi sebenarnya lebih buruk daripada laci yang
-- menggantung. Menutup shift berarti menghitung uang laci dan
-- menandatangani selisihnya — dan selisih itu tercatat ATAS NAMA
-- KASIRNYA, lalu jadi tagihan atas namanya kalau kurang. Atasan yang
-- menutup shift orang lain membuat tagihan atas nama orang yang tidak
-- ada di sana saat uangnya dihitung, dan orang itu tidak punya cara
-- membantahnya.
--
-- Jadi sekarang: yang membuka, itu yang menutup. Titik.
--
-- Owner dan Admin tetap melihat shift yang sedang berjalan dan seluruh
-- riwayatnya — yang dicabut cuma tangannya, bukan matanya.
--
-- ── Lalu bagaimana kalau kasirnya benar-benar pulang? ────────────────
--
-- Shiftnya tetap terbuka sampai ia masuk lagi dan menutupnya. Itu
-- memang merepotkan, dan kerepotan itu yang membuat orang berhenti
-- pulang tanpa menutup shift. Yang tidak boleh terjadi adalah tagihan
-- selisih lahir atas nama orang yang tidak pernah menghitung uangnya.

begin;

create or replace function close_shift(
  p_shift_id uuid,
  p_counted_cash bigint,
  p_note text default null)
returns cashier_shifts
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_shift cashier_shifts;
  v_expected bigint;
  v_saat timestamptz := now();
  v_row cashier_shifts;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  select * into v_shift from cashier_shifts where id = p_shift_id;
  if v_shift is null then
    raise exception 'Shiftnya tidak ditemukan.';
  end if;

  if v_shift.closed_at is not null then
    raise exception 'Shift ini sudah ditutup.';
  end if;

  -- Hanya yang membukanya. Atasan pun tidak.
  if lower(v_email) <> lower(coalesce(v_shift.employee_email, '')) then
    raise exception 'Shift ini dibuka %. Hanya dia yang bisa menutupnya, '
                    'karena selisihnya tercatat atas namanya.',
      coalesce(nullif(btrim(coalesce(v_shift.employee_name, '')), ''),
               v_shift.employee_email);
  end if;

  if p_counted_cash is null or p_counted_cash < 0 then
    raise exception 'Uang yang dihitung tidak boleh minus.';
  end if;

  v_expected := saldo_cash_laci(v_shift.resto_id);

  update cashier_shifts
     set closed_at = v_saat,
         counted_cash = p_counted_cash,
         expected_cash = v_expected,
         difference = p_counted_cash - v_expected,
         note = nullif(btrim(coalesce(p_note, '')), ''),
         closed_by = v_email
   where id = p_shift_id
  returning * into v_row;

  return v_row;
end;
$fn$;

commit;
