-- KaataGo - layar pelanggan menampilkan rincian, bukan cuma nominal.
--
-- Jalankan SETELAH customer_display.sql. Aman diulang.
--
-- Sampai sekarang layar depan cuma bisa menyebut satu angka dan satu QR.
-- Untuk QRIS dinamis itu memang cukup — yang dilihat pelanggan adalah
-- kode yang dipindainya. Untuk cara bayar yang lain, ia tidak
-- menampilkan apa pun yang berguna:
--
--   - Tunai: pelanggan menyerahkan uang tanpa pernah melihat apa saja
--     yang ditagihkan. Perbedaan antara yang dipesan dan yang ditagih
--     baru ketahuan setelah struk tercetak, kalau ketahuan.
--   - QRIS Statis: QR-nya milik merchant dan berupa gambar, bukan teks
--     EMVCo yang bisa digambar ulang — jadi tidak ada yang bisa dipindai
--     pelanggan dari layar depan sama sekali.
--   - Transfer: nomor rekeningnya cuma ada di layar kasir, dan dibacakan
--     dengan suara di tengah keramaian.
--
-- Kolom di bawah ini yang membuat ketiganya bisa ditampilkan.

begin;

-- Cara bayar yang sedang berjalan, supaya layar depan tahu harus
-- menampilkan apa. Null untuk baris lama.
alter table customer_displays add column if not exists payment_method text;

-- Rincian pesanannya: [{"nama": "...", "qty": 2, "total": 40000}, ...]
--
-- Disalin, bukan ditunjuk ke pesanannya — dengan alasan yang sama
-- seperti nominalnya: di alur kasir, pesanannya baru dibuat sesudah
-- pembayaran dikonfirmasi.
alter table customer_displays add column if not exists items jsonb;

-- Gambar QR statis milik merchant.
alter table customer_displays add column if not exists qr_image_url text;

-- Rekening tujuan transfer, disalin saat itu juga. Membacanya dari
-- `bank_accounts` di perangkat layar depan berarti perangkat itu perlu
-- hak baca atas rekening perusahaan — untuk menampilkan satu baris yang
-- memang sedang ditunjukkan ke pelanggan.
alter table customer_displays add column if not exists bank_name text;
alter table customer_displays add column if not exists account_number text;
alter table customer_displays add column if not exists account_holder text;

commit;

begin;

-- Fungsi lamanya dibuang lebih dulu, bukan ditimpa.
--
-- `create or replace` dengan daftar parameter yang berbeda TIDAK
-- menimpa apa pun — ia membuat fungsi KEDUA dengan nama yang sama. Yang
-- dipanggil aplikasi kemudian bergantung pada pencocokan tipe, dan yang
-- lama tetap ada untuk dipanggil siapa pun yang belum diperbarui.
drop function if exists set_customer_display(text, text, bigint, text, text);

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
  p_account_holder text default null
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
    bank_name, account_number, account_holder,
    updated_by, updated_at
  ) values (
    p_resto_id, coalesce(p_status, 'idle'), p_amount, p_qr_string, p_label,
    p_payment_method, p_items, p_qr_image_url,
    p_bank_name, p_account_number, p_account_holder,
    auth.jwt() ->> 'email', now()
  )
  -- Pembaruan susulan tidak menghapus rincian yang sudah ada.
  --
  -- Layar QRIS dinamis memanggil fungsi ini untuk kedua kalinya begitu
  -- QR-nya terbit dari penyedia pembayaran, dan yang dibawanya cuma
  -- nominal dan QR — ia tidak memegang isi keranjangnya. Tanpa coalesce
  -- di bawah, panggilan kedua itu menghapus rincian pesanan yang baru
  -- saja ditampilkan.
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
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$fn$;

revoke all on function set_customer_display(
  text, text, bigint, text, text, text, jsonb, text, text, text, text)
  from public, anon;
grant execute on function set_customer_display(
  text, text, bigint, text, text, text, jsonb, text, text, text, text)
  to authenticated;

commit;
