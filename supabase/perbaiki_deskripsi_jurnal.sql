-- KaataGo - membetulkan deskripsi jurnal yang huruf pisahnya rusak.
--
-- Jalankan SETELAH cash_variance_lebih.sql. Aman diulang.
--
-- Sebabnya bukan di database dan bukan di aplikasi: berkas SQL-nya
-- disalin ke papan klip lewat `pbcopy` di terminal yang LC_CTYPE-nya
-- "C". Dalam keadaan itu pbcopy membaca masukannya sebagai MacRoman,
-- bukan UTF-8, jadi tiga byte tanda pisah panjang (E2 80 94) berubah
-- jadi tiga huruf terpisah sebelum sempat ditempel ke SQL Editor.
-- Yang tersimpan di fungsinya, dan ikut tertulis ke tiap baris jurnal
-- yang dilahirkannya, adalah tiga huruf itu.
--
-- Dua hal diperbaiki: fungsinya ditulis ulang, dan baris jurnal yang
-- terlanjur lahir dibetulkan teksnya.
--
-- Deskripsi yang tersimpan sekarang memakai tanda hubung biasa. Bukan
-- karena tanda pisah panjang itu salah, tapi karena teks yang harus
-- melewati papan klip, editor, dan penyalinan orang tidak sepantasnya
-- bergantung pada satu huruf yang tidak selamat di semua jalur itu.

begin;

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
        then 'Selisih lebih shift ' || v_nama || ' - penjualannya sudah diinput'
        else 'Selisih lebih shift ' || v_nama || ' - diakui pendapatan'
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

-- Baris jurnal yang terlanjur lahir dengan huruf rusaknya.
--
-- Diperbaiki, bukan dihapus: nominal dan jurnalnya sendiri sudah benar,
-- dan menghapus baris jurnal demi kesalahan pengetikan berarti menukar
-- cacat tampilan dengan cacat pembukuan.
-- Huruf rusaknya ditulis sebagai titik kode, bukan diketik apa adanya.
--
-- Berkas ini sendiri harus melewati papan klip dan editor yang sama
-- yang merusak aslinya. Sebuah pola pencarian yang ikut rusak di jalan
-- tidak akan cocok dengan apa pun, dan perbaikannya diam-diam tidak
-- mengerjakan apa-apa sambil melapor berhasil.
--
-- U+201A U+00C4 U+00EE - bentuk MacRoman dari tanda pisah panjang UTF-8.
update gl_journal_entries
   set description = replace(description, U&'\201A\00C4\00EE', '-')
 where description like '%' || U&'\201A\00C4\00EE' || '%';

commit;
