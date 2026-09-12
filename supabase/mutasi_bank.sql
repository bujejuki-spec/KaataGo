-- KaataGo - mutasi rekening, dan mencocokkannya dengan yang tercatat.
--
-- Jalankan SETELAH rekening_perusahaan.sql, setor_dan_pickup.sql, dan
-- tutup_buku_harian.sql. Aman diulang.
--
-- Tiga jenis uang masuk ke rekening merchant tanpa satu pun laporan yang
-- menyebutkan asalnya:
--
--   setoran & pickup - kasir menyerahkan uang laci; sampainya menyusul
--   QRIS Statis      - pelanggan memindai QR cetak merchant
--   transfer         - pelanggan mengirim langsung
--
-- Untuk ketiganya, satu-satunya bukti bahwa uangnya benar-benar sampai
-- adalah mutasi rekening — dan sampai sekarang mutasi itu tidak pernah
-- masuk ke aplikasi sama sekali. Yang dilakukan Finance selama ini
-- membandingkan layar dengan tab bank di sebelahnya, dengan mata.
--
-- ── Yang dijawab rekonsiliasi, dan kenapa dua-duanya penting ─────────
--
-- Mencocokkan menghasilkan DUA daftar sisa, dan keduanya menanyakan hal
-- yang berbeda:
--
--   mutasi yang tidak punya pasangan
--     Uang masuk rekening yang tidak ada catatannya di aplikasi.
--     Bisa jadi penjualan yang belum diinput, bisa jadi uang dari luar
--     usaha. Yang jelas: ada di bank, tidak ada di buku.
--
--   catatan yang tidak punya mutasi
--     Setoran yang dinyatakan sudah dikirim tapi tidak pernah sampai,
--     atau pembayaran yang diakui lunas tapi uangnya tidak ada.
--     Ini yang mahal, dan ini yang selama ini tidak pernah terlihat.
--
-- Yang cuma menghitung total takkan menemukan keduanya: dua kekeliruan
-- berlawanan arah bisa menghasilkan total yang kebetulan cocok.

begin;

create table if not exists bank_mutations (
  id uuid primary key default gen_random_uuid(),

  -- Mutasi milik REKENING, bukan resto. Satu rekening bisa dipakai
  -- beberapa cabang, dan mutasi yang masuk ke sana tidak membawa
  -- keterangan cabang mana pun.
  bank_account_id uuid not null references bank_accounts (id) on delete cascade,

  mutated_on date not null,

  -- Selalu positif; arahnya di kolom sendiri. Angka negatif untuk uang
  -- keluar terlihat rapi di satu kolom dan menyusahkan di semua
  -- penjumlahan berikutnya — yang lupa menyaring arahnya mendapat total
  -- yang diam-diam saling menghapus.
  amount bigint not null check (amount > 0),
  direction text not null check (direction in ('in', 'out')),

  description text,

  -- Nomor acuan dari banknya, kalau ada. Dipakai mencegah satu mutasi
  -- dimasukkan dua kali oleh dua orang yang sama-sama merasa belum
  -- mencatatnya.
  reference text,

  -- Apa yang dijelaskan mutasi ini.
  --
  --   deposit  - setoran atau pickup yang sampai       (cash_deposits)
  --   order    - pembayaran pelanggan                  (orders)
  --   gateway  - pencairan penyedia pembayaran         (gateway_settlements)
  --   other    - bukan dari penjualan; diakui apa adanya
  --
  -- Null berarti belum dicocokkan, dan itu keadaan yang paling berguna:
  -- daftar yang null-nya panjang adalah pekerjaan yang menunggu.
  matched_kind text
    check (matched_kind is null
           or matched_kind in ('deposit', 'order', 'gateway', 'other')),
  matched_id text,
  matched_by text,
  matched_at timestamptz,

  note text,
  created_by text,
  created_at timestamptz not null default now(),

  -- 'other' tidak menunjuk baris mana pun; sisanya wajib.
  constraint bank_mutations_match_check
    check (matched_kind is null
           or matched_kind = 'other'
           or coalesce(btrim(matched_id), '') <> '')
);

