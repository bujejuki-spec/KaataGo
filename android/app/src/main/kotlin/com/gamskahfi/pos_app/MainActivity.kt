package com.gamskahfi.pos_app

import android.app.DownloadManager
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Unduhan APK diserahkan ke DownloadManager milik Android.
///
/// Sebelumnya berkasnya diunduh di dalam proses aplikasi sendiri. Itu
/// berjalan baik selama layarnya dilihat, dan berhenti begitu tidak:
/// aplikasi yang ditutup dari daftar aplikasi terakhir dimatikan
/// prosesnya, dan HP yang terkunci membekukan jaringan aplikasi latar.
/// Yang terjadi pada orangnya selalu sama — 86 MB yang batal di tengah
/// jalan, tanpa satu pun pesan yang menjelaskan kenapa.
///
/// DownloadManager berjalan di proses sistem, bukan proses aplikasi ini.
/// Ia bertahan saat aplikasinya ditutup, saat layarnya dikunci, dan
/// menyambung sendiri saat sinyalnya putus lalu kembali.
///
/// Yang hilang: tidak ada cara menjeda. DownloadManager tidak
/// menyediakannya, dan menirunya berarti membangun ulang seluruh
/// isinya. Ditukar dengan sadar — jeda dulu ada supaya unduhan tidak
/// hangus saat orangnya pergi, dan sekarang ia memang tidak hangus.
class MainActivity : FlutterActivity() {
    private val saluran = "kaatago/unduhan"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, saluran)
            .setMethodCallHandler { panggilan, hasil ->
                val manajer =
                    getSystemService(DOWNLOAD_SERVICE) as DownloadManager

                when (panggilan.method) {
                    "mulai" -> {
                        val url = panggilan.argument<String>("url")
                        val nama = panggilan.argument<String>("nama")
                            ?: "KaataGo-update.apk"
                        if (url.isNullOrBlank()) {
                            hasil.error("url_kosong", "Tautannya kosong.", null)
                            return@setMethodCallHandler
                        }

                        // Folder milik aplikasi di penyimpanan luar: tidak
                        // butuh izin apa pun, tidak menumpuk di folder
                        // Unduhan bersama, dan ikut terhapus saat
                        // aplikasinya dicopot.
                        val permintaan = DownloadManager.Request(Uri.parse(url))
                            .setTitle("Pembaruan KaataGo")
                            .setDescription("Mengunduh versi terbaru")
                            .setMimeType(
                                "application/vnd.android.package-archive")
                            .setNotificationVisibility(
                                DownloadManager.Request
                                    .VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            .setAllowedOverMetered(true)
                            .setAllowedOverRoaming(true)
                            .setDestinationInExternalFilesDir(
                                this, null, nama)

                        hasil.success(manajer.enqueue(permintaan))
                    }

                    // Kemajuannya ditanyakan, bukan dikirim: DownloadManager
                    // tidak menyiarkan kemajuan, hanya penyelesaian.
                    "status" -> {
                        val id = (panggilan.argument<Number>("id"))?.toLong()
                        if (id == null) {
                            hasil.error("id_kosong", "Id unduhannya kosong.", null)
                            return@setMethodCallHandler
                        }

                        val kursor: Cursor? = manajer.query(
                            DownloadManager.Query().setFilterById(id))
                        kursor.use { c ->
                            if (c == null || !c.moveToFirst()) {
                                // Barisnya hilang — dihapus orangnya lewat
                                // aplikasi Unduhan, atau dibersihkan sistem.
                                hasil.success(mapOf("keadaan" to "hilang"))
                                return@setMethodCallHandler
                            }

                            val status = c.getInt(c.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_STATUS))
                            val turun = c.getLong(c.getColumnIndexOrThrow(
                                DownloadManager
                                    .COLUMN_BYTES_DOWNLOADED_SO_FAR))
                            val total = c.getLong(c.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                            val alasan = c.getInt(c.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_REASON))

                            val keadaan = when (status) {
                                DownloadManager.STATUS_SUCCESSFUL -> "selesai"
                                DownloadManager.STATUS_FAILED -> "gagal"
                                DownloadManager.STATUS_PAUSED -> "tertunda"
                                DownloadManager.STATUS_PENDING -> "tertunda"
                                else -> "berjalan"
                            }

                            hasil.success(mapOf(
                                "keadaan" to keadaan,
                                "turun" to turun,
                                // -1 berarti servernya tidak memberitahu
                                // panjang berkasnya. Diteruskan apa adanya;
                                // yang di atas yang memutuskan artinya.
                                "total" to total,
                                "alasan" to alasan))
                        }
                    }

                    "batal" -> {
                        val id = (panggilan.argument<Number>("id"))?.toLong()
                        if (id != null) manajer.remove(id)
                        hasil.success(null)
                    }

                    // Membuka layar pemasang atas berkas yang sudah turun.
                    //
                    // Uri-nya diminta dari DownloadManager, bukan disusun
                    // dari jalur berkas: sejak Android 7 sebuah file://
                    // yang dilempar ke aplikasi lain melempar
                    // FileUriExposedException, dan yang terlihat orangnya
                    // cuma aplikasi yang berhenti sendiri.
                    "pasang" -> {
                        val id = (panggilan.argument<Number>("id"))?.toLong()
                        if (id == null) {
                            hasil.error("id_kosong", "Id unduhannya kosong.", null)
                            return@setMethodCallHandler
                        }
                        val uri = manajer.getUriForDownloadedFile(id)
                        if (uri == null) {
                            hasil.success(false)
                            return@setMethodCallHandler
                        }
                        val niat = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri,
                                "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        try {
                            startActivity(niat)
                            hasil.success(true)
                        } catch (e: Exception) {
                            // Android melarang aplikasi latar membuka layar
                            // sendiri. Bukan kerusakan — yang di atas
                            // menjawabnya dengan notifikasi.
                            hasil.success(false)
                        }
                    }

                    else -> hasil.notImplemented()
                }
            }
    }
}
