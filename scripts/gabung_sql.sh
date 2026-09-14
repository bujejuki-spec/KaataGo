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
  discount_min_qty.sql
  discount_product_rules.sql
  billing.sql
  billing_va.sql
  platform_finance.sql
  resto_soft_delete.sql
  billing_discount_apply.sql
  billing_journal_gross.sql
  gl_discount_backfill.sql
  platform_gl_renumber.sql
  product_toppings.sql
  vouchers.sql
  voucher_payouts.sql
  voucher_announcement.sql
  voucher_manage.sql
  market_report.sql
  billing_due_day.sql
  balance_topup.sql
  voucher_new_customer.sql
  qris_receipt_fields.sql
  order_number.sql
  customer_display.sql
  resto_facilities.sql
  merchant_reviews.sql
  review_prompt.sql
  order_cancel_kitchen.sql
  product_badges_reviews.sql
  cashier_shift.sql
  product_review_per_order.sql
  cash_variance.sql
  cash_variance_lebih.sql
  backfill_selisih_lebih.sql
  buka_shift_terkunci.sql
  perbaiki_deskripsi_jurnal.sql
  stok_terkunci.sql
  foto_menu_storage.sql
  saldo_cash_pembanding.sql
  merchant_email.sql
  tagihan_ikut_tanggal.sql
  qris_hangus.sql
  qris_statis.sql
  tutup_buku_harian.sql
  rekening_perusahaan.sql
  setor_dan_pickup.sql
  mutasi_bank.sql
  cara_tagih.sql
  rekening_owner.sql
  shift_privasi.sql
  terima_cash_pickup.sql
  uam_menu.sql
  layar_pelanggan_rinci.sql
  stok_lepas_10_menit.sql
  rekening_kaatago_terbaca.sql
  jurnal_cash_pickup_benar.sql
  saldo_perusahaan.sql
  jurnal_bank_terjadwal.sql
  backfill_saldo_bank.sql
  jurnal_selisih_ke_bank.sql
  setoran_ke_saldo_bank.sql
  tutup_shift_sendiri.sql
  saldo_awal.sql
  periksa_pembukuan.sql
  layar_pelanggan_rincian_biaya.sql
  merchant_report.sql
  laporan_grafik.sql
  absensi_payroll.sql
  paket_langganan.sql
  perbaikan_hak_fungsi.sql
  paket_trial_rapi.sql
  paket_publik.sql
  wajah_tidak_kembar.sql
  wajah_geometri.sql
  wajah_facenet.sql
  absensi_baca_super_admin.sql
  shift_opening_check.sql
  support_tickets.sql
  support_push.sql
  support_auto_reply.sql
  support_chat_rules.sql
  support_pesan_kembar.sql
  support_push_wording.sql
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
