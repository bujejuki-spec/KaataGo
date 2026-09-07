package com.gamskahfi.pos_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/// Mengunduh APK di layanan latar milik aplikasi sendiri.
///
/// DownloadManager sempat dipakai dan dilepas lagi. Ia memang bertahan
/// saat layar dikunci, tapi ia tidak bisa dijeda — dan menjeda unduhan
/// 86 MB di tengah jalan adalah hal yang benar-benar dipakai orang di
/// tempat yang sinyalnya mahal.
///
/// Yang tidak berubah dan tidak bisa diubah siapa pun: force-stop
/// membunuh seluruh milik aplikasinya, termasuk layanan ini. Di banyak
/// HP, menggeser aplikasi dari daftar aplikasi terakhir memang berarti
/// force-stop. Yang bisa dijanjikan cuma sampai batas itu — layar
/// terkunci, pindah aplikasi, dan aplikasi yang ditutup biasa.
class UnduhanService : Service() {

    companion object {
        const val AKSI_MULAI = "mulai"
        const val AKSI_JEDA = "jeda"
        const val AKSI_LANJUT = "lanjut"
        const val AKSI_BATAL = "batal"

        private const val SALURAN = "unduhan_pembaruan"
        private const val ID_NOTIFIKASI = 4801

        // Keadaan dibaca sisi Dart lewat MethodChannel. Ditaruh di
        // companion, bukan dikirim lewat siaran: layanan ini hidup lebih
        // lama daripada mesin Flutter yang menanyakannya, dan siaran
        // yang tidak ada penerimanya hilang begitu saja.
        @Volatile var keadaan: String = "kosong"
        @Volatile var turun: Long = 0
        @Volatile var total: Long = -1
        @Volatile var berkas: String? = null
        @Volatile var pesanGalat: String? = null

        @Volatile private var mintaJeda = false
        @Volatile private var mintaBatal = false
    }

