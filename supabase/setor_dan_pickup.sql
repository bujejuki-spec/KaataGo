-- KaataGo - setoran menyebut rekeningnya, dan cash pickup.
--
-- Jalankan SETELAH cash_deposit.sql dan rekening_perusahaan.sql.
-- Aman diulang.
--
-- Tiga hal:
--
--   1. Setoran mencatat KE REKENING MANA uangnya disetor. Sampai
--      sekarang tujuannya cuma disalin sebagai tiga potong teks di
--      dialognya — nama bank, nomor, atas nama — dan tidak ada satu pun
--      tautan ke rekening yang sebenarnya. Begitu sebuah merchant punya
--      dua rekening, tidak ada cara tahu setoran ini masuk ke yang mana,
--      dan mencocokkannya dengan mutasi bank jadi tebakan.
--
--   2. Bukti transfer wajib. Setoran tanpa bukti adalah pernyataan
--      sepihak bahwa uang sudah berpindah, dan yang memeriksanya nanti
--      tidak punya apa pun untuk dibandingkan dengan mutasi rekening.
--
--   3. Cash pickup: uang laci diambil petugas penjemputan, bukan
--      disetor sendiri oleh kasir.
--
-- ── Kenapa pickup ditaruh di tabel setoran, bukan tabelnya sendiri ────
--
-- Karena yang terjadi pada uangnya sama persis: lembarannya keluar dari
-- laci. Saldo Cash sudah tahu cara menghitung itu — `cashOnHand`
-- mengurangi setiap baris `cash_deposits` yang tidak ditolak.
--
-- Tabel baru berarti Saldo Cash harus diajari sumber kedua, dan selama
-- ia belum diajari, uang yang sudah dibawa pergi masih dihitung ada di
-- laci. Itu persis kelas kekeliruan yang sudah berkali-kali diperbaiki
-- di aplikasi ini: angka yang mengaku menyebut isi laci sementara
-- lacinya sudah kosong.
--
-- Yang membedakan keduanya cuma keterangannya, dan itu cukup jadi kolom.

begin;

-- Rekening tujuannya. Null untuk baris lama yang dibuat sebelum
-- rekening punya keberadaan sendiri — sengaja tidak ditebak mundur:
-- menebak setoran lama masuk ke rekening mana berarti membuat data yang
-- terlihat pasti padahal karangan.
alter table cash_deposits
  add column if not exists bank_account_id uuid references bank_accounts (id);

-- Cara uangnya keluar laci.
alter table cash_deposits
  add column if not exists method text not null default 'setor';

alter table cash_deposits drop constraint if exists cash_deposits_method_check;
alter table cash_deposits add constraint cash_deposits_method_check
  check (method in ('setor', 'pickup'));

-- Siapa yang menjemput uangnya. Diisi hanya untuk pickup.
alter table cash_deposits add column if not exists picked_up_by text;

-- Nomor segel kantong uangnya. Opsional: sebagian jasa penjemputan
-- memakainya, sebagian tidak, dan mewajibkannya berarti menahan kasir
-- yang jasanya memang tidak memberi segel.
alter table cash_deposits add column if not exists seal_number text;

-- Pickup wajib menyebut siapa yang menjemput.
--
-- Uang yang keluar laci tanpa nama penerima adalah uang yang tidak bisa
-- ditanyakan ke siapa pun besok pagi.
alter table cash_deposits drop constraint if exists cash_deposits_pickup_check;
alter table cash_deposits add constraint cash_deposits_pickup_check
  check (method <> 'pickup'
         or coalesce(btrim(picked_up_by), '') <> '');

create index if not exists cash_deposits_rekening_idx
  on cash_deposits (bank_account_id);

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Bukti wajib, tapi hanya untuk yang baru
-- ─────────────────────────────────────────────────────────────────────
--
-- Tidak bisa jadi NOT NULL: baris lama dibuat waktu buktinya memang
-- opsional, dan menolaknya sekarang berarti tabelnya tidak bisa diubah
-- sama sekali sampai seseorang mengarang bukti untuk setoran tahun lalu.
--
-- Pemicu saat insert menegakkannya ke depan saja. Yang lama tetap apa
-- adanya — tercatat tanpa bukti, dan memang begitu kenyataannya.

begin;

create or replace function _wajib_bukti_setoran()
returns trigger
language plpgsql
as $$
begin
  if coalesce(btrim(new.proof_base64), '') = '' then
    raise exception 'Bukti transfer wajib dilampirkan.';
  end if;
  return new;
end;
$$;

drop trigger if exists wajib_bukti_setoran on cash_deposits;
create trigger wajib_bukti_setoran
  before insert on cash_deposits
  for each row
  execute function _wajib_bukti_setoran();

commit;
