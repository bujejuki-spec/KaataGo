-- KaataGo - pesanan QRIS yang tidak dibayar ikut hangus.
--
-- Jalankan SETELAH cash_payment_expiry.sql dan stok_terkunci.sql.
-- Aman diulang.
--
-- Sampai sekarang hanya pesanan tunai yang hangus setelah 30 menit.
-- QRIS sengaja dikecualikan, dengan alasan yang waktu itu masuk akal:
-- pesanan QRIS punya tenggangnya sendiri di sisi penyedia pembayaran,
-- dan membatalkannya dari sini berarti membatalkan pesanan yang uangnya
-- mungkin sedang dalam perjalanan.
--
-- Yang tidak diperhitungkan: sebagian besar merchant belum memasang
-- payment gateway sama sekali. Bagi mereka QR-nya tidak punya tenggang
-- apa pun, jadi pesanan QRIS yang ditinggalkan menetap SELAMANYA di
-- layar Pending Payment dan di dapur — persis penyakit yang dulu
-- diperbaiki untuk sisi tunai, cuma di kolom sebelahnya.
--
-- Sekarang keduanya hangus pada tenggang yang sama.
--
-- ── Soal uang yang sedang di jalan ────────────────────────────────────
--
-- Risikonya nyata dan tidak dihilangkan berkas ini: pembayaran yang
-- diterima penyedia di menit ke-31 tiba pada pesanan yang sudah hangus.
-- Yang dilakukan di sini cuma memastikan kejadian itu tidak berakhir
-- sebagai uang yang hilang tanpa jejak — `bangkitkan_pesanan_terbayar`
-- di bawah mengembalikan pesanan yang hangus menjadi lunas kalau
-- pembayarannya benar-benar datang.
--
-- Tenggangnya juga sengaja dibuat lebih panjang daripada masa berlaku
-- QR mana pun yang wajar: QR yang sudah kedaluwarsa tidak bisa dibayar,
-- jadi selisih waktunya bekerja sebagai bantalan, bukan sebagai jebakan.

begin;

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
      -- Tunai DAN QRIS. Yang menentukan bukan cara bayarnya melainkan
      -- kenyataan yang sama pada keduanya: pesanan yang tidak pernah
      -- dilunasi tetap menempati layar kasir dan dapur.
      -- QRIS Statis ikut: alurnya sama dengan tunai — pesanannya
      -- menunggu dibayar di kasir, dan yang ditinggalkan menempati
      -- layar Pending Payment persis seperti yang lain.
      and _normalize_payment_method(source, payment_method)
            in ('cash', 'qris', 'qris_static')
      and created_at <= now() - interval '30 minutes'
    returning resto_id, items
  loop
    -- Stoknya kembali ke rak. Yang tidak jadi terjual harus kembali bisa
    -- dijual — tanpa ini, tiap pesanan yang ditinggalkan menelan stoknya
    -- diam-diam.
    perform kembalikan_stok(v_baris.resto_id, v_baris.items);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Kalau uangnya ternyata datang juga
-- ─────────────────────────────────────────────────────────────────────
--
-- Dipanggil jalur yang menyatakan sebuah pesanan lunas — webhook
-- penyedia pembayaran, atau kasir yang menerima uangnya. Pesanan yang
-- sudah hangus dikembalikan jadi lunas, dan stoknya diambil lagi.
--
-- Tanpa ini, pembayaran yang tiba terlambat menghasilkan keadaan yang
-- paling buruk dari semuanya: uangnya masuk, pesanannya tidak ada, dan
-- tidak ada satu pun baris yang menghubungkan keduanya. Yang menanggung
-- kebingungannya pelanggan yang sudah membayar.
--
-- Mengembalikan true kalau ada yang dibangkitkan.
create or replace function bangkitkan_pesanan_terbayar(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found or v_order.payment_status <> 'expired' then
    return false;
  end if;

  update orders set payment_status = 'paid' where id = p_order_id;

  -- Stoknya diambil lagi, karena kehangusannya tadi mengembalikannya.
  -- Kalau barangnya keburu habis, pengambilannya gagal dan seluruh
  -- pembangkitan ini dibatalkan — pesanan yang tidak bisa dipenuhi lebih
  -- baik tetap hangus dan uangnya dikembalikan, daripada diterima lalu
  -- tidak ada barangnya.
  perform ambil_stok(v_order.resto_id, v_order.items);
  return true;
end;
$$;

grant execute on function bangkitkan_pesanan_terbayar(uuid) to authenticated;
