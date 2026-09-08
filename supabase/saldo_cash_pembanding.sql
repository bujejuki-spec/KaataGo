-- KaataGo - buka dan tutup shift dibandingkan dengan Saldo Cash.
--
-- Jalankan SETELAH cash_variance_lebih.sql. Aman diulang.
--
-- Sampai sekarang ada dua angka berbeda yang sama-sama mengaku menyebut
-- "yang seharusnya ada di laci":
--
--   Saldo Cash       - dihitung dari seluruh pemasukan tunai merchant,
--                      dikurangi setoran, petty cash, dan selisih kurang
--                      yang belum dibayar, ditambah selisih lebih yang
--                      uangnya masih di laci. Ini yang dipercaya
--                      pembukuan.
--
--   shift_expected   - dimulai dari `opening_cash` yang DIKETIK kasir,
--                      lalu ditambah penjualan sepanjang shift itu saja.
--
-- Keduanya berpisah sejak kasir pertama mengetik modal awal yang berbeda
-- dari isi laci menurut pembukuan, dan setelah itu tidak pernah bertemu
-- lagi: tiap shift berikutnya membangun perkiraannya di atas angka
-- ketikan sebelumnya, bukan di atas pembukuan. Selisih yang sudah
-- tercatat pun tidak pernah ikut diperhitungkan.
--
-- Sekarang keduanya memakai angka yang sama.
--
-- Rumus di bawah harus sama persis dengan cashOnHand() di
-- lib/utils/cash_balance.dart. Dua tempat yang menghitung hal yang sama
-- dengan kode masing-masing akan berpisah pada perubahan berikutnya -
-- itu sudah terjadi dua kali di aplikasi ini, dan keduanya baru
-- ketahuan setelah angkanya dipakai orang.

begin;

create or replace function saldo_cash_laci(p_resto_id text)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select
    -- Seluruh pemasukan tunai merchant, sejak awal. Bukan sepanjang
    -- shift: yang ditanyakan adalah berapa lembar yang seharusnya ada di
    -- laci sekarang, dan laci tidak dikosongkan tiap ganti shift.
    coalesce((
      select sum(o.total)
      from orders o
      where o.resto_id = p_resto_id
        and o.payment_status = 'paid'
        and o.payment_method = 'cash'
    ), 0)

    -- Sudah keluar laci lewat setoran. Yang menunggu persetujuan ikut
    -- dihitung - fisiknya memang sudah tidak ada sejak diserahkan.
    - coalesce((
        select sum(d.amount)
        from cash_deposits d
        where d.resto_id = p_resto_id
          and d.status <> 'rejected'
      ), 0)

    -- Pindah ke petty cash.
    - coalesce((
        select sum(p.amount)
        from petty_cash_entries p
        where p.resto_id = p_resto_id
          and p.source = 'cash_withdrawal'
          and p.status <> 'rejected'
      ), 0)

    -- Selisih kurang yang uangnya tidak ada di laci.
    --
    -- Yang dibayar tunai berhenti dikurangkan - uangnya kembali ke laci.
    -- Yang dibayar TRANSFER tetap dikurangkan selamanya: uang yang
    -- hilang dari laci tidak pernah kembali ke laci, yang bertambah
    -- rekening merchant.
    - coalesce((
        select sum(v.amount)
        from cash_variances v
        where v.resto_id = p_resto_id
          and v.kind = 'kurang'
          and (v.status <> 'settled' or v.settle_method = 'transfer')
      ), 0)

    -- Selisih lebih yang uangnya masih di laci.
    --
    -- Ditambahkan karena uangnya memang ADA - itulah artinya berlebih.
    -- Yang berhenti dihitung cuma yang diselesaikan dengan
    -- 'input_penjualan': pesanan yang baru dimasukkan sudah membawa
    -- uangnya lewat pemasukan tunai di atas, dan menghitungnya lagi di
    -- sini berarti uang yang sama dua kali.
    --
    -- Yang diakui sebagai pendapatan TETAP dihitung: yang berubah cuma
    -- pengakuannya di pembukuan, lembarannya tidak ke mana-mana.
    + coalesce((
        select sum(v.amount)
        from cash_variances v
        where v.resto_id = p_resto_id
          and v.kind = 'lebih'
          and v.resolution is distinct from 'input_penjualan'
      ), 0);
$$;

grant execute on function saldo_cash_laci(text) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Tutup shift memakai Saldo Cash sebagai pembandingnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Badannya disalin apa adanya dari cashier_shift.sql; yang berubah cuma
-- satu baris, dari shift_expected_cash ke saldo_cash_laci.
--
-- Akibat yang perlu disadari: `opening_cash` tidak lagi ikut menentukan
-- apa pun. Itu memang tujuannya - selama ia ikut, angka ketikan seorang
-- kasir jadi dasar perhitungan seluruh shift sesudahnya, dan pembukuan
-- tidak pernah bisa mengoreksinya.
--
-- shift_expected_cash sengaja tidak dihapus: ia masih dipakai layar
-- untuk menunjukkan perkiraan berjalan, dan membuang fungsi yang masih
-- dipanggil berarti menukar satu masalah dengan satu galat.

begin;

create or replace function close_shift(
  p_shift_id uuid,
  p_counted_cash bigint,
  p_note text default null)
returns cashier_shifts
language plpgsql
security definer
set search_path = public
as $$
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

  -- Yang membuka boleh menutup shiftnya sendiri. Selain itu harus
  -- atasan — kasir yang kebetulan sedang login tidak boleh menutup
  -- shift orang lain lalu meninggalkan selisihnya atas nama orang itu.
  if v_email <> v_shift.employee_email
     and not is_resto_employee(v_shift.resto_id,
           array['owner', 'finance', 'admin']) then
    raise exception 'Hanya yang membuka shift ini, atau atasannya, yang '
                    'boleh menutupnya.';
  end if;

  if p_counted_cash is null or p_counted_cash < 0 then
    raise exception 'Uang yang dihitung tidak boleh minus.';
  end if;

  -- Satu-satunya baris yang berubah.
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
$$;

commit;
