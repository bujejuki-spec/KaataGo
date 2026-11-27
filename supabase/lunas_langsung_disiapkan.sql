-- KaataGo — pesanan yang lunas langsung masuk Diproses.
--
-- Jalankan SETELAH mark_order_paid.sql. Aman diulang.
--
-- ═══════════════════════════════════════════════════════════════════
-- Kenapa di basis data, bukan di aplikasi
-- ═══════════════════════════════════════════════════════════════════
--
-- `payment_status` jadi 'paid' dari enam tempat yang berbeda:
--
--   mark_order_paid()        — pelanggan QRIS dari HP-nya sendiri
--   payment_gateway          — webhook penyedia pembayaran
--   qris_hangus              — pelunasan setelah QR kedaluwarsa
--   settleCashPayment()      — kasir menerima tunai (UPDATE langsung)
--   settlePayment()          — kasir mengganti cara bayarnya
--   insert pesanan           — penjualan kasir yang lahir sudah lunas
--
-- Tiga yang pertama fungsi SQL, dua berikutnya UPDATE langsung dari
-- aplikasi, yang terakhir INSERT. Menaruh aturannya di aplikasi berarti
-- menuliskannya enam kali dan melupakannya di tempat ketujuh — dan yang
-- terlupa tidak akan berbunyi: pesanannya cuma diam di Menunggu
-- Diproses sampai ada yang menyadarinya.
--
-- Satu pemicu BEFORE menjangkau keenamnya.
--
-- ── Kenapa BEFORE, bukan AFTER ───────────────────────────────────────
--
-- BEFORE mengubah barisnya sebelum ditulis: satu kali tulis, dan tidak
-- ada pemicu yang memanggil dirinya sendiri. AFTER harus menjalankan
-- UPDATE kedua — yang membangunkan pemicu ini lagi, mengirim dua
-- payload realtime untuk satu perubahan, dan membuat tiap pelanggan yang
-- membuka menu menerima barisnya dua kali.

begin;

create or replace function _pesanan_lunas_langsung_disiapkan()
returns trigger
language plpgsql
as $fn$
begin
  -- Hanya dari 'waiting'.
  --
  -- Sengaja bukan "apa pun selain done": pesanan yang sudah ditandai
  -- selesai lalu cara bayarnya diperbaiki kasir TIDAK boleh kembali ke
  -- Diproses. Yang terlihat waiter adalah pesanan selesai yang
  -- tiba-tiba muncul lagi di antrean, tanpa ada yang memesannya.
  --
  -- 'cancelled' juga tidak ikut, dengan alasan yang sama.
  if new.payment_status = 'paid'
     and coalesce(new.kitchen_status, 'waiting') = 'waiting' then
    new.kitchen_status := 'onProgress';
  end if;
  return new;
end;
$fn$;

-- `update of payment_status` saja, bukan seluruh kolom.
--
-- Baris pesanan diperbarui sering — status dapur, barang yang sudah
-- siap, catatan. Pemicu yang bangun di tiap perubahan itu bekerja
-- berkali-kali untuk menjawab pertanyaan yang jawabannya tidak berubah.
--
-- `kitchen_status` sengaja TIDAK ikut dalam daftar. Kalau ikut, siapa
-- pun yang nanti menambahkan tombol "kembalikan ke Menunggu" akan
-- mendapati tombolnya tidak bekerja — statusnya dilontarkan balik ke
-- Diproses di dalam transaksi yang sama, tanpa jejak.
drop trigger if exists trg_lunas_langsung_disiapkan on orders;
create trigger trg_lunas_langsung_disiapkan
  before insert or update of payment_status on orders
  for each row execute function _pesanan_lunas_langsung_disiapkan();

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Pesanan hari ini yang sudah lunas tapi masih menunggu
-- ═══════════════════════════════════════════════════════════════════
--
-- Mereka berada di keadaan yang sudah tidak ada lagi dalam alur baru:
-- lunas, tapi menunggu konfirmasi yang tombolnya dicabut.
--
-- ── Kenapa hanya hari ini ────────────────────────────────────────────
--
-- `watchAktif` — yang mengisi layar Status Pesanan — tidak menyaring
-- tanggal; ia mengambil sejumlah pesanan terbaru. Mendorong SELURUH
-- pesanan lunas-tapi-menunggu sejak hari pertama ke Diproses berarti
-- membangkitkan pesanan berbulan lalu ke dalam antrean waiter hari ini.
--
-- Yang kemarin dan sebelumnya ditinggalkan apa adanya. Itu riwayat, dan
-- riwayat tidak perlu diperbaiki supaya cocok dengan alur yang baru.

begin;

update orders
set kitchen_status = 'onProgress'
where payment_status = 'paid'
  and coalesce(kitchen_status, 'waiting') = 'waiting'
  and created_at >= date_trunc('day', now() at time zone 'Asia/Jakarta')
                      at time zone 'Asia/Jakarta';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Memeriksanya
-- ═══════════════════════════════════════════════════════════════════
--
-- Pemicunya terpasang?
--
--   select tgname, tgenabled
--   from pg_trigger
--   where tgrelid = 'orders'::regclass and not tgisinternal;
--
-- Masih ada yang lunas tapi menunggu? (hari ini harus 0)
--
--   select (created_at at time zone 'Asia/Jakarta')::date as tanggal,
--          count(*)
--   from orders
--   where payment_status = 'paid'
--     and coalesce(kitchen_status, 'waiting') = 'waiting'
--   group by 1
--   order by 1 desc;
