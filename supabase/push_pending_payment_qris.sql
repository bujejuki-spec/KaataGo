-- KaataGo — pesanan pelanggan yang menunggu dibayar juga berbunyi
-- untuk QRIS Statis, bukan cuma tunai.
--
-- Jalankan SETELAH push_notifications.sql. Aman diulang.
--
-- ═══════════════════════════════════════════════════════════════════
-- Yang salah
-- ═══════════════════════════════════════════════════════════════════
--
-- `queue_push_pending_payment` menyaring `new.payment_method = 'cash'`.
-- Waktu ia ditulis, tunai memang satu-satunya cara bayar yang
-- menyisakan pekerjaan di kasir.
--
-- QRIS Statis menyisakan pekerjaan yang sama — kasir yang menyatakan
-- lunasnya, karena QR statis tidak membawa nominal dan tidak ada kabar
-- apa pun dari penyedia pembayaran. Tapi saringan itu tidak pernah
-- ikut diperlebar, jadi pesanan QRIS Statis masuk ke Pending Payment
-- tanpa satu pun pemberitahuan.
--
-- Tidak ada galat. Pesanannya ada di daftar, cuma tidak ada yang tahu
-- ia datang.
--
-- ── Memakai `isAwaitingPayment`-nya aplikasi, bukan daftar cara bayar
--
-- Aplikasi menentukan "menunggu dibayar" begitu: pesanan dari pelanggan
-- yang pembayarannya masih pending — tanpa menyebut cara bayarnya sama
-- sekali (`CustomerOrder.isAwaitingPayment`).
--
-- Fungsi ini sekarang bertanya dengan cara yang sama. Daftar cara bayar
-- yang ditulis tangan di sini adalah daftar yang akan ketinggalan lagi
-- pada cara bayar berikutnya — persis yang baru saja terjadi.

begin;

create or replace function queue_push_pending_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cara text;
begin
  -- Tidak menyaring cara bayarnya.
  --
  -- Pesanan pelanggan yang pembayarannya masih pending SELALU
  -- menyisakan pekerjaan di kasir, cara bayarnya apa pun. Yang
  -- membedakan cuma kalimatnya.
  if new.source = 'customer' and new.payment_status = 'pending' then
    v_cara := case new.payment_method
      when 'cash' then 'Pelanggan memilih bayar tunai di kasir'
      when 'qris_static' then 'Pelanggan bayar QRIS — tunggu bukti transfernya'
      else 'Menunggu pembayaran'
    end;

    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'pending_payment',
      jsonb_build_object(
        -- Sama dengan yang punya akses menu Pending Payment di
        -- `lib/utils/katalog_menu.dart`. Peran yang tidak bisa membuka
        -- layarnya tidak perlu dibangunkan olehnya.
        'audience', 'role', 'roles', array['kasir', 'admin', 'owner'],
        'title', 'Pesanan menunggu dibayar',
        'body', v_cara || ' — #' || upper(substr(new.id::text, 1, 8))
      )
    );
  end if;
  return new;
end;
$$;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Memeriksanya
-- ═══════════════════════════════════════════════════════════════════
--
-- Pemicunya masih terpasang? (fungsinya diganti, pemicunya tidak)
--
--   select tgname from pg_trigger
--   where tgrelid = 'orders'::regclass
--     and tgname = 'trg_queue_push_pending_payment';
--
-- Yang terkirim belakangan — isi kalimatnya menyebut cara bayarnya,
-- jadi tidak perlu disambungkan ke tabel pesanan:
--
--   select payload->>'body' as kabar, created_at
--   from push_outbox
--   where event = 'pending_payment'
--     and created_at > now() - interval '2 days'
--   order by created_at desc
--   limit 20;
--
-- Masih ada pesanan menunggu bayar yang TIDAK punya barisnya?
-- (harus 0 untuk pesanan sesudah query ini dijalankan)
--
--   select o.id, o.payment_method, o.created_at
--   from orders o
--   where o.source = 'customer'
--     and o.payment_status = 'pending'
--     and o.created_at > now() - interval '1 day'
--     and not exists (
--       select 1 from push_outbox p
--       where p.event = 'pending_payment'
--         and p.resto_id = o.resto_id
--         and p.payload->>'body' like '%' ||
--             upper(substr(o.id::text, 1, 8))
--     );
