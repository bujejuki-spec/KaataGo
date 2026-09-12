-- KaataGo - tutup buku harian merchant.
--
-- Jalankan SETELAH cashier_shift.sql, gateway_settlement.sql, dan
-- qris_statis.sql. Aman diulang.
--
-- Sampai sekarang tidak ada satu momen pun yang berbunyi "hari ini
-- selesai, angkanya segini". Yang ada cuma aliran: pesanan masuk, jurnal
-- tertulis, saldo bergerak. Akibatnya tidak pernah jelas sampai mana
-- sebuah hari sudah diperiksa — dan pertanyaan "kemarin sudah cocok
-- belum?" hanya bisa dijawab dengan menghitung ulang semuanya.
--
-- Berkas ini menambahkan momen itu: satu baris per resto per hari, berisi
-- angka tiap metode bayar yang DIBEKUKAN saat ditutup.
--
-- ── Kenapa dibekukan, bukan dihitung ulang tiap dibaca ───────────────
--
-- Alasan yang sama dengan `cashier_shifts.expected_cash`: angka yang
-- sudah ditandatangani seseorang tidak boleh berubah karena ada pesanan
-- yang dikoreksi tiga hari kemudian. Yang dibekukan adalah keadaan pada
-- saat penutupan; koreksi sesudahnya terlihat sebagai selisih, bukan
-- diam-diam menimpa angka lamanya.
--
-- ── Yang TIDAK dikerjakan di sini: sisi tunai ────────────────────────
--
-- Tunai sudah direkonsiliasi tutup shift kasir, lengkap dengan
-- selisihnya dan penelusurannya. Menghitungnya lagi di sini berarti dua
-- angka yang sama-sama mengaku menyebut isi laci, dan yang membaca
-- layarnya tidak punya cara tahu mana yang benar.
--
-- Jadi baris tunai di sini MENGAMBIL hasil shift hari itu, bukan
-- menyusunnya sendiri.

begin;

create table if not exists daily_settlements (
  id uuid primary key default gen_random_uuid(),
  resto_id text not null references restaurants (id) on delete cascade,

  -- Tanggal WIB, bukan UTC. Resto tutup jam sebelas malam waktu sini,
  -- dan hari yang berganti jam tujuh pagi membuat penjualan satu malam
  -- terbelah dua.
  settled_on date not null,

  -- Yang seharusnya, menurut pesanan yang lunas hari itu.
  cash_expected bigint not null default 0,
  qris_expected bigint not null default 0,
  qris_static_expected bigint not null default 0,
  transfer_expected bigint not null default 0,

  -- Yang benar-benar terbukti sampai:
  --
  --   tunai       - dihitung tangan saat tutup shift
  --   qris        - dicairkan penyedia pembayaran (bersih, setelah MDR)
  --   qris statis - terlihat di mutasi rekening
  --   transfer    - terlihat di mutasi rekening
  --
  -- Ketiganya yang terakhir diisi tahap berikutnya; hari ini nol berarti
  -- "belum dicocokkan", bukan "tidak ada".
  cash_counted bigint not null default 0,
  qris_settled bigint not null default 0,
  qris_static_settled bigint not null default 0,
  transfer_settled bigint not null default 0,

  -- Potongan penyedia pembayaran hari itu. Dipisah supaya selisih QRIS
  -- tidak terbaca sebagai uang hilang padahal cuma biaya yang wajar.
  gateway_fee bigint not null default 0,

  status text not null default 'open'
    check (status in ('open', 'settled')),

  note text,
  settled_by text,
  settled_at timestamptz,
  created_at timestamptz not null default now(),

  -- Satu hari satu baris. Tanpa ini, menutup dua kali menghasilkan dua
  -- kebenaran untuk tanggal yang sama.
  unique (resto_id, settled_on)
);

create index if not exists daily_settlements_resto_idx
  on daily_settlements (resto_id, settled_on desc);

alter table daily_settlements enable row level security;

-- Dibaca seluruh yang memegang angka; ditutup hanya Owner dan Finance.
--
-- Menutup buku adalah pernyataan bahwa sebuah hari sudah diperiksa, dan
-- yang menyatakannya harus orang yang menanggung pembukuannya. Admin
-- merchant menjalankan operasional, bukan menutup buku.
drop policy if exists "daily_settlements: staff read" on daily_settlements;
create policy "daily_settlements: staff read" on daily_settlements
  for select using (
    is_super_admin()
    or is_resto_employee(resto_id, array['owner', 'finance', 'admin'])
  );