    private var pekerja: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            AKSI_JEDA -> {
                mintaJeda = true
                return START_STICKY
            }
            AKSI_BATAL -> {
                mintaBatal = true
                return START_STICKY
            }
            AKSI_MULAI, AKSI_LANJUT -> {
                val url = intent.getStringExtra("url") ?: return START_NOT_STICKY
                val nama = intent.getStringExtra("nama") ?: "KaataGo-update.apk"
                // Memulai dari nol berarti membuang berkas separuh yang
                // ada; melanjutkan justru bersandar padanya.
                mulai(url, nama, ulangDariNol = intent.action == AKSI_MULAI)
            }
        }
        return START_STICKY
    }

    private fun mulai(url: String, nama: String, ulangDariNol: Boolean) {
        if (pekerja?.isAlive == true) return

        mintaJeda = false
        mintaBatal = false
        keadaan = "berjalan"
        pesanGalat = null

        buatSaluran()
        // Notifikasinya dipasang sebelum apa pun yang lain. Layanan
        // latar yang tidak memanggil ini dalam beberapa detik dimatikan
        // Android beserta unduhannya.
        startForeground(ID_NOTIFIKASI, bangunNotifikasi(0, "Menyiapkan…"))

        pekerja = thread(start = true) {
            val file = File(getExternalFilesDir(null), nama)
            if (ulangDariNol && file.exists()) file.delete()

            var sudah = if (file.exists()) file.length() else 0L
            turun = sudah

            var koneksi: HttpURLConnection? = null
            var keluaran: RandomAccessFile? = null
            try {
                koneksi = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 30_000
                    readTimeout = 30_000
                    if (sudah > 0) setRequestProperty("Range", "bytes=$sudah-")
                }
                koneksi.connect()

                val kode = koneksi.responseCode
                // Server yang menolak melanjutkan menjawab 200 berisi
                // seluruh berkas, bukan 206 berisi sisanya. Menambahkannya
                // ke belakang berkas separuh menghasilkan APK dobel yang
                // gagal dipasang tanpa sebab yang jelas.
                if (sudah > 0 && kode == HttpURLConnection.HTTP_OK) {
                    file.delete()
                    sudah = 0
                    turun = 0
                }
                if (kode != HttpURLConnection.HTTP_OK &&
                    kode != HttpURLConnection.HTTP_PARTIAL) {
                    gagal(if (kode == 404)
                        "Berkas pembaruannya tidak ditemukan di server."
                    else
                        "Unduhan gagal — server sedang tidak bisa melayani (kode $kode).")
                    return@thread
                }

                val panjang = koneksi.contentLengthLong
                total = if (panjang > 0) sudah + panjang else -1

                // Salinan val-nya yang dipakai di dalam lambda: Kotlin
                // tidak bisa menjamin sebuah var yang tertangkap masih
                // bukan null di sana, dan var-nya sendiri tetap ada
                // hanya untuk penutupan di finally.
                val tulis = RandomAccessFile(file, "rw")
                keluaran = tulis
                tulis.seek(sudah)

                koneksi.inputStream.use { masuk ->
                    val bak = ByteArray(64 * 1024)
                    var persenTerakhir = -1
                    while (true) {
                        if (mintaBatal) {
                            tulis.close()
                            keluaran = null
                            file.delete()
                            turun = 0
                            keadaan = "dibatalkan"
                            selesaikan()
                            return@thread
                        }
                        if (mintaJeda) {
                            // Berkasnya sengaja TIDAK dihapus. Itu
                            // seluruh gunanya jeda.
                            tulis.close()
                            keluaran = null
                            keadaan = "dijeda"
                            perbaruiNotifikasi(persen(), "Dijeda")
                            stopForeground(STOP_FOREGROUND_DETACH)
                            stopSelf()
                            return@thread
                        }

                        val n = masuk.read(bak)
                        if (n < 0) break
                        tulis.write(bak, 0, n)
                        sudah += n
                        turun = sudah

                        val p = persen()
                        if (p != persenTerakhir) {
                            persenTerakhir = p
                            perbaruiNotifikasi(p, "Mengunduh pembaruan")
                        }
                    }
                }
                tulis.close()
                keluaran = null

                berkas = file.absolutePath
                keadaan = "selesai"
                notifikasiSelesai(file)
                stopForeground(STOP_FOREGROUND_DETACH)
                stopSelf()
            } catch (e: Exception) {
                if (mintaBatal) {
                    keadaan = "dibatalkan"
                    selesaikan()
                } else {
                    gagal("Unduhan gagal karena masalah koneksi.")
                }
            } finally {
                // Ditutup di sini juga: jalur galat melompati penutupan
                // di atas, dan berkas yang tetap terbuka menumpuk
                // deskriptor tiap kali unduhannya diulang.
                try { keluaran?.close() } catch (_: Exception) {}
                koneksi?.disconnect()
            }
        }
    }

    private fun persen(): Int =
        if (total > 0) ((turun * 100) / total).toInt() else 0

    private fun gagal(pesan: String) {
        keadaan = "gagal"
        pesanGalat = pesan
        selesaikan()
    }

    private fun selesaikan() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buatSaluran() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val saluran = NotificationChannel(
            SALURAN, "Unduhan pembaruan", NotificationManager.IMPORTANCE_LOW)
        saluran.setShowBadge(false)
        (getSystemService(NotificationManager::class.java))
            .createNotificationChannel(saluran)
    }

    private fun bangunNotifikasi(persen: Int, judul: String): Notification =
        NotificationCompat.Builder(this, SALURAN)
            .setContentTitle(judul)
            .setContentText(if (total > 0) "$persen%" else "Mengunduh…")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, persen, total <= 0)
            .build()

    private fun perbaruiNotifikasi(persen: Int, judul: String) {
        (getSystemService(NotificationManager::class.java))
            .notify(ID_NOTIFIKASI, bangunNotifikasi(persen, judul))
    }

    /// Notifikasi selesai yang mengetuknya langsung membuka pemasang.
    ///
    /// Android melarang aplikasi latar membuka layar sendiri, jadi saat
    /// unduhannya kelar sementara HP-nya terkunci, ketukan inilah
    /// satu-satunya jalan yang tersisa menuju pemasangnya.
    private fun notifikasiSelesai(file: File) {
        val uri = FileProvider.getUriForFile(
            this, "$packageName.unduhan", file)
        val niat = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val tertunda = PendingIntent.getActivity(
            this, 0, niat,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notifikasi = NotificationCompat.Builder(this, SALURAN)
            .setContentTitle("Pembaruan siap dipasang")
            .setContentText("Ketuk untuk memasang KaataGo versi terbaru")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(tertunda)
            .setAutoCancel(true)
            .build()

        (getSystemService(NotificationManager::class.java))
            .notify(ID_NOTIFIKASI, notifikasi)
    }
}
