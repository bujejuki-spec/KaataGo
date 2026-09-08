-- KaataGo - stok yang benar-benar menahan pesanan.
--
-- Jalankan SETELAH product_out_of_stock.sql. Aman diulang.
--
-- Sampai sekarang angka stok tidak menahan apa pun. Tiga orang yang
-- memesan barang terakhir secara bersamaan ketiganya berhasil, dan
-- `greatest(stock - qty, 0)` di decrement_stock justru menyembunyikan
-- kelebihannya: angkanya berhenti di 0, bukan turun ke -2, jadi tidak
-- ada satu pun jejak bahwa kelebihan pesanan pernah terjadi. Dapur baru
-- mengetahuinya saat menyiapkan pesanan kedua.
--
-- Dua hal yang diperbaiki di sini, dan keduanya harus ada bersamaan:
--
--   1. Stok diambil SEBELUM pesanannya dibuat, dan pengambilannya bisa
--      GAGAL. Yang tercepat menang; sisanya ditolak dengan menyebut
--      nama barangnya.
--
--   2. Produk yang stoknya menyentuh nol otomatis ditandai habis, jadi
--      ia langsung hilang dari menu tanpa menunggu resto menandainya.
--
-- Yang sengaja TIDAK berubah: produk yang stoknya `null` tidak dihitung
-- sama sekali dan tidak pernah ditolak. Itu seluruh alasan angka stok
-- dilepas dulu — nasi goreng tidak punya "sisa 7 porsi", dan resto yang
-- tidak menghitung tidak boleh kehilangan penjualan karenanya.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Mengambil stok, dan boleh menolak
-- ─────────────────────────────────────────────────────────────────────
--
-- p_items: jsonb array berisi {"productId": "...", "quantity": n}.
-- Bentuknya sengaja sama persis dengan `orders.items`, supaya
-- pengembaliannya nanti bisa membaca baris pesanannya apa adanya.
--
-- Semua atau tidak sama sekali. Pesanan berisi lima barang yang satu di
-- antaranya habis tidak boleh masuk separuh: yang lain sudah dipotong
-- stoknya untuk pesanan yang tidak pernah ada.
create or replace function ambil_stok(p_resto_id text, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_kena int;
  v_nama text;
begin
  -- Diurutkan menurut id, dan itu bukan kerapian.
  --
  -- Dua pesanan yang memuat barang yang sama dalam urutan berbeda saling
  -- mengunci baris yang sedang ditunggu lawannya, dan Postgres memutus
  -- salah satunya sebagai deadlock. Urutan yang sama untuk semua orang
  -- membuat keadaan itu tidak bisa terbentuk.
  for v_item in
    select (e ->> 'productId') as id,
           sum((e ->> 'quantity')::int) as qty
    from jsonb_array_elements(p_items) e
    group by 1
    order by 1
  loop
    -- Dijumlahkan lebih dulu lewat group by: satu produk kini boleh
    -- menempati beberapa baris pesanan (pedas dan tidak pedas), dan
    -- memeriksanya baris per baris meloloskan dua kali satu porsi
    -- terakhir.
    update products
       set stock = case when stock is null then null else stock - v_item.qty end,
           -- Menyentuh nol berarti habis, tanpa menunggu resto
           -- menandainya. Yang stoknya null tidak tersentuh.
           out_of_stock = case
             when stock is not null and stock - v_item.qty <= 0 then true
             else out_of_stock
           end
     where id = v_item.id
       and resto_id = p_resto_id
       and out_of_stock = false
       and (stock is null or stock >= v_item.qty);

    get diagnostics v_kena = row_count;

    if v_kena = 0 then
      -- Namanya dicari terpisah supaya pesannya bisa dibaca orang yang
      -- sedang memegang HP-nya, bukan berisi id yang tidak berarti
      -- apa-apa baginya.
      select name into v_nama from products where id = v_item.id;
      raise exception '% sudah habis. Hapus dari keranjang lalu pesan lagi.',
        coalesce(v_nama, 'Salah satu barang');
    end if;
  end loop;
end;
$$;

grant execute on function ambil_stok(text, jsonb) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Mengembalikan stok
-- ─────────────────────────────────────────────────────────────────────
--
-- Tanpa ini fiturnya justru merugikan: pesanan yang dibatalkan atau
-- hangus membawa stoknya ikut hilang, dan setelah beberapa hari resto
-- tidak bisa menjual barang yang sebenarnya ada di rak. Menahan
-- pesanan hanya benar kalau yang ditahan bisa dilepas lagi.
--
-- Penandaan habis ikut dicabut kalau stoknya kembali di atas nol —
-- karena penandaan itu tadi dipasang mesin, bukan orang.
create or replace function kembalikan_stok(p_resto_id text, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
begin
  for v_item in
    select (e ->> 'productId') as id,
           sum((e ->> 'quantity')::int) as qty
    from jsonb_array_elements(p_items) e
    group by 1
    order by 1
  loop
    update products
       set stock = case when stock is null then null else stock + v_item.qty end,
           out_of_stock = case
             when stock is not null and stock + v_item.qty > 0 then false
             else out_of_stock
           end
     where id = v_item.id
       and resto_id = p_resto_id;
  end loop;
end;
$$;

grant execute on function kembalikan_stok(text, jsonb) to anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Yang batal dan yang hangus mengembalikan stoknya
-- ─────────────────────────────────────────────────────────────────────
--
-- Badan kedua fungsi ini disalin apa adanya dari berkas aslinya, dan
-- yang ditambahkan cuma satu baris pengembalian stok. Ditulis ulang dari
-- ingatan, pemeriksaan kepemilikan di cancel_my_order nyaris ikut hilang
-- — dan tanpa pemeriksaan itu, nomor pesanan yang terbaca dari struk
-- orang lain sudah cukup untuk membatalkan pesanannya.
--
-- Tanda tangannya juga harus persis sama. `create or replace` dengan
-- daftar parameter yang berbeda tidak mengganti apa pun: ia membuat
-- fungsi KEDUA, dan yang dipanggil aplikasi tetap yang lama.

begin;

create or replace function cancel_my_order(
  p_order_id uuid,
  p_session_id text default null,
  p_email text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    return 'Pesanan tidak ditemukan.';
  end if;

  -- Miliknya sendiri. Pelanggan yang login dikenali dari emailnya, tamu
  -- dari session id yang tersimpan di HP-nya. Tanpa pemeriksaan ini,
  -- nomor pesanan yang terbaca dari struk orang lain sudah cukup untuk
  -- membatalkan pesanannya.
  if not (
    (p_email is not null and v_order.customer_label = p_email)
    or (p_session_id is not null and v_order.session_id = p_session_id)
  ) then
    return 'Pesanan ini bukan milikmu.';
  end if;

  if v_order.source <> 'customer' then
    return 'Pesanan yang diinput kasir dibatalkan lewat kasir.';
  end if;

  if v_order.payment_status = 'paid' then
    return 'Pesanan sudah dibayar. Hubungi kasir untuk pembatalan.';
  end if;

  if v_order.payment_status <> 'pending' then
    return 'Pesanan ini sudah tidak aktif.';
  end if;

  -- Dapur sudah mulai memasak berarti bahannya sudah terpakai.
  -- Membatalkannya sepihak dari HP memindahkan kerugiannya ke resto,
  -- dan yang menanggungnya bukan pihak yang membuat keputusannya.
  if v_order.kitchen_status <> 'waiting' then
    return 'Pesanan sudah mulai dimasak. Hubungi kasir kalau mau batal.';
  end if;

  update orders set payment_status = 'cancelled' where id = p_order_id;

  -- Stoknya kembali ke rak, di dalam transaksi yang sama dengan
  -- pembatalannya. Pesanan yang batal tapi stoknya tidak kembali adalah
  -- barang yang hilang dari penjualan tanpa pernah terjual.
  perform kembalikan_stok(v_order.resto_id, v_order.items);

  return null;
end;
$$;

grant execute on function cancel_my_order(uuid, text, text) to anon, authenticated;

-- Pesanan tunai yang lewat tenggang 30 menit. Alasannya sama persis
-- dengan pembatalan: yang tidak jadi terjual harus kembali bisa dijual.
create or replace function expire_unpaid_cash_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_baris record;
begin
  v_count := 0;
  for v_baris in
    update orders
    set payment_status = 'expired'
    where payment_status = 'pending'
      and source = 'customer'
      -- Hanya yang tunai. Pesanan QRIS punya tenggangnya sendiri di sisi
      -- penyedia pembayaran, dan membatalkannya dari sini berarti
      -- membatalkan pesanan yang uangnya mungkin sedang dalam perjalanan.
      and _normalize_payment_method(source, payment_method) = 'cash'
      and created_at <= now() - interval '30 minutes'
    returning resto_id, items
  loop
    perform kembalikan_stok(v_baris.resto_id, v_baris.items);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

commit;
