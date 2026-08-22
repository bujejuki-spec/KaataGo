-- KaataGo — bagian 54 untuk 2.12.0.
-- Jalankan SETELAH bagian 52 (product_badges_reviews).
-- Aman diulang.

-- KaataGo — penilaian menu menempel pada pesanannya, bukan pada menunya.
--
-- Jalankan SETELAH product_badges_reviews.sql. Aman diulang.
--
-- Semula satu orang hanya boleh menilai sebuah menu satu kali. Terdengar
-- benar — sampai orang yang sama memesan nasi goreng untuk kedua
-- kalinya, membuka formulirnya, dan menemukan bintang lima dari bulan
-- lalu sudah terisi di sana. Yang mau bilang "kali ini keasinan" tidak
-- punya tempat untuk mengatakannya, dan yang membaca ulasannya tidak
-- pernah tahu menunya sudah berubah.
--
-- Satu pesanan satu penilaian. Yang memesan sepuluh kali punya sepuluh
-- kesempatan bicara, dan tiap-tiapnya menilai masakan hari itu saja.

begin;

alter table product_reviews
  add column if not exists order_id uuid references orders (id) on delete cascade;

-- Kunci lamanya dilepas. Selama ia masih ada, pesanan kedua atas menu
-- yang sama akan ditolak basis data — persis keluhan yang mau
-- diperbaiki.
alter table product_reviews
  drop constraint if exists product_reviews_product_id_customer_email_key;

-- Penggantinya memakai indeks, bukan constraint, karena `order_id` boleh
-- kosong pada baris lama. Di dalam unique constraint, dua NULL dianggap
-- berbeda — dan itu berarti baris lama bisa berlipat ganda tanpa
-- ketahuan. `coalesce` menutup celah itu: yang tanpa pesanan tetap
-- dibatasi satu per menu per orang, seperti aturan lama yang memang
-- berlaku saat baris itu ditulis.
create unique index if not exists product_reviews_per_order
  on product_reviews (
    coalesce(order_id::text, ''), product_id, customer_email);

create index if not exists product_reviews_order_idx
  on product_reviews (order_id);

-- Aturan menulisnya ikut menyempit: bukan lagi "pernah memesan menu ini
-- di suatu tempat", melainkan "menu ini ada di pesanan ITU, dan pesanan
-- itu miliknya, dan sudah lunas".
--
-- Tanpa penyempitan ini, satu pesanan lunas berisi nasi goreng sudah
-- cukup untuk menulis penilaian sebanyak-banyaknya atas nama pesanan
-- lain mana pun.
drop policy if exists "product_reviews: own write" on product_reviews;
create policy "product_reviews: own write" on product_reviews
  for all
  using (customer_email = auth.jwt() ->> 'email')
  with check (
    customer_email = auth.jwt() ->> 'email'
    and exists (
      select 1
      from orders o
      where o.customer_label = auth.jwt() ->> 'email'
        and o.payment_status = 'paid'
        and o.items @> jsonb_build_array(
              jsonb_build_object('productId', product_reviews.product_id))
        -- Baris lama tanpa order_id tetap boleh disunting pemiliknya.
        and (product_reviews.order_id is null
             or o.id = product_reviews.order_id)
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   -- Penilaian yang sudah masuk, berikut pesanannya:
--   select r.created_at, r.customer_email, p.name, r.rating, r.comment,
--          r.order_id
--   from product_reviews r
--   join products p on p.id = r.product_id
--   order by r.created_at desc limit 20;
--
--   -- Ringkasan yang dibaca kartu menu:
--   select * from product_stats('<resto_id>');