-- Satu mutasi dicatat sekali.
--
-- Acuan banknya yang jadi penanda. Yang tidak punya acuan tidak
-- dibatasi — sebagian bank tidak memberikannya, dan menolak yang tanpa
-- acuan berarti menolak mutasi yang sah.
create unique index if not exists bank_mutations_acuan_unik
  on bank_mutations (bank_account_id, reference)
  where reference is not null and btrim(reference) <> '';

-- Satu setoran dijelaskan satu mutasi, tidak lebih.
--
-- Tanpa ini, satu setoran bisa "dibuktikan" dua kali oleh dua mutasi
-- berbeda — dan jumlah yang terbukti sampai jadi dua kali lipat dari
-- yang benar-benar dikirim.
create unique index if not exists bank_mutations_sasaran_unik
  on bank_mutations (matched_kind, matched_id)
  where matched_kind is not null and matched_kind <> 'other';

create index if not exists bank_mutations_rekening_idx
  on bank_mutations (bank_account_id, mutated_on desc);

create index if not exists bank_mutations_belum_cocok_idx
  on bank_mutations (bank_account_id, mutated_on desc)
  where matched_kind is null;

alter table bank_mutations enable row level security;

-- Terlihat karyawan resto yang memakai rekeningnya; ditulis Owner dan
-- Finance. Mutasi rekening adalah isi buku bank perusahaan — kasir tidak
-- punya urusan membacanya, apalagi menuliskannya.
drop policy if exists "bank_mutations: finance read" on bank_mutations;
create policy "bank_mutations: finance read" on bank_mutations
  for select using (
    is_super_admin()
    or exists (
      select 1 from resto_bank_accounts rb
      where rb.bank_account_id = bank_mutations.bank_account_id
        and is_resto_employee(rb.resto_id, array['owner', 'finance'])
    )
  );

