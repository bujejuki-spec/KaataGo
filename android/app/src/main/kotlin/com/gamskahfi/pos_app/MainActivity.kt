package com.gamskahfi.pos_app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Jembatan ke [UnduhanService].
///
/// Perintahnya dikirim sebagai Intent — mulai, jeda, lanjut, batal —
/// dan keadaannya ditanyakan, bukan disiarkan: layanannya hidup lebih
/// lama daripada mesin Flutter yang menanyakan, dan siaran yang tidak
/// ada penerimanya hilang begitu saja.
class MainActivity : FlutterActivity() {
    private val saluran = "kaatago/unduhan"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, saluran)
            .setMethodCallHandler { panggilan, hasil ->
                when (panggilan.method) {
                    "mulai", "lanjut" -> {
                        val url = panggilan.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            hasil.error("url_kosong", "Tautannya kosong.", null)
                            return@setMethodCallHandler
                        }
                        val niat = Intent(this, UnduhanService::class.java)
                            .setAction(
                                if (panggilan.method == "mulai")
                                    UnduhanService.AKSI_MULAI
                                else UnduhanService.AKSI_LANJUT)
                            .putExtra("url", url)
                            .putExtra("nama",
                                panggilan.argument<String>("nama")
                                    ?: "KaataGo-update.apk")

                        // Sejak Android 8 layanan latar tidak bisa
                        // dimulai dengan startService saat aplikasinya
                        // tidak di depan. startForegroundService
                        // menjanjikan notifikasinya menyusul — dan
                        // layanannya memang memasangnya lebih dulu.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(niat)
                        } else {
                            startService(niat)
                        }
                        hasil.success(true)
                    }

                    "jeda", "batal" -> {
                        val niat = Intent(this, UnduhanService::class.java)
                            .setAction(
                                if (panggilan.method == "jeda")
                                    UnduhanService.AKSI_JEDA
                                else UnduhanService.AKSI_BATAL)
                        startService(niat)
                        hasil.success(true)
                    }

                    "status" -> hasil.success(mapOf(
                        "keadaan" to UnduhanService.keadaan,
                        "turun" to UnduhanService.turun,
                        // -1 berarti servernya tidak memberitahu panjang
                        // berkasnya. Diteruskan apa adanya; yang di atas
                        // yang memutuskan artinya.
                        "total" to UnduhanService.total,
                        "berkas" to UnduhanService.berkas,
                        "galat" to UnduhanService.pesanGalat))

                    else -> hasil.notImplemented()
                }
            }
    }
}
