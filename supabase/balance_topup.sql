-- KaataGo — setoran modal ke saldo utama.
--
-- Jalankan SETELAH vouchers.sql dan platform_finance.sql. Aman diulang.
--
-- Ada satu jenis uang masuk yang selama ini tidak punya tempat: modal.
-- Investor menyetor ke KaataGo, atau pemilik resto menaruh uang awal
-- supaya kasnya tidak minus di hari pertama. Keduanya uang sungguhan
-- yang benar-benar masuk, tapi bukan penjualan dan bukan langganan —
-- jadi tidak ada pemicu yang menjurnalnya, dan saldonya berbunyi nol
-- padahal uangnya ada.
--
-- Mencatatnya sebagai "penghasilan" akan lebih buruk daripada tidak
-- mencatatnya: laporan penjualan jadi memuat uang yang tidak pernah
-- dijual, dan resto yang menyetor modal besar akan terlihat seperti
-- resto yang laris.

begin;

-- Akunnya sendiri, terpisah dari pendapatan.
alter table gl_accounts drop constraint if exists gl_accounts_payment_method_check;
alter table gl_accounts add constraint gl_accounts_payment_method_check
  check (
    payment_method in
    ('cash', 'qris', 'transfer', 'petty_cash', 'income_aggregate', 'total_balance',
     'ppn', 'service', 'suspense', 'suspense_petty', 'gateway_fee', 'discount',
     'subscription', 'subscription_discount', 'voucher', 'voucher_redeem',
     'capital'));

-- Untuk KaataGo — sederet dengan akun platform lainnya.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values ('kaatago', 'capital', '1100003', 'GL Setoran Modal')
on conflict (resto_id, payment_method) do nothing;

-- Untuk tiap resto.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'capital', '1940001', 'GL Setoran Modal'
from restaurants r
where coalesce(r.is_platform, false) = false
on conflict (resto_id, payment_method) do nothing;

create table if not exists balance_topups (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,
  amount bigint not null check (amount > 0),

  -- Dari siapa, dan keterangannya. Setoran modal tanpa nama penyetor
  -- adalah uang yang tidak bisa dipertanggungjawabkan ke siapa pun.
  source text not null,
  note text,

  -- Bukti transfer, base64. Boleh kosong untuk setoran tunai langsung.
  proof_base64 text,

  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists balance_topups_resto_idx
  on balance_topups (resto_id, created_at desc);

alter table balance_topups enable row level security;

drop policy if exists "balance_topups: read" on balance_topups;
create policy "balance_topups: read" on balance_topups
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin', 'kasir'])
  );

-- Mencatatnya hanya Owner, Finance, dan Super Admin.
--
-- Kasir boleh melihat — angkanya memengaruhi saldo yang dia
-- pertanggungjawabkan — tapi tidak boleh menambah. Baris yang menaikkan
-- saldo tanpa uang sungguhan adalah cara paling rapi menutupi selisih
-- laci.
drop policy if exists "balance_topups: write" on balance_topups;
create policy "balance_topups: write" on balance_topups
  for insert with check (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  );

-- Tidak ada kebijakan ubah maupun hapus. Setoran yang salah diperbaiki
-- dengan setoran koreksi, bukan dengan menghapus jejaknya — jurnalnya
-- hanya pernah ditambah, tidak pernah disunting.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Jurnalnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Kredit GL Total Saldo — uang masuk, dan sejak detik ini bebas
-- dipakai. Debit GL Setoran Modal — kantong asalnya, supaya jelas uang
-- ini datang dari mana dan tidak tercampur dengan hasil penjualan.

create or replace function log_balance_topup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total record;
  v_modal record;
  v_now timestamptz := now();
  v_tanggal date := (v_now at time zone 'Asia/Jakarta')::date;
  v_jam time := (v_now at time zone 'Asia/Jakarta')::time;
  v_ket text := 'Setoran modal dari ' || new.source;
begin
  select * into v_total from _gl_account_for(new.resto_id, 'total_balance');
  select * into v_modal from _gl_account_for(new.resto_id, 'capital');

  if v_total.gl_code is not null and v_total.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_tanggal, v_jam, v_total.gl_code, v_total.gl_name,
      'capital', new.id::text, new.amount, 'credit', v_ket
    );
  end if;

  if v_modal.gl_code is not null and v_modal.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id, v_tanggal, v_jam, v_modal.gl_code, v_modal.gl_name,
      'capital', new.id::text, new.amount, 'debit', v_ket
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_balance_topup on balance_topups;
create trigger trg_log_balance_topup
  after insert on balance_topups
  for each row execute function log_balance_topup();

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select t.created_at, r.name, t.amount, t.source
--   from balance_topups t left join restaurants r on r.id = t.resto_id
--   order by t.created_at desc;
--
--   select gl_code, gl_name, entry_type, amount, description
--   from gl_journal_entries where reference_type = 'capital'
--   order by created_at desc limit 10;
