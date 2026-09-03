package com.zerolog.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Environment
import android.provider.MediaStore
import android.content.ContentValues
import android.webkit.MimeTypeMap
import java.io.File
import androidx.core.content.FileProvider
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class FileTransferForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "zerolog_file_transfer"
        const val NOTIFICATION_ID = 9101

        const val ACTION_START =
            "com.zerolog.app.FILE_TRANSFER_START"

        const val ACTION_STOP =
            "com.zerolog.app.FILE_TRANSFER_STOP"

        const val EXTRA_SENDER = "sender"
        const val EXTRA_RECIPIENT = "recipient"
        const val EXTRA_FILE_ID = "fileId"
        const val EXTRA_FILE_NAME = "fileName"
        const val EXTRA_FILE_SIZE = "fileSize"

        private const val TAG = "ZeroLogFile"
        private const val METHOD_CHANNEL =
            "zerolog/background_transfer"

        private const val PREFS =
            "zerolog_background_transfer"
    }

    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "File transfer service created")
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {

        if (intent?.action == ACTION_STOP) {
            stopTransferService()
            return START_NOT_STICKY
        }

        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(
                NOTIFICATION_ID,
                notification
            )
        }

        val sender =
            intent?.getStringExtra(EXTRA_SENDER)
                ?.trim()
                .orEmpty()

        val recipient =
            intent?.getStringExtra(EXTRA_RECIPIENT)
                ?.trim()
                .orEmpty()

        val fileId =
            intent?.getStringExtra(EXTRA_FILE_ID)
                ?.trim()
                .orEmpty()

        val fileName =
            intent?.getStringExtra(EXTRA_FILE_NAME)
                ?.trim()
                .orEmpty()

        val fileSize =
            intent?.getStringExtra(EXTRA_FILE_SIZE)
                ?.trim()
                .orEmpty()

        if (sender.isEmpty() ||
            recipient.isEmpty() ||
            fileId.isEmpty() ||
            (fileSize.toLongOrNull() ?: 0L) <= 0L
        ) {
            Log.e(TAG, "Invalid transfer metadata")
            stopTransferService()
            return START_NOT_STICKY
        }

        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putString(EXTRA_SENDER, sender)
            .putString(EXTRA_RECIPIENT, recipient)
            .putString(EXTRA_FILE_ID, fileId)
            .putString(EXTRA_FILE_NAME, fileName)
            .putString(EXTRA_FILE_SIZE, fileSize)
            .apply()

        startFlutterEngine()

        return START_STICKY
    }

    private fun startFlutterEngine() {
        if (flutterEngine != null) return

        try {
            val loader =
                FlutterInjector.instance().flutterLoader()

            loader.startInitialization(applicationContext)

            loader.ensureInitializationComplete(
                applicationContext,
                null
            )

            val engine =
                FlutterEngine(applicationContext)

            methodChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                METHOD_CHANNEL
            )

            methodChannel?.setMethodCallHandler {
                call,
                result ->
                when (call.method) {

                    "getPendingTransfer" -> {
                        val prefs =
                            getSharedPreferences(
                                PREFS,
                                MODE_PRIVATE
                            )

                        val sender =
                            prefs.getString(
                                EXTRA_SENDER,
                                ""
                            ).orEmpty()

                        val recipient =
                            prefs.getString(
                                EXTRA_RECIPIENT,
                                ""
                            ).orEmpty()

                        val fileId =
                            prefs.getString(
                                EXTRA_FILE_ID,
                                ""
                            ).orEmpty()

                        val fileName =
                            prefs.getString(
                                EXTRA_FILE_NAME,
                                ""
                            ).orEmpty()

                        val fileSize =
                            prefs.getString(
                                EXTRA_FILE_SIZE,
                                ""
                            ).orEmpty()

                        if (sender.isEmpty() ||
                            recipient.isEmpty() ||
                            fileId.isEmpty()
                        ) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "sender" to sender,
                                    "recipient" to recipient,
                                    "fileId" to fileId,
                                    "fileName" to fileName,
                                    "fileSize" to fileSize
                                )
                            )
                        }
                    }

                    "stopService" -> {
                        stopTransferService()
                        result.success(true)
                    }

                    "registerBackgroundReceivedFile" -> {
                        val fileId =
                            call.argument<String>("fileId")
                                ?.trim()
                                .orEmpty()

                        val sourcePath =
                            call.argument<String>("sourcePath")
                                ?.trim()
                                .orEmpty()

                        val fileName =
                            call.argument<String>("fileName")
                                ?.trim()
                                .ifEmpty { "received_file" }
                                ?: "received_file"

                        result.success(
                            if (fileId.isEmpty() || sourcePath.isEmpty()) {
                                null
                            } else {
                                registerBackgroundReceivedFile(
                                    fileId,
                                    sourcePath,
                                    fileName
                                )
                            }
                        )
                    }

                    else -> result.notImplemented()
                }
            }

            flutterEngine = engine

            val entrypoint =
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "zerologBackgroundTransferMain"
                )

            engine.dartExecutor.executeDartEntrypoint(
                entrypoint
            )

            Log.d(
                TAG,
                "Headless FlutterEngine started"
            )
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Headless FlutterEngine start failed",
                e
            )
            stopTransferService()
        }
    }

    private fun registerBackgroundReceivedFile(
        fileId: String,
        sourcePath: String,
        fileName: String
    ): String? {
        if (fileId.isBlank() || sourcePath.isBlank()) return null

        return try {
            val source = File(sourcePath)

            if (!source.exists() || source.length() <= 0L) {
                throw IllegalStateException(
                    "Arka plan alınan dosya bulunamadı."
                )
            }

            val safeName = fileName
                .replace(Regex("[\\r\\n<>]"), "_")
                .trim()
                .ifEmpty { "received_file" }
                .take(255)

            val extension = safeName.substringAfterLast('.', "")
                .trim()
                .lowercase()

            val mimeType = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"

            // Android 10+:
            // Background transfer doğrudan kullanıcı tarafından görülebilen
            // gerçek hedefe yazılır. Fotoğraflar Pictures/ZeroLog,
            // diğer dosyalar Downloads/ZeroLog altında tutulur.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val isImage = extension in setOf(
                    "jpg", "jpeg", "png", "webp", "gif", "heic", "heif"
                )

                val collection =
                    if (isImage) {
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    } else {
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI
                    }

                val relativePath =
                    if (isImage) {
                        "${Environment.DIRECTORY_PICTURES}/ZeroLog"
                    } else {
                        Environment.DIRECTORY_DOWNLOADS
                    }

                val values = ContentValues().apply {
                    put(
                        MediaStore.MediaColumns.DISPLAY_NAME,
                        safeName
                    )
                    put(
                        MediaStore.MediaColumns.MIME_TYPE,
                        mimeType
                    )
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        relativePath
                    )
                    put(
                        MediaStore.MediaColumns.IS_PENDING,
                        1
                    )
                }

                val targetUri = contentResolver.insert(
                    collection,
                    values
                ) ?: throw IllegalStateException(
                    "Arka plan dosyası için MediaStore hedefi oluşturulamadı."
                )

                try {
                    contentResolver.openOutputStream(targetUri)
                        ?.use { output ->
                            source.inputStream().use { input ->
                                val buffer = ByteArray(64 * 1024)

                                while (true) {
                                    val count = input.read(buffer)
                                    if (count <= 0) break
                                    output.write(buffer, 0, count)
                                }
                            }

                            output.flush()
                        }
                        ?: throw IllegalStateException(
                            "Arka plan dosyası için çıktı akışı açılamadı."
                        )

                    val expectedSize = source.length()

                    val copiedSize =
                        contentResolver.openFileDescriptor(
                            targetUri,
                            "r"
                        )?.use { it.statSize }
                            ?: -1L

                    if (copiedSize != expectedSize) {
                        throw IllegalStateException(
                            "Arka plan dosya boyutu doğrulanamadı: " +
                                "$copiedSize / $expectedSize"
                        )
                    }

                    val publishValues = ContentValues().apply {
                        put(
                            MediaStore.MediaColumns.IS_PENDING,
                            0
                        )
                    }

                    contentResolver.update(
                        targetUri,
                        publishValues,
                        null,
                        null
                    )

                    getSharedPreferences(
                        "zerolog_received_files",
                        MODE_PRIVATE
                    )
                        .edit()
                        .putString(
                            "uri_$fileId",
                            targetUri.toString()
                        )
                        .apply()

                    source.delete()

                    targetUri.toString()
                } catch (e: Exception) {
                    try {
                        contentResolver.delete(
                            targetUri,
                            null,
                            null
                        )
                    } catch (_: Exception) {}

                    throw e
                }
            } else {
                // Android 9 ve altı için izin gerektirmeyen güvenli fallback.
                // Bu sürümlerde FileProvider URI ile ZeroLog içinden erişim
                // korunur.
                val receivedDir = File(
                    filesDir,
                    "received_files"
                )

                if (!receivedDir.exists() && !receivedDir.mkdirs()) {
                    throw IllegalStateException(
                        "ZeroLog alınan dosya klasörü oluşturulamadı."
                    )
                }

                val safeId = fileId.replace(
                    Regex("[^A-Za-z0-9._-]"),
                    "_"
                )

                val target = File(receivedDir, safeId)
                val tempTarget = File(
                    receivedDir,
                    "$safeId.bgpart"
                )

                if (tempTarget.exists()) {
                    tempTarget.delete()
                }

                source.inputStream().use { input ->
                    tempTarget.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)

                        while (true) {
                            val count = input.read(buffer)
                            if (count <= 0) break
                            output.write(buffer, 0, count)
                        }

                        output.flush()
                    }
                }

                if (!tempTarget.exists() ||
                    tempTarget.length() != source.length()
                ) {
                    tempTarget.delete()

                    throw IllegalStateException(
                        "Arka plan dosya kopyası doğrulanamadı."
                    )
                }

                if (target.exists()) {
                    target.delete()
                }

                if (!tempTarget.renameTo(target)) {
                    tempTarget.delete()

                    throw IllegalStateException(
                        "Arka plan dosyası kalıcı konuma taşınamadı."
                    )
                }

                val uri = FileProvider.getUriForFile(
                    applicationContext,
                    "$packageName.fileprovider",
                    target
                )

                getSharedPreferences(
                    "zerolog_received_files",
                    MODE_PRIVATE
                )
                    .edit()
                    .putString(
                        "uri_$fileId",
                        uri.toString()
                    )
                    .apply()

                source.delete()

                target.absolutePath
            }
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Background received file registration failed",
                e
            )

            null
        }
    }

    private fun stopTransferService() {
        Log.d(TAG, "Stopping file transfer service")

        try {
            methodChannel?.setMethodCallHandler(null)
        } catch (_: Exception) {
        }

        methodChannel = null

        try {
            flutterEngine?.destroy()
        } catch (_: Exception) {
        }

        flutterEngine = null

        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .clear()
            .apply()

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        try {
            flutterEngine?.destroy()
        } catch (_: Exception) {
        }

        flutterEngine = null
        methodChannel = null

        Log.d(TAG, "File transfer service destroyed")

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager =
            getSystemService(NotificationManager::class.java)

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Dosya aktarımı",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description =
                "ZeroLog dosya aktarımı devam ederken gösterilir."
            setShowBadge(false)
        }

        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(
            this,
            CHANNEL_ID
        )
            .setSmallIcon(
                android.R.drawable.stat_sys_upload
            )
            .setContentTitle("ZeroLog")
            .setContentText(
                "Dosya aktarımı devam ediyor…"
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(
                NotificationCompat.CATEGORY_PROGRESS
            )
            .build()
    }
}
