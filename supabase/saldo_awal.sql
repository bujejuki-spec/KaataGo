-- KaataGo - menyetel saldo awal kas dan rekening perusahaan.
--
-- Jalankan SETELAH saldo_perusahaan.sql. Aman diulang.
--
-- Saldo Bank Perusahaan sekarang menjumlahkan uang yang PERNAH MASUK,
-- bukan yang masih ada. Sebabnya bukan salah hitung: pengeluaran yang
-- dilakukan dari rekening sebelum aplikasi ini mencatatnya memang tidak
-- punya barisnya di mana pun, jadi tidak ada yang bisa dikurangkan.
--
-- Selama itu belum dibereskan, angkanya tidak bisa dipakai mengambil
-- keputusan — dan angka yang tidak bisa dipakai mengambil keputusan
-- lebih berbahaya daripada angka yang tidak ada, karena ia tetap
-- dibaca orang.
--
-- Yang dibutuhkan bukan tebakan sistem melainkan satu kenyataan dari
-- luar: berapa isi rekening pada suatu tanggal, menurut mutasi bank
-- sungguhan. Fungsi di bawah menerima angka itu, membandingkannya
-- dengan apa yang tercatat sampai tanggal itu, lalu menuliskan
-- selisihnya sebagai penyesuaian.
--
-- ── Kenapa penyesuaian, bukan menghapus lalu menulis ulang ───────────
--
-- Baris lama tidak disentuh. Penjualan yang pernah masuk memang pernah
-- masuk, dan menghapusnya demi merapikan satu angka berarti menukar
-- angka yang salah dengan riwayat yang bohong. Yang ditambahkan cuma
-- satu baris yang menyatakan: sampai tanggal ini, isinya sekian.
--
-- Pergerakan SESUDAH tanggal itu tidak ikut disetel — ia tetap berjalan
-- di atas saldo awalnya. Jadi menyetel saldo per 31 Agustus hari ini
-- tidak menghapus penjualan September.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Akun penyeimbangnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Penyesuaiannya butuh lawan akun, kalau tidak jurnalnya timpang dan
-- Jurnal GL berhenti bisa dibaca sebagai pasangan debit-kredit. Akun
-- ini menampung "uang yang sudah ada sebelum aplikasi ini mencatat" —
-- dan saldonya sendiri memang tidak berarti apa-apa selain itu.

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
     'cash_pickup', 'company_cash', 'company_bank', 'opening_balance'));

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'opening_balance', '1990004', 'GL Saldo Awal'
from restaurants r
on conflict (resto_id, payment_method) do nothing;

alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (
    reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher', 'capital', 'cash_variance',
     'other_income', 'company_deposit', 'opening_balance'));

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Menyetelnya
-- ─────────────────────────────────────────────────────────────────────

begin;

create or replace function setel_saldo_awal(
  p_resto_id text,
  p_kantong text,
  p_saldo bigint,
  p_tanggal date,
  p_note text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_email text := auth.jwt() ->> 'email';
  v_jenis text;
  v_akun record;
  v_lawan record;
  v_tercatat bigint;
  v_selisih bigint;
  v_sebut text;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  -- Menyatakan berapa isi rekening perusahaan adalah pernyataan
  -- pembukuan, bukan pekerjaan operasional.
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'finance'])) then
    raise exception 'Hanya Owner dan Finance yang bisa menyetel saldo awal.';
  end if;

  if p_kantong not in ('cash', 'bank') then
    raise exception 'Kantongnya harus cash atau bank.';
  end if;

  if p_saldo is null or p_saldo < 0 then
    raise exception 'Saldo awal tidak boleh kosong atau minus.';
  end if;

  if p_tanggal is null then
    raise exception 'Tanggalnya wajib disebut.';
  end if;

  -- Tanggal yang belum terjadi tidak punya mutasi bank untuk
  -- dibandingkan — yang disetel dengannya cuma angan-angan.
  if p_tanggal > (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Tanggalnya belum terjadi.';
  end if;

  v_jenis := case p_kantong when 'cash' then 'company_cash'
                            else 'company_bank' end;
  v_sebut := case p_kantong when 'cash' then 'Saldo Cash Perusahaan'
                            else 'Saldo Bank Perusahaan' end;

  select * into v_akun from _gl_account_for(p_resto_id, v_jenis);
  if v_akun.gl_code is null or v_akun.gl_code = '' then
    raise exception 'Akun % belum dipetakan di Mapping GL Account.', v_sebut;
  end if;

  select * into v_lawan from _gl_account_for(p_resto_id, 'opening_balance');
  if v_lawan.gl_code is null or v_lawan.gl_code = '' then
    raise exception 'GL Saldo Awal belum dipetakan di Mapping GL Account.';
  end if;

  -- Yang tercatat SAMPAI tanggal itu, bukan sampai hari ini. Pergerakan
  -- sesudahnya berjalan di atas saldo awalnya dan tidak ikut disetel.
  select coalesce(sum(case when j.entry_type = 'credit'
                           then j.amount else -j.amount end), 0)
    into v_tercatat
  from gl_journal_entries j
  where j.resto_id = p_resto_id
    and j.gl_code = v_akun.gl_code
    and j.entry_date <= p_tanggal
    and coalesce(j.is_reversal, false) = false;

  v_selisih := p_saldo - v_tercatat;

  -- Sudah cocok: tidak ada yang perlu ditulis. Baris penyesuaian
  -- bernilai nol cuma menambah baris yang harus dibaca orang nanti.
  if v_selisih = 0 then
    return 0;
  end if;

  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    p_resto_id, p_tanggal, '00:00:00',
    v_akun.gl_code, v_akun.gl_name, 'opening_balance',
    p_resto_id || ':' || p_kantong || ':' || p_tanggal::text,
    abs(v_selisih),
    case when v_selisih > 0 then 'credit' else 'debit' end,
    'Penyesuaian saldo awal ' || v_sebut ||
      coalesce(' — ' || nullif(btrim(coalesce(p_note, '')), ''), '')
  );

  -- Sisi penyeimbangnya, arah kebalikannya.
  insert into gl_journal_entries (
    resto_id, entry_date, entry_time, gl_code, gl_name,
    reference_type, reference_id, amount, entry_type, description
  ) values (
    p_resto_id, p_tanggal, '00:00:00',
    v_lawan.gl_code, v_lawan.gl_name, 'opening_balance',
    p_resto_id || ':' || p_kantong || ':' || p_tanggal::text,
    abs(v_selisih),
    case when v_selisih > 0 then 'debit' else 'credit' end,
    'Lawan penyesuaian saldo awal ' || v_sebut
  );

  return v_selisih;
end;
$fn$;

revoke all on function setel_saldo_awal(text, text, bigint, date, text)
  from public, anon;
grant execute on function setel_saldo_awal(text, text, bigint, date, text)
  to authenticated;

commit;