drop policy if exists "bank_mutations: finance write" on bank_mutations;
create policy "bank_mutations: finance write" on bank_mutations
  for all using (
    is_super_admin()
    or exists (
      select 1 from resto_bank_accounts rb
      where rb.bank_account_id = bank_mutations.bank_account_id
        and is_resto_employee(rb.resto_id, array['owner', 'finance'])
    )
  ) with check (
    is_super_admin()
    or exists (
      select 1 from resto_bank_accounts rb
      where rb.bank_account_id = bank_mutations.bank_account_id
        and is_resto_employee(rb.resto_id, array['owner', 'finance'])
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Yang belum punya pasangan
-- ─────────────────────────────────────────────────────────────────────
--
-- Setoran dan pickup yang dinyatakan terkirim tapi tidak ada mutasinya.
-- Inilah sisi yang mahal: uang yang keluar laci dan tidak pernah sampai
-- ke bank.
--
-- Yang ditolak tidak ikut: uangnya memang dikembalikan ke laci, jadi
-- tidak ada yang perlu ditunggu di rekening.

begin;

create or replace function setoran_belum_cocok(p_resto_id text)
returns table (
  id uuid,
  amount bigint,
  method text,
  created_by text,
  created_at timestamptz,
  bank_account_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select d.id, d.amount, d.method, d.created_by, d.created_at,
         d.bank_account_id
  from cash_deposits d
  where d.resto_id = p_resto_id
    and d.status <> 'rejected'
    and not exists (
      select 1 from bank_mutations m
      where m.matched_kind = 'deposit'
        and m.matched_id = d.id::text
    )
  order by d.created_at desc;
$$;

grant execute on function setoran_belum_cocok(text) to authenticated;

-- Pembayaran pelanggan yang uangnya mendarat langsung di rekening —
-- QRIS Statis dan transfer — dan belum ada mutasinya.
--
-- Tunai tidak pernah ikut: uangnya masuk laci, dan perjalanannya ke bank
-- sudah diwakili barisnya sendiri sebagai setoran. QRIS Dinamis juga
-- tidak: uangnya menginap di penyedia pembayaran dan datang sebagai
-- pencairan, bukan sebagai mutasi per pesanan.
create or replace function pembayaran_belum_cocok(
  p_resto_id text,
  p_sejak date default (now() at time zone 'Asia/Jakarta')::date - 30)
returns table (
  id uuid,
  total bigint,
  payment_method text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select o.id, o.total::bigint,
         _normalize_payment_method(o.source, o.payment_method),
         o.created_at
  from orders o
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and _normalize_payment_method(o.source, o.payment_method)
          in ('qris_static', 'transfer')
    and (o.created_at at time zone 'Asia/Jakarta')::date >= p_sejak
    and not exists (
      select 1 from bank_mutations m
      where m.matched_kind = 'order'
        and m.matched_id = o.id::text
    )
  order by o.created_at desc;
$$;

grant execute on function pembayaran_belum_cocok(text, date) to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Hasilnya mengisi tutup buku harian
-- ─────────────────────────────────────────────────────────────────────
--
-- Kolom `qris_static_settled` dan `transfer_settled` di
-- daily_settlements selama ini selalu nol, dengan catatan "belum
-- dicocokkan". Sekarang ada yang mengisinya: jumlah pembayaran hari itu
-- yang sudah punya mutasinya.

begin;

create or replace function hitung_tercocok(p_resto_id text, p_tanggal date)
returns table (qris_static_settled bigint, transfer_settled bigint)
language sql
stable
security definer
set search_path = public
as $$
  with cocok as (
    select _normalize_payment_method(o.source, o.payment_method) as metode,
           o.total
    from orders o
    join bank_mutations m
      on m.matched_kind = 'order' and m.matched_id = o.id::text
    where o.resto_id = p_resto_id
      and o.payment_status = 'paid'
      and (o.created_at at time zone 'Asia/Jakarta')::date = p_tanggal
  )
  select
    coalesce((select sum(total) from cocok where metode = 'qris_static'), 0)::bigint,
    coalesce((select sum(total) from cocok where metode = 'transfer'), 0)::bigint;
$$;

grant execute on function hitung_tercocok(text, date) to authenticated;

-- Tutup buku ikut mengambilnya.
--
-- Badannya disalin dari tutup_buku_harian.sql; yang ditambah cuma dua
-- kolom yang tadinya selalu nol. Ditulis ulang dari ingatan, pengaman
-- "hari ini belum selesai" dan "masih ada shift terbuka" bisa ikut
-- hilang — dan keduanya yang menjaga angka bekunya berarti sesuatu.
create or replace function tutup_hari(
  p_resto_id text,
  p_tanggal date,
  p_note text default null)
returns daily_settlements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_angka record;
  v_cocok record;
  v_row daily_settlements;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'finance'])) then
    raise exception 'Hanya Owner dan Finance yang boleh menutup buku.';
  end if;

  if p_tanggal >= (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Hari ini belum selesai. Tutup buku paling cepat besok.';
  end if;

  if exists (
    select 1 from cashier_shifts s
    where s.resto_id = p_resto_id
      and s.closed_at is null
      and (s.opened_at at time zone 'Asia/Jakarta')::date <= p_tanggal
  ) then
    raise exception 'Masih ada shift kasir yang belum ditutup.';
  end if;

  select * into v_angka from hitung_hari(p_resto_id, p_tanggal);
  select * into v_cocok from hitung_tercocok(p_resto_id, p_tanggal);

  insert into daily_settlements (
    resto_id, settled_on,
    cash_expected, qris_expected, qris_static_expected, transfer_expected,
    cash_counted, qris_settled, qris_static_settled, transfer_settled,
    gateway_fee, status, note, settled_by, settled_at
  ) values (
    p_resto_id, p_tanggal,
    v_angka.cash_expected, v_angka.qris_expected,
    v_angka.qris_static_expected, v_angka.transfer_expected,
    v_angka.cash_counted, v_angka.qris_settled,
    v_cocok.qris_static_settled, v_cocok.transfer_settled,
    v_angka.gateway_fee,
    'settled', nullif(btrim(coalesce(p_note, '')), ''), v_email, now()
  )
  on conflict (resto_id, settled_on) do update
    set cash_expected = excluded.cash_expected,
        qris_expected = excluded.qris_expected,
        qris_static_expected = excluded.qris_static_expected,
        transfer_expected = excluded.transfer_expected,
        cash_counted = excluded.cash_counted,
        qris_settled = excluded.qris_settled,
        qris_static_settled = excluded.qris_static_settled,
        transfer_settled = excluded.transfer_settled,
        gateway_fee = excluded.gateway_fee,
        status = 'settled',
        note = excluded.note,
        settled_by = excluded.settled_by,
        settled_at = excluded.settled_at
  returning * into v_row;

  return v_row;
end;
$$;

commit;
