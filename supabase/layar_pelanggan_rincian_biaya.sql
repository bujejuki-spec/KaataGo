-- KaataGo - layar pelanggan menyebut dari mana totalnya berasal.
--
-- Jalankan SETELAH layar_pelanggan_rinci.sql. Aman diulang.
--
-- Layar depan sudah menampilkan apa yang dipesan dan berapa totalnya.
-- Yang belum: jarak di antara keduanya. Pelanggan yang menjumlahkan
-- sendiri baris-baris pesanannya mendapat angka yang lebih kecil
-- daripada yang tertulis besar-besar di bawahnya, dan selisihnya —
-- service sepuluh persen, PPN sebelas — tidak disebut di mana pun.
--
-- Yang terjadi berikutnya selalu sama: pelanggan bertanya ke kasir, dan
-- kasir menjelaskan dengan mulut hal yang seharusnya sudah tertulis.
-- Pada jam ramai, pertanyaan itu tidak ditanyakan — dibayar saja dengan
-- perasaan ditagih lebih.
--
-- Satu kolom, bukan empat.
--
-- Rinciannya selalu ditulis dan dibaca sekaligus; memecahnya jadi empat
-- kolom cuma menambah empat parameter yang harus diteruskan utuh di
-- setiap pemanggilan, dan baris ini memang bukan catatan uang yang
-- dipakai membukukan apa pun.

begin;

-- {"subtotal": 111000, "service": 10000, "ppn": 12100,
--  "discount": 5000, "discount_name": "Promo Jumat",
--  "ppn_percent": 11, "service_percent": 10}
--
-- Null untuk baris lama dan untuk tagihan tanpa biaya tambahan sama
-- sekali — layar depannya menampilkan totalnya saja, tanpa daftar berisi
-- satu baris yang mengulang angka yang sama.
alter table customer_displays add column if not exists breakdown jsonb;

commit;

begin;

-- Fungsi lamanya dibuang lebih dulu, bukan ditimpa.
--
-- `create or replace` dengan daftar parameter yang berbeda TIDAK
-- menimpa apa pun — ia membuat fungsi KEDUA dengan nama yang sama.
drop function if exists set_customer_display(
  text, text, bigint, text, text, text, jsonb, text, text, text, text);

create or replace function set_customer_display(
  p_resto_id text,
  p_status text,
  p_amount bigint default null,
  p_qr_string text default null,
  p_label text default null,
  p_payment_method text default null,
  p_items jsonb default null,
  p_qr_image_url text default null,
  p_bank_name text default null,
  p_account_number text default null,
  p_account_holder text default null,
  p_breakdown jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'admin', 'kasir'])) then
    raise exception 'Tidak berwenang atas layar merchant ini';
  end if;

  insert into customer_displays (
    resto_id, status, amount, qr_string, label,
    payment_method, items, qr_image_url,
    bank_name, account_number, account_holder, breakdown,
    updated_by, updated_at
  ) values (
    p_resto_id, coalesce(p_status, 'idle'), p_amount, p_qr_string, p_label,
    p_payment_method, p_items, p_qr_image_url,
    p_bank_name, p_account_number, p_account_holder, p_breakdown,
    auth.jwt() ->> 'email', now()
  )
  -- Pembaruan susulan tidak menghapus rincian yang sudah ada.
  --
  -- Layar QRIS dinamis memanggil fungsi ini untuk kedua kalinya begitu
  -- QR-nya terbit dari penyedia pembayaran, dan yang dibawanya cuma
  -- nominal dan QR — ia tidak memegang isi keranjangnya.
  --
  -- Kecuali saat dipadamkan: 'idle' mengosongkan semuanya, karena
  -- tagihan orang sebelumnya tidak boleh tertinggal di depan pelanggan
  -- berikutnya.
  on conflict (resto_id) do update
    set status = excluded.status,
        amount = excluded.amount,
        qr_string = excluded.qr_string,
        label = excluded.label,
        payment_method = case when excluded.status = 'idle' then null
          else coalesce(excluded.payment_method, customer_displays.payment_method) end,
        items = case when excluded.status = 'idle' then null
          else coalesce(excluded.items, customer_displays.items) end,
        qr_image_url = case when excluded.status = 'idle' then null
          else coalesce(excluded.qr_image_url, customer_displays.qr_image_url) end,
        bank_name = case when excluded.status = 'idle' then null
          else coalesce(excluded.bank_name, customer_displays.bank_name) end,
        account_number = case when excluded.status = 'idle' then null
          else coalesce(excluded.account_number, customer_displays.account_number) end,
        account_holder = case when excluded.status = 'idle' then null
          else coalesce(excluded.account_holder, customer_displays.account_holder) end,
        breakdown = case when excluded.status = 'idle' then null
          else coalesce(excluded.breakdown, customer_displays.breakdown) end,
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$fn$;

revoke all on function set_customer_display(
  text, text, bigint, text, text, text, jsonb, text, text, text, text, jsonb)
  from public, anon;
grant execute on function set_customer_display(
  text, text, bigint, text, text, text, jsonb, text, text, text, text, jsonb)
  to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select resto_id, status, amount, breakdown, updated_at
--   from customer_displays;
