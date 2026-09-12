-- KaataGo - merchant benar-benar bisa membaca rekening KaataGo.
--
-- Jalankan SETELAH cara_tagih.sql. Aman diulang.
--
-- cara_tagih.sql sudah membuka baris `bank_accounts` milik resto
-- platform untuk semua orang. Itu ternyata belum cukup, dan
-- kekurangannya baru terlihat sekarang: aplikasi tidak membaca
-- `bank_accounts` secara langsung. Ia membacanya lewat
-- `resto_bank_accounts` — tabel penaut yang menjawab "rekening mana
-- dipakai resto mana" — dan policy baca tabel itu menuntut si pembaca
-- karyawan resto yang bersangkutan.
--
-- Merchant bukan karyawan 'kaatago'. Jadi baris penautnya tidak
-- terlihat, daftarnya kembali kosong, dan yang ditagih lewat transfer
-- melihat kartu rekening yang tidak berisi apa-apa — persis keadaan yang
-- ingin dihilangkan cara_tagih.sql.
--
-- Yang dibuka di sini cuma baris penaut milik resto platform. Isinya
-- tidak menyebut apa pun selain "rekening ini milik KaataGo", dan itu
-- memang yang sedang ditunjukkan ke merchant.

begin;

drop policy if exists "resto_bank_accounts: staff read" on resto_bank_accounts;
create policy "resto_bank_accounts: staff read" on resto_bank_accounts
  for select using (
    is_super_admin()
    or resto_id = 'kaatago'
    or is_resto_employee(resto_id,
         array['owner', 'finance', 'admin', 'kasir'])
  );

commit;
