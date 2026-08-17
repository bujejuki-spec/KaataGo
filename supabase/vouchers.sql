-- KaataGo — voucher untuk pelanggan, ditanggung KaataGo.
--
-- Jalankan SETELAH product_toppings.sql. Aman diulang.
--
-- Bedanya dengan diskon resto: diskon resto adalah promo restonya
-- sendiri, dan potongannya mengurangi pendapatan resto itu. Voucher ini
-- promo KAMI — dipakai menarik orang memasang aplikasinya — jadi yang
-- menanggung juga kami. Dananya keluar dari saldo KaataGo sebagai biaya
-- promosi.
--
-- ── Yang belum ditangani aplikasi ────────────────────────────────────
--
-- Pada saat pelanggan membayar, resto menerima uang yang sudah dipotong
-- vouchernya. Pembukuan KaataGo mencatat potongan itu sebagai biaya, dan
-- layar Super Admin menampilkan berapa yang terutang ke tiap resto — tapi
-- pembayarannya ke resto masih dilakukan di luar aplikasi. Menuliskannya
-- di sini supaya tidak ada yang mengira transfernya otomatis.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Voucher
-- ─────────────────────────────────────────────────────────────────────

create table if not exists vouchers (
  id text primary key,

  -- Kode yang diketik pelanggan. Disimpan huruf besar semua supaya
  -- "hemat10" dan "HEMAT10" adalah voucher yang sama — yang mengetiknya
  -- sedang lapar dan berdiri di depan kasir, bukan sedang teliti.
  code text not null unique,
  name text not null,

  kind text not null default 'percent' check (kind in ('percent', 'amount')),
  value bigint not null check (value > 0),

  -- Batas atas untuk voucher persen. Tanpa ini, "diskon 20%" pada
  -- tagihan sejuta rupiah adalah dua ratus ribu yang keluar dari saldo
  -- kami untuk satu transaksi.
  max_discount bigint not null default 0 check (max_discount >= 0),

  min_purchase bigint not null default 0 check (min_purchase >= 0),

  -- Resto yang menerimanya. Kosong berarti berlaku di semua resto.
  resto_ids jsonb not null default '[]'::jsonb,

  -- Nol berarti tanpa batas.
  quota_total integer not null default 0 check (quota_total >= 0),
  quota_per_customer integer not null default 1 check (quota_per_customer >= 0),

  starts_on date,
  ends_on date,
  active boolean not null default true,

  created_by text,
  created_at timestamptz not null default now(),

  constraint vouchers_period_check
    check (ends_on is null or starts_on is null or ends_on > starts_on),
  constraint vouchers_percent_check
    check (kind <> 'percent' or value between 1 and 100)
);

create index if not exists idx_vouchers_aktif
  on vouchers (code) where active;

-- ─────────────────────────────────────────────────────────────────────
-- Pemakaian
-- ─────────────────────────────────────────────────────────────────────
--
-- Dicatat sebagai barisnya sendiri, bukan dihitung dari pesanan. Kuota
-- harus bisa dijawab tanpa memindai seluruh tabel pesanan, dan yang
-- lebih penting: pesanan bisa dibatalkan, sementara catatan pemakaian
-- voucher adalah jejak yang tetap perlu ada.

