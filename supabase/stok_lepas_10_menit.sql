-- KaataGo - stok yang dipesan dan tidak dibayar kembali ke rak
-- setelah 10 menit, bukan 30.
--
-- Jalankan SETELAH qris_hangus.sql dan stok_terkunci.sql. Aman diulang.
--
-- ── Kapan sebenarnya stoknya terkunci ────────────────────────────────
--
-- Bukan saat pelanggan sedang memilih. Selama keranjangnya belum
-- dikirim, tidak ada satu pun baris di basis data yang tahu ia ada —
-- stok baru berkurang saat pesanannya dibuat, lewat `ambil_stok`.
--
-- Jadi yang dipersingkat di sini adalah tenggang antara pesanan dibuat
-- dan pembayarannya datang. Itu memang jendela yang dimaksud: selama
-- jendela itu terbuka, porsi terakhir tercatat sudah terjual kepada
-- orang yang mungkin tidak pernah kembali, dan pelanggan berikutnya —
-- yang berdiri di depan kasir dengan uang di tangan — ditolak.
--
-- ── Kenapa pesanannya ikut hangus di menit yang sama ─────────────────
--
-- Melepas stoknya saja, dan membiarkan pesanannya menunggu sampai menit
-- ke-30, akan melahirkan keadaan yang lebih buruk daripada keduanya:
-- pesanan yang masih bisa dibayar padahal barangnya sudah dijual ke
-- orang lain. Yang membayarnya akan menunggu makanan yang tidak ada.
--
-- Karena itu tenggangnya satu: 10 menit, dan keduanya berakhir
-- bersamaan. Pembayaran yang datang terlambat tetap tidak hilang —
-- `bangkitkan_pesanan_terbayar` mengembalikan pesanan yang hangus
-- menjadi lunas dan mengambil stoknya lagi, dan kalau stoknya sudah
-- habis, penolakannya terjadi di tempat yang bisa ditangani orang.

begin;

create or replace function expire_unpaid_cash_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
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
      -- Tunai, QRIS, dan QRIS Statis. Yang menentukan bukan cara
      -- bayarnya melainkan kenyataan yang sama pada ketiganya: pesanan
      -- yang tidak pernah dilunasi menahan stok dan menempati layar
      -- kasir maupun dapur.
      --
      -- Pelanggan yang masuk dan yang tidak masuk sama saja di sini:
      -- yang menahan stok adalah pesanannya, bukan akunnya.
      and _normalize_payment_method(source, payment_method)
            in ('cash', 'qris', 'qris_static')
      and created_at <= now() - interval '10 minutes'
    returning resto_id, items
  loop
    perform kembalikan_stok(v_baris.resto_id, v_baris.items);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$fn$;

commit;
