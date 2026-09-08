-- KaataGo - alamat surel merchant.
--
-- Aman dijalankan berulang kali.
--
-- Nomor telepon sudah ada sejak lama; surelnya belum. Keduanya dipakai
-- untuk hal yang sama dan saling menggantikan: mengirimkan tagihan
-- langganan yang belum dibayar, dan menghubungi merchant dari List
-- Merchant. Merchant yang cuma punya salah satunya tetap bisa dihubungi
-- lewat yang dia punya.
--
-- Sengaja tidak wajib. Memaksanya diisi berarti merchant lama tidak bisa
-- disimpan lagi sampai seseorang menelepon mereka satu per satu.

begin;

alter table restaurants add column if not exists email text;

commit;
