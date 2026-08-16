#!/usr/bin/env bash
#
# KaataGo — menggabung migrasi yang tertunda jadi satu berkas.
#
# Dihasilkan, bukan diketik: berkas gabungan yang disunting sendiri akan
# berbeda dari berkas aslinya pada perubahan berikutnya, dan yang
# ketinggalan justru berkas yang benar-benar dijalankan orang.
#
# Tiap berkas asal sudah membawa begin/commit-nya sendiri, dan itu
# sengaja dipertahankan. Membungkus semuanya dalam satu transaksi raksasa
# berarti satu galat di bagian keenam membatalkan lima bagian yang sudah
# benar — persis yang terjadi waktu perbaikan arah jurnal ikut hangus
# oleh galat batasan di berkas yang sama.
#
# Pakai:
#   scripts/gabung_sql.sh

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/supabase"
OUT="$DIR/JALANKAN-INI.sql"

# Urutannya penting: yang belakangan bergantung pada tabel yang dibuat
# yang sebelumnya.
FILES=(
  employee_surrogate_key.sql
  promo_banner.sql
  rilis_setor_petty_inbox.sql
  customer_cash_payment.sql
  push_notifications.sql
  announcement_categories.sql
  fix_device_tokens_rls.sql
  push_trigger_pg_net.sql
  payment_gateway.sql
  gateway_settlement.sql
  resto_payment_accounts.sql
  counter_charge.sql
  announcement_push.sql
  cash_payment_expiry.sql
  level_groups.sql
  resto_order_types.sql
  product_out_of_stock.sql
  discounts.sql
  promo_banner_period.sql
  default_gl_accounts.sql
  gateway_account_super_admin.sql
  announcement_audience.sql
  kasir_journal_read.sql
  cancel_order.sql
  settled_at_counter.sql
)

{
  cat <<'HEADER'
-- ═══════════════════════════════════════════════════════════════════
-- KaataGo — seluruh migrasi yang tertunda, dalam satu berkas.
--
-- DIHASILKAN OLEH scripts/gabung_sql.sh — jangan disunting di sini.
-- Suntingannya akan hilang saat berkas ini dibuat ulang; sunting berkas
-- aslinya di supabase/ lalu jalankan skripnya lagi.
--
-- Cara pakai: salin seluruh isinya ke SQL Editor Supabase, jalankan.
-- Aman dijalankan berulang kali.
--
-- Tiap bagian punya begin/commit sendiri. Artinya kalau ada satu bagian
-- yang gagal, bagian sebelumnya tetap tersimpan — yang perlu diulang
-- hanya bagian yang gagal itu dan sesudahnya. Perhatikan pesan galat
-- Supabase: nomor bagiannya tertulis di komentar pemisah di bawah.
-- ═══════════════════════════════════════════════════════════════════

HEADER

  n=0
  for f in "${FILES[@]}"; do
    n=$((n + 1))
    printf -- '\n\n-- ═══════════════════════════════════════════════════════════════════\n'
    printf -- '-- BAGIAN %d dari %d — %s\n' "$n" "${#FILES[@]}" "$f"
    printf -- '-- ═══════════════════════════════════════════════════════════════════\n\n'
    cat "$DIR/$f"
  done
} > "$OUT"

printf '\ndibuat: %s (%s baris, %s bagian)\n' \
  "$OUT" "$(wc -l < "$OUT" | tr -d ' ')" "${#FILES[@]}"
