-- KaataGo — siapa yang boleh membuka shift, dan kapan dia belum boleh.
--
-- Jalankan SETELAH cashier_shift.sql dan cash_variance_lebih.sql.
-- Aman diulang.
--
-- Dua perubahan, keduanya di `open_shift`:
--
-- 1. Finance tidak lagi boleh membuka shift. Finance memeriksa uang;
--    yang memegang laci adalah Kasir. Orang yang memegang laci sekaligus
--    memeriksa selisihnya sendiri membuat pemeriksaannya tidak berarti.
--    Membaca riwayat dan menutup selisih tetap boleh — yang dicabut
--    hanya membuka lacinya.
--
-- 2. Yang masih punya selisih kurang belum boleh membuka shift lagi.
--    Selisih kurang adalah uang merchant yang ada pada orangnya. Selama
--    belum dilunasi, menyerahkan laci berikutnya berarti menumpuk
--    tanggungan di atas tanggungan.
--
--    Selisih LEBIH tidak menahan siapa pun. Uangnya ada di laci, bukan
--    di tangan kasirnya, dan yang menelusurinya Finance — menahan kasir
--    karena pekerjaan orang lain belum selesai adalah menghukum orang
--    yang tidak melakukan apa-apa.

begin;

create or replace function open_shift(p_resto_id text, p_opening_cash bigint)
returns cashier_shifts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_nama text;
  v_row cashier_shifts;
  v_utang bigint;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not is_resto_employee(p_resto_id,
        array['owner', 'admin', 'kasir']) then
    raise exception 'Tidak berhak membuka shift di merchant ini.';
  end if;

  if p_opening_cash is null or p_opening_cash < 0 then
    raise exception 'Modal awal tidak boleh minus.';
  end if;

  -- Tanggungannya sendiri, bukan tanggungan merchant. Kasir lain yang
  -- belum melunasi selisihnya bukan urusan orang ini.
  select coalesce(sum(v.amount), 0) into v_utang
  from cash_variances v
  where v.resto_id = p_resto_id
    and v.employee_email = v_email
    and v.kind = 'kurang'
    and v.status = 'open';

  if v_utang > 0 then
    raise exception
      'Masih ada selisih kurang Rp % yang belum dilunasi. '
      'Lunasi dulu sebelum membuka shift baru.',
      to_char(v_utang, 'FM999G999G999G999');
  end if;

  -- Diperiksa lebih dulu supaya pesannya bisa dibaca orang. Tanpa ini
  -- yang muncul adalah galat unique index — benar, tapi tidak memberi
  -- tahu apa pun kepada kasir yang sedang berdiri di depan antrean.
  if exists (
    select 1 from cashier_shifts s
    where s.resto_id = p_resto_id and s.closed_at is null
  ) then
    raise exception 'Masih ada shift yang belum ditutup di merchant ini.';
  end if;

  select e.name into v_nama
  from employees e
  where e.email = v_email and e.resto_id = p_resto_id
  limit 1;

  insert into cashier_shifts (
    resto_id, employee_email, employee_name, opening_cash)
  values (p_resto_id, v_email, v_nama, p_opening_cash)
  returning * into v_row;

  return v_row;
end;
$$;

commit;