drop policy if exists "daily_settlements: finance write" on daily_settlements;
create policy "daily_settlements: finance write" on daily_settlements
  for all using (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  ) with check (
    is_super_admin() or is_resto_employee(resto_id, array['owner', 'finance'])
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Angka sebuah hari, dihitung dari sumbernya
-- ─────────────────────────────────────────────────────────────────────
--
-- Dipakai dua kali dengan arti berbeda, dan bedanya penting:
--
--   hari yang BELUM ditutup - inilah angkanya, dihitung ulang tiap
--                             dibuka, berubah kalau ada koreksi
--   hari yang SUDAH ditutup - ini pembanding; yang berlaku angka beku
--                             di barisnya, dan selisihnya justru yang
--                             ingin dilihat orang

begin;

create or replace function hitung_hari(p_resto_id text, p_tanggal date)
returns table (
  cash_expected bigint,
  qris_expected bigint,
  qris_static_expected bigint,
  transfer_expected bigint,
  cash_counted bigint,
  qris_settled bigint,
  gateway_fee bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with pesanan as (
    select _normalize_payment_method(o.source, o.payment_method) as metode,
           o.total
    from orders o
    where o.resto_id = p_resto_id
      and o.payment_status = 'paid'
      -- Tanggal WIB-nya, bukan tanggal UTC baris itu.
      and (o.created_at at time zone 'Asia/Jakarta')::date = p_tanggal
  ),
  shift as (
    -- Sisi tunai diambil dari tutup shift, bukan disusun ulang. Yang
    -- dihitung tangan di laci adalah satu-satunya kebenaran soal tunai.
    select coalesce(sum(s.counted_cash), 0) as dihitung
    from cashier_shifts s
    where s.resto_id = p_resto_id
      and s.closed_at is not null
      and (s.closed_at at time zone 'Asia/Jakarta')::date = p_tanggal
  ),
  cair as (
    select coalesce(sum(g.net_amount), 0) as bersih,
           coalesce(sum(g.fee_amount), 0) as biaya
    from gateway_settlements g
    where g.resto_id = p_resto_id
      and g.settled_on = p_tanggal
  )
  select
    coalesce((select sum(total) from pesanan where metode = 'cash'), 0)::bigint,
    coalesce((select sum(total) from pesanan where metode = 'qris'), 0)::bigint,
    coalesce((select sum(total) from pesanan where metode = 'qris_static'), 0)::bigint,
    coalesce((select sum(total) from pesanan where metode = 'transfer'), 0)::bigint,
    (select dihitung from shift)::bigint,
    (select bersih from cair)::bigint,
    (select biaya from cair)::bigint;
$$;

grant execute on function hitung_hari(text, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Menutup sebuah hari
-- ─────────────────────────────────────────────────────────────────────
--
-- Angkanya dihitung SERVER saat ditutup, bukan dikirim aplikasi. Angka
-- yang membekukan sebuah hari tidak boleh berasal dari perangkat yang
-- kebetulan menekan tombolnya — itu aturan yang sama dengan tutup shift.
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
  v_row daily_settlements;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'finance'])) then
    raise exception 'Hanya Owner dan Finance yang boleh menutup buku.';
  end if;

  -- Hari yang belum selesai tidak bisa ditutup. Menutup hari ini pada
  -- pukul dua siang membekukan angka yang masih akan bertambah sampai
  -- malam, dan selisihnya muncul besok sebagai uang yang seolah hilang.
  if p_tanggal >= (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Hari ini belum selesai. Tutup buku paling cepat besok.';
  end if;

  -- Shift yang masih terbuka berarti uang laci belum dihitung. Menutup
  -- buku sebelum itu membekukan sisi tunai yang belum ada angkanya.
  if exists (
    select 1 from cashier_shifts s
    where s.resto_id = p_resto_id
      and s.closed_at is null
      and (s.opened_at at time zone 'Asia/Jakarta')::date <= p_tanggal
  ) then
    raise exception 'Masih ada shift kasir yang belum ditutup.';
  end if;

  select * into v_angka from hitung_hari(p_resto_id, p_tanggal);

  insert into daily_settlements (
    resto_id, settled_on,
    cash_expected, qris_expected, qris_static_expected, transfer_expected,
    cash_counted, qris_settled, gateway_fee,
    status, note, settled_by, settled_at
  ) values (
    p_resto_id, p_tanggal,
    v_angka.cash_expected, v_angka.qris_expected,
    v_angka.qris_static_expected, v_angka.transfer_expected,
    v_angka.cash_counted, v_angka.qris_settled, v_angka.gateway_fee,
    'settled', nullif(btrim(coalesce(p_note, '')), ''), v_email, now()
  )
  on conflict (resto_id, settled_on) do update
    set cash_expected = excluded.cash_expected,
        qris_expected = excluded.qris_expected,
        qris_static_expected = excluded.qris_static_expected,
        transfer_expected = excluded.transfer_expected,
        cash_counted = excluded.cash_counted,
        qris_settled = excluded.qris_settled,
        gateway_fee = excluded.gateway_fee,
        status = 'settled',
        note = excluded.note,
        settled_by = excluded.settled_by,
        settled_at = excluded.settled_at
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function tutup_hari(text, date, text) to authenticated;

-- Membuka kembali hari yang sudah ditutup.
--
-- Ada, dan sengaja tidak disembunyikan: hari yang ditutup terlalu cepat
-- — sebelum pencairan gateway-nya masuk, misalnya — harus bisa
-- diperbaiki. Yang tidak boleh adalah membukanya tanpa jejak, jadi
-- statusnya kembali 'open' sementara angka bekunya TETAP tersimpan.
create or replace function buka_hari(p_resto_id text, p_tanggal date)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'finance'])) then
    raise exception 'Hanya Owner dan Finance yang boleh membuka buku.';
  end if;

  update daily_settlements
     set status = 'open'
   where resto_id = p_resto_id and settled_on = p_tanggal;
end;
$$;

grant execute on function buka_hari(text, date) to authenticated;

commit;
