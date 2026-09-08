-- KaataGo - tagihan yang belum waktunya ikut hilang saat tanggalnya diubah.
--
-- Jalankan SETELAH billing.sql dan billing_due_day.sql. Aman diulang.
--
-- Tagihan diterbitkan begitu jatuh temponya tinggal tujuh hari lagi.
-- Kalau sesudah itu tanggal tagihnya diubah, tagihan yang terlanjur
-- terbit tetap menempel di tab Tagihan — mengacu pada jadwal yang sudah
-- tidak ada lagi. Merchant melihat tagihan bertanggal lama, KaataGo
-- Admin melihatnya juga, dan tidak ada satu pun yang menghapusnya
-- karena tidak ada yang bertugas melakukannya.
--
-- Sekarang perubahan setelan langganan membatalkannya sendiri.
--
-- DIBATALKAN, bukan dihapus. Nomor tagihannya sudah terlanjur ada di
-- luar sana — di layar merchant, dan di penyedia pembayaran. Baris yang
-- lenyap meninggalkan nomor yang statusnya menggantung terbuka di sana
-- selamanya, tanpa satu pun catatan di sisi kita yang menjelaskan ke
-- mana perginya. Status 'cancelled' menjawab pertanyaan itu.
--
-- ── Yang TIDAK ikut dibatalkan, dan kenapa ──────────────────────────────
--
-- 1. Yang sudah dibayar, sedang diperiksa, atau dibebaskan. Tagihan yang
--    uangnya sudah berpindah adalah catatan, bukan jadwal — membatalkannya
--    berarti membatalkan bukti pembayaran orang.
--
-- 2. Yang jatuh temponya SUDAH LEWAT. Itu utang yang benar-benar ada,
--    dan mengubah tanggal tagih tidak membatalkan bulan yang sudah
--    terpakai. Kalau ikut terhapus, mengubah satu angka di setelan jadi
--    cara membatalkan tunggakan — dan itu bukan fitur, itu lubang.
--
-- Jadi yang dibatalkan hanya tagihan yang belum dibayar DAN belum jatuh
-- tempo DAN tidak lagi cocok dengan jadwal yang berlaku sekarang.

begin;

alter table billing_invoices drop constraint if exists billing_invoices_status_check;
alter table billing_invoices add constraint billing_invoices_status_check
  check (status in ('unpaid', 'review', 'paid', 'waived', 'cancelled'));

create or replace function _bersihkan_tagihan_tak_berlaku(
  p_resto_id text,
  p_billing_day smallint,
  p_active boolean,
  p_monthly_price bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_due date;
  v_count integer;
begin
  -- Jadwal yang berlaku sekarang, menurut setelan yang baru.
  v_due := _billing_due_on(coalesce(p_billing_day, 1::smallint), current_date);

  update billing_invoices
     set status = 'cancelled'
   where resto_id = p_resto_id
     and status = 'unpaid'
     -- Belum jatuh tempo. Yang sudah lewat adalah tunggakan.
     and due_date > current_date
     and (
       -- Langganannya dimatikan atau harganya dinolkan: tidak ada lagi
       -- dasar untuk menagih periode yang belum berjalan.
       coalesce(p_active, false) = false
       or coalesce(p_monthly_price, 0) <= 0
       -- Jatuh temponya bergeser karena tanggal tagihnya diubah.
       or due_date <> v_due
       -- Jadwal barunya masih lebih dari tujuh hari lagi, jadi belum
       -- waktunya ada tagihan sama sekali. Tujuh, bukan tiga: angka itu
       -- yang dipakai generate_billing_invoices, dan pengingat H-3
       -- membutuhkan tagihan yang sudah ada untuk ditunjuk. Dua tempat
       -- yang memakai angka berbeda akan saling menghapus dan
       -- menerbitkan tagihan yang sama tiap hari.
       or v_due - current_date > 7
     );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Dijalankan pemicu, bukan diserahkan ke layar yang menyimpan setelannya.
--
-- Setelan langganan bisa diubah dari layar KaataGo Admin, dari SQL
-- Editor, atau dari mana pun nanti. Pembersihan yang dititipkan pada
-- salah satu pemanggil akan terlewat di pemanggil berikutnya, dan yang
-- terlihat adalah tagihan hantu yang muncul lagi tanpa sebab.
create or replace function _trigger_bersihkan_tagihan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform _bersihkan_tagihan_tak_berlaku(
    new.resto_id, new.billing_day, new.active, new.monthly_price);
  return new;
end;
$$;

drop trigger if exists bersihkan_tagihan_saat_setelan_berubah on resto_billing;
create trigger bersihkan_tagihan_saat_setelan_berubah
  after update of billing_day, active, monthly_price on resto_billing
  for each row
  execute function _trigger_bersihkan_tagihan();

commit;

-- Membersihkan yang terlanjur menggantung dari sebelum pemicunya ada.
--
-- Dipisah dari transaksi di atas: kalau ada satu baris yang menolak
-- diubah, pemicunya tetap terpasang. Yang tertinggal bisa dibereskan
-- lagi hanya dengan menyimpan ulang setelan langganannya.
do $$
declare
  b record;
begin
  for b in select * from resto_billing loop
    perform _bersihkan_tagihan_tak_berlaku(
      b.resto_id, b.billing_day, b.active, b.monthly_price);
  end loop;
end;
$$;
