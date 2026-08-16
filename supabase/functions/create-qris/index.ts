// KaataGo — membuat tagihan QRIS di Xendit.
//
// Dipanggil aplikasi pelanggan sambil menyebut nomor pesanannya saja.
// Nominalnya **tidak** ikut dikirim: fungsi ini membacanya sendiri dari
// pesanan di database. Nominal yang datang dari HP bisa diubah siapa pun
// yang mau membayar seratus ribu dengan seribu rupiah.
//
// Deploy:
//   supabase functions deploy create-qris --project-ref xizpwtycczigjhzxegen
//
// Secret yang dibutuhkan:
//   XENDIT_SECRET_KEY   kunci rahasia Xendit (xnd_development_… saat uji)
//
// Kunci itu tidak boleh pernah ada di dalam APK. Siapa pun yang
// memegangnya bisa membuat tagihan, menarik dana, dan membaca seluruh
// riwayat transaksi merchant.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Berlaku 30 menit. Cukup panjang untuk orang yang masih memilih menu
// atau kehabisan pulsa data sebentar, cukup pendek supaya QR yang
// terlanjur difoto tidak bisa dibayar berjam-jam kemudian.
const EXPIRY_MINUTES = 30;

interface OrderRow {
  id: string;
  resto_id: string | null;
  total: number;
  payment_status: string;
  payment_method: string | null;
}

Deno.serve(async (req) => {
  try {
    const { order_id, simulate } = await req.json();
    if (!order_id) {
      return json({ error: "order_id wajib diisi" }, 400);
    }

    if (simulate === true) return await simulatePayment(order_id);

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select("id, resto_id, total, payment_status, payment_method")
      .eq("id", order_id)
      .maybeSingle<OrderRow>();

    if (orderError) return json({ error: orderError.message }, 500);
    if (!order) return json({ error: "pesanan tidak ditemukan" }, 404);
    if (order.payment_status === "paid") {
      return json({ error: "pesanan ini sudah dibayar" }, 409);
    }

    // Tagihan yang masih hidup dipakai ulang, bukan dibuatkan yang baru.
    //
    // Pelanggan yang menutup layarnya lalu kembali akan memanggil fungsi
    // ini lagi. Kalau tiap panggilan membuat QR baru, satu pesanan bisa
    // punya lima QR aktif sekaligus — dan kalau dua di antaranya
    // terbayar, yang kedua adalah uang pelanggan yang harus
    // dikembalikan.
    const { data: existing } = await admin
      .from("payment_charges")
      .select("reference_id, qr_string, amount, expires_at")
      .eq("order_id", order.id)
      .eq("status", "pending")
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const secret = Deno.env.get("XENDIT_SECRET_KEY");
    if (!secret) return json({ error: "XENDIT_SECRET_KEY belum diset" }, 500);

    // Mode uji ditentukan server, bukan aplikasi.
    //
    // Aplikasi tidak punya cara mengetahuinya sendiri, dan menitipkannya
    // ke penanda saat build berarti mengandalkan seseorang ingat
    // mematikannya sebelum rilis — yang selalu gagal tepat pada rilis
    // yang paling sibuk. Dengan cara ini, mengganti kunci ke produksi
    // sudah cukup untuk melenyapkan seluruh perkakas ujinya.
    const testMode = secret.startsWith("xnd_development_");

    if (existing?.qr_string) {
      return json({
        qr_string: existing.qr_string,
        amount: existing.amount,
        expires_at: existing.expires_at,
        reused: true,
        test_mode: testMode,
      });
    }

    // Pengenal kita sendiri, bukan nomor pesanannya mentah-mentah: satu
    // pesanan bisa butuh QR kedua setelah yang pertama kedaluwarsa, dan
    // keduanya harus bisa dibedakan saat webhooknya datang.
    const referenceId = `kaatago-${order.id}-${Date.now()}`;
    const expiresAt = new Date(Date.now() + EXPIRY_MINUTES * 60_000);

    const res = await fetch("https://api.xendit.co/qr_codes", {
      method: "POST",
      headers: {
        // Xendit memakai Basic auth dengan kunci rahasia sebagai
        // username dan kata sandi kosong.
        Authorization: `Basic ${btoa(secret + ":")}`,
        "Content-Type": "application/json",
        "api-version": "2022-07-31",
      },
      body: JSON.stringify({
        reference_id: referenceId,
        type: "DYNAMIC",
        currency: "IDR",
        amount: order.total,
        expires_at: expiresAt.toISOString(),
      }),
    });

    const body = await res.json();
    if (!res.ok) {
      // Dicatat sebagai gagal, bukan dibiarkan menghilang: pelanggan
      // yang QR-nya tidak muncul akan bertanya, dan jawabannya harus ada
      // di suatu tempat.
      await admin.from("payment_charges").insert({
        order_id: order.id,
        resto_id: order.resto_id,
        reference_id: referenceId,
        amount: order.total,
        status: "failed",
        raw: body,
      });
      return json({ error: `Xendit menolak: ${JSON.stringify(body)}` }, 502);
    }

    await admin.from("payment_charges").insert({
      order_id: order.id,
      resto_id: order.resto_id,
      reference_id: referenceId,
      provider_charge_id: body.id ?? null,
      qr_string: body.qr_string ?? null,
      amount: order.total,
      status: "pending",
      expires_at: expiresAt.toISOString(),
      raw: body,
    });

    return json({
      qr_string: body.qr_string,
      amount: order.total,
      expires_at: expiresAt.toISOString(),
      reused: false,
      test_mode: testMode,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

/// Memalsukan pembayaran, hanya untuk pengujian.
///
/// Dashboard Xendit tidak selalu menyediakan tombol simulasi, dan
/// jalan satu-satunya lewat API — yang berarti menyalin secret key ke
/// terminal, lalu menebak QR mana yang dimaksud di antara sekian
/// banyak. Kuncinya sudah ada di sini, dan nomor pesanannya sudah
/// diketahui, jadi keduanya tidak perlu diulang di tempat lain.
///
/// Ditolak mentah-mentah kalau kunci yang terpasang bukan kunci Test.
/// Fungsi yang bisa menyatakan sebuah tagihan terbayar tanpa uang
/// benar-benar berpindah tidak boleh ada di lingkungan produksi, dan
/// penjagaan yang mengandalkan "nanti diingat untuk dihapus" akan
/// gagal pada rilis yang paling sibuk.
async function simulatePayment(orderId: string) {
  const secret = Deno.env.get("XENDIT_SECRET_KEY") ?? "";
  if (!secret.startsWith("xnd_development_")) {
    return json({ error: "simulasi hanya untuk kunci Test" }, 403);
  }

  const { data: charge } = await admin
    .from("payment_charges")
    .select("provider_charge_id, reference_id, amount, status")
    .eq("order_id", orderId)
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!charge?.provider_charge_id) {
    return json({ error: "tidak ada tagihan menunggu untuk pesanan ini" }, 404);
  }

  const res = await fetch(
    `https://api.xendit.co/qr_codes/${charge.provider_charge_id}/payments/simulate`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(secret + ":")}`,
        "Content-Type": "application/json",
        "api-version": "2022-07-31",
      },
      body: JSON.stringify({ amount: charge.amount }),
    },
  );

  const body = await res.text();
  return json({
    simulated: res.ok,
    status: res.status,
    reference_id: charge.reference_id,
    response: body.slice(0, 400),
  }, res.ok ? 200 : 502);
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
