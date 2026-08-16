// KaataGo — penerima kabar pembayaran dari Xendit.
//
// Inilah satu-satunya hal yang boleh menyatakan sebuah pesanan lunas
// lewat QRIS. Tombol di HP pelanggan tidak, dan tidak akan pernah:
// apa pun yang bisa ditekan orang yang belum membayar bukan bukti
// pembayaran.
//
// Deploy:
//   supabase functions deploy xendit-webhook \
//     --project-ref xizpwtycczigjhzxegen --no-verify-jwt
//
// --no-verify-jwt wajib: pemanggilnya server Xendit, yang tidak punya
// sesi pengguna. Yang menjaga pintunya adalah token callback di bawah.
//
// Secret yang dibutuhkan:
//   XENDIT_CALLBACK_TOKEN   dari Dashboard Xendit → Settings → Callbacks
//
// Daftarkan URL ini di Dashboard Xendit untuk kejadian "QR Code payment":
//   https://xizpwtycczigjhzxegen.supabase.co/functions/v1/xendit-webhook

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  // Token callback diperiksa lebih dulu, sebelum apa pun dibaca dari
  // badan permintaannya. URL fungsi ini terbuka untuk umum — tanpa
  // pemeriksaan ini, siapa pun bisa mengarang kabar "sudah lunas" untuk
  // pesanan mana pun.
  const expected = Deno.env.get("XENDIT_CALLBACK_TOKEN");
  if (!expected) {
    return new Response("XENDIT_CALLBACK_TOKEN belum diset", { status: 500 });
  }
  if (req.headers.get("x-callback-token") !== expected) {
    return new Response("ditolak", { status: 401 });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return new Response("badan permintaan bukan JSON", { status: 400 });
  }

  const data = (payload.data ?? payload) as Record<string, unknown>;
  const referenceId = data.reference_id as string | undefined;
  const status = String(data.status ?? "").toUpperCase();

  if (!referenceId) {
    // Dijawab 200 supaya Xendit berhenti mengulangnya. Kabar yang tidak
    // kita mengerti tidak akan jadi lebih dimengerti pada percobaan
    // kelima.
    return json({ ignored: "tanpa reference_id" });
  }

  // Hanya pembayaran berhasil yang menggerakkan uang. Kejadian lain —
  // kedaluwarsa, dibatalkan — sengaja tidak menyentuh pesanannya:
  // pelanggan yang QR-nya kedaluwarsa masih boleh membayar tunai di
  // kasir, dan pesanannya tidak boleh ikut ditutup.
  if (status !== "SUCCEEDED" && status !== "COMPLETED" && status !== "PAID") {
    await admin.from("payment_charges")
      .update({ raw: payload })
      .eq("reference_id", referenceId);
    return json({ ignored: `status ${status}` });
  }

  const { data: result, error } = await admin.rpc("settle_gateway_payment", {
    p_reference_id: referenceId,
    p_provider_charge_id: (data.qr_id ?? data.id ?? null) as string | null,
    p_raw: payload,
  });

  if (error) {
    // 500 supaya Xendit mengulang. Ini satu-satunya kegagalan yang
    // memang layak diulang: databasenya sedang tidak bisa dihubungi,
    // sementara uangnya sudah benar-benar diterima.
    return json({ error: error.message }, 500);
  }

  return json({ result });
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