create table if not exists voucher_redemptions (
  id text primary key,
  voucher_id text not null references vouchers (id) on delete cascade,
  order_id uuid,
  resto_id text references restaurants (id) on delete set null,

  -- Email pelanggan, atau penanda tamu. Dipakai menegakkan kuota per
  -- orang.
  customer_label text not null,
  amount bigint not null check (amount >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_redemptions_voucher
  on voucher_redemptions (voucher_id);
create index if not exists idx_redemptions_customer
  on voucher_redemptions (voucher_id, customer_label);
create index if not exists idx_redemptions_resto
  on voucher_redemptions (resto_id, created_at desc);

alter table orders add column if not exists voucher_id text;
alter table orders add column if not exists voucher_code text;
alter table orders add column if not exists voucher_amount bigint not null default 0;

-- ─────────────────────────────────────────────────────────────────────
-- Akun biaya voucher di pembukuan KaataGo
-- ─────────────────────────────────────────────────────────────────────

insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values ('kaatago', 'voucher', '1100080', 'GL Biaya Voucher KaataGo')
on conflict (resto_id, payment_method) do nothing;

-- ─────────────────────────────────────────────────────────────────────
-- Menghitung potongan voucher
-- ─────────────────────────────────────────────────────────────────────
--
-- Dihitung di server, bukan di aplikasi. Nominal potongan yang datang
-- dari HP bisa diubah siapa pun yang ingin membayar seribu rupiah untuk
-- tagihan seratus ribu — dan ini uang kami sendiri yang keluar.

create or replace function voucher_quote(
  p_code text,
  p_resto_id text,
  p_customer text,
  p_total bigint
)
returns table (
  voucher_id text,
  code text,
  name text,
  amount bigint,
  reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v vouchers;
  v_terpakai integer;
  v_terpakai_orang integer;
  v_amount bigint;
begin
  select * into v from vouchers where vouchers.code = upper(trim(p_code));

  if v.id is null then
    return query select null::text, null::text, null::text, 0::bigint,
      'Kode voucher tidak ditemukan';
    return;
  end if;

  if not v.active then
    return query select v.id, v.code, v.name, 0::bigint,
      'Voucher ini sudah tidak berlaku';
    return;
  end if;

  if v.starts_on is not null and current_date < v.starts_on then
    return query select v.id, v.code, v.name, 0::bigint,
      'Voucher ini belum berlaku';
    return;
  end if;

  if v.ends_on is not null and current_date > v.ends_on then
    return query select v.id, v.code, v.name, 0::bigint,
      'Voucher ini sudah lewat masa berlakunya';
    return;
  end if;

  if jsonb_array_length(v.resto_ids) > 0 and not (v.resto_ids ? p_resto_id) then
    return query select v.id, v.code, v.name, 0::bigint,
      'Voucher ini tidak berlaku di resto ini';
    return;
  end if;

  if p_total < v.min_purchase then
    return query select v.id, v.code, v.name, 0::bigint,
      'Belanja minimal ' || v.min_purchase || ' untuk memakai voucher ini';
    return;
  end if;

  if v.quota_total > 0 then
    select count(*) into v_terpakai
    from voucher_redemptions where voucher_redemptions.voucher_id = v.id;
    if v_terpakai >= v.quota_total then
      return query select v.id, v.code, v.name, 0::bigint,
        'Kuota voucher ini sudah habis';
      return;
    end if;
  end if;

  if v.quota_per_customer > 0 and coalesce(p_customer, '') <> '' then
    select count(*) into v_terpakai_orang
    from voucher_redemptions
    where voucher_redemptions.voucher_id = v.id
      and voucher_redemptions.customer_label = p_customer;
    if v_terpakai_orang >= v.quota_per_customer then
      return query select v.id, v.code, v.name, 0::bigint,
        'Voucher ini sudah kamu pakai';
      return;
    end if;
  end if;

  v_amount := case
    when v.kind = 'percent' then p_total * v.value / 100
    else v.value
  end;

  -- Batas atas persen, lalu tidak pernah melebihi tagihannya sendiri.
  if v.max_discount > 0 and v_amount > v.max_discount then
    v_amount := v.max_discount;
  end if;
  if v_amount > p_total then
    v_amount := p_total;
  end if;

  return query select v.id, v.code, v.name, v_amount, null::text;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Mencatat pemakaian
-- ─────────────────────────────────────────────────────────────────────
--
-- Lewat pemicu pada pesanan, bukan panggilan terpisah dari aplikasi.
-- Panggilan terpisah bisa gagal atau tidak pernah dikirim, dan yang
-- tertinggal adalah voucher yang memotong tagihan tanpa pernah terhitung
-- kuotanya.

create or replace function log_voucher_redemption()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_petty record;
  v_now timestamptz := now();
  v_id text;
begin
  if coalesce(new.voucher_amount, 0) <= 0 or new.voucher_id is null then
    return new;
  end if;

  if exists (
    select 1 from voucher_redemptions where order_id = new.id
  ) then
    return new;
  end if;

  v_id := 'VR-' || upper(substr(md5(new.id::text), 1, 12));

  insert into voucher_redemptions (
    id, voucher_id, order_id, resto_id, customer_label, amount
  ) values (
    v_id, new.voucher_id, new.id, new.resto_id,
    coalesce(new.customer_label, 'Tamu'), new.voucher_amount
  );

  -- Biaya promosi di pembukuan KaataGo: uangnya keluar dari saldo kami.
  --
  -- Dua kaki, sama seperti pengeluaran biasa — debit biayanya, kredit
  -- kantong yang membayarinya. Satu kaki saja akan membuat saldo
  -- KaataGo terlihat utuh padahal uangnya sudah dijanjikan keluar.
  select * into v_gl from _gl_account_for('kaatago', 'voucher');
  select * into v_petty from _gl_account_for('kaatago', 'petty_cash');

  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      'kaatago',
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'voucher', v_id, new.voucher_amount, 'debit',
      'Voucher ' || coalesce(new.voucher_code, '') ||
        ' — pesanan #' || upper(substr(new.id::text, 1, 8))
    );
  end if;

  if v_petty.gl_code is not null and v_petty.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      'kaatago',
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_petty.gl_code, v_petty.gl_name,
      'voucher', v_id, new.voucher_amount, 'credit',
      'Dana voucher ' || coalesce(new.voucher_code, '')
    );
  end if;

  return new;
end;
$$;

alter table gl_journal_entries drop constraint if exists gl_journal_entries_reference_type_check;
alter table gl_journal_entries add constraint gl_journal_entries_reference_type_check
  check (reference_type in
    ('order', 'order_discount', 'expense', 'petty_cash', 'cash_deposit',
     'billing', 'billing_discount', 'voucher'));

drop trigger if exists trg_log_voucher_redemption on orders;
create trigger trg_log_voucher_redemption
  after insert on orders
  for each row execute function log_voucher_redemption();

-- ─────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────

alter table vouchers enable row level security;
alter table voucher_redemptions enable row level security;

-- Dibaca siapa saja termasuk tamu: vouchernya harus terlihat di layar
-- pelanggan sebelum dia memutuskan memesan.
drop policy if exists "vouchers: public read" on vouchers;
create policy "vouchers: public read" on vouchers
  for select using (true);

drop policy if exists "vouchers: super admin write" on vouchers;
create policy "vouchers: super admin write" on vouchers
  for all using (is_super_admin()) with check (is_super_admin());

-- Pemakaian hanya dibaca Super Admin dan resto yang bersangkutan —
-- resto perlu tahu berapa yang tertahan untuk ditagihkan ke kami.
drop policy if exists "voucher_redemptions: read" on voucher_redemptions;
create policy "voucher_redemptions: read" on voucher_redemptions
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'admin', 'finance'])
  );

commit;
