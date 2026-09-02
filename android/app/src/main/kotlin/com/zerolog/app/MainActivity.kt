package com.zerolog.app

import android.Manifest
import android.content.Intent
import android.content.SharedPreferences
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.media.MediaPlayer
import android.media.AudioAttributes
import android.media.AudioManager
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.os.Build
import java.io.OutputStream
import java.security.MessageDigest
import java.io.File
import java.io.FileOutputStream
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.util.Locale
import kotlin.math.roundToInt
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "zerolog/system"
    private val lifecyclePrefsName = "zerolog_lifecycle"
    private val lifecycleForegroundKey = "foreground"

    private fun setLifecycleForeground(value: Boolean) {
        getSharedPreferences(lifecyclePrefsName, MODE_PRIVATE)
            .edit()
            .putBoolean(lifecycleForegroundKey, value)
            .apply()
    }

    override fun onResume() {
        super.onResume()
        setLifecycleForeground(true)
    }

    override fun onPause() {
        setLifecycleForeground(false)
        super.onPause()
    }

    private fun startFileTransferForegroundService() {
        try {
            val intent = Intent(
                this,
                FileTransferForegroundService::class.java
            ).apply {
                action = FileTransferForegroundService.ACTION_START
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Failed to start file transfer foreground service",
                e
            )
        }
    }

    private fun stopFileTransferForegroundService() {
        try {
            val intent = Intent(
                this,
                FileTransferForegroundService::class.java
            ).apply {
                action = FileTransferForegroundService.ACTION_STOP
            }

            startService(intent)
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Failed to stop file transfer foreground service",
                e
            )
        }
    }

    private val startupPermissionRequestCode = 7401
    private val callPermissionRequestCode = 7402
    private var outgoingCallPlayer: MediaPlayer? = null
    private var outgoingCallAudioManager: AudioManager? = null
    private var outgoingCallPreviousMode: Int? = null
    private var outgoingCallPreviousSpeaker: Boolean? = null
    private var callPermissionResult:
        io.flutter.plugin.common.MethodChannel.Result? = null
    private var startupPermissionResult:
        io.flutter.plugin.common.MethodChannel.Result? = null

    private val createDocumentRequestCode = 7403
    private val chooseFileSaveDirectoryRequestCode = 7404

    private val fileStoragePrefsName = "zerolog_file_storage"
    private val fileStorageTreeUriKey = "tree_uri"
    private val fileStorageLabelKey = "label"

    private val receivedFileIndexPrefsName = "zerolog_received_files"
    private val receivedFileUriPrefix = "uri_"

    private var incomingFileSaveResult:
        io.flutter.plugin.common.MethodChannel.Result? = null

    private var incomingFileOutputStream: OutputStream? = null
    private var incomingFileBytesWritten: Long = 0L
    private var incomingFileUri: Uri? = null
    private var incomingFileTempFile: File? = null
    private var incomingFileTargetCreated = false
    private var incomingFileTargetPending = false

    private var fileSaveDirectoryResult:
        io.flutter.plugin.common.MethodChannel.Result? = null

    private fun sanitizeIncomingFileName(fileName: String): String {
        val cleaned = fileName
            .replace(Regex("[/\\\\]"), "_")
            .trim()

        return if (cleaned.isEmpty()) {
            "received_file"
        } else {
            cleaned
        }
    }

    private fun defaultFileSaveLabel(): String = "İndirilenler"

    private fun storedFileSaveTreeUri(): Uri? {
        val raw = getSharedPreferences(
            fileStoragePrefsName,
            MODE_PRIVATE
        )
            .getString(fileStorageTreeUriKey, null)
            ?.trim()

        if (raw.isNullOrEmpty()) return null

        return try {
            Uri.parse(raw)
        } catch (_: Exception) {
            null
        }
    }

    private fun requestFileSaveDirectory(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        try {
            fileSaveDirectoryResult?.error(
                "SAVE_DIRECTORY_BUSY",
                "Başka bir klasör seçimi devam ediyor.",
                null
            )

            fileSaveDirectoryResult = result

            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }

            startActivityForResult(
                intent,
                chooseFileSaveDirectoryRequestCode
            )
        } catch (e: Exception) {
            fileSaveDirectoryResult = null

            result.error(
                "SAVE_DIRECTORY_DIALOG_FAILED",
                e.message ?: "Klasör seçme ekranı açılamadı.",
                null
            )
        }
    }

    private fun clearCustomFileSaveDirectory() {
        val prefs = getSharedPreferences(
            fileStoragePrefsName,
            MODE_PRIVATE
        )

        val raw = prefs.getString(
            fileStorageTreeUriKey,
            null
        )

        if (!raw.isNullOrEmpty()) {
            try {
                contentResolver.releasePersistableUriPermission(
                    Uri.parse(raw),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: Exception) {}
        }

        prefs.edit()
            .remove(fileStorageTreeUriKey)
            .remove(fileStorageLabelKey)
            .apply()
    }

    private fun getFileSaveDirectoryLabel(): String {
        return getSharedPreferences(
            fileStoragePrefsName,
            MODE_PRIVATE
        )
            .getString(fileStorageLabelKey, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: defaultFileSaveLabel()
    }

    private fun incomingFileMimeType(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "")
            .trim()
            .lowercase()

        return when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "heic", "heif" -> "image/heic"
            "pdf" -> "application/pdf"
            "txt" -> "text/plain"
            "mp4" -> "video/mp4"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "zip" -> "application/zip"
            else -> "application/octet-stream"
        }
    }

    private fun createIncomingFileTarget(
        fileName: String
    ): Uri? {
        val safeName = sanitizeIncomingFileName(fileName)

        val treeUri = storedFileSaveTreeUri()

        // Kullanıcının seçtiği klasör.
        if (treeUri != null) {
            try {
                val target = DocumentsContract.createDocument(
                    contentResolver,
                    treeUri,
                    incomingFileMimeType(safeName),
                    safeName
                )

                if (target != null) {
                    incomingFileTargetCreated = true
                    incomingFileTargetPending = false
                    return target
                }
            } catch (e: Exception) {
                android.util.Log.w(
                    "ZeroLogFile",
                    "Custom save directory unavailable; "
                        + "falling back to Downloads",
                    e
                )

                clearCustomFileSaveDirectory()
            }
        }

        // Varsayılan: Android Downloads.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(
                    MediaStore.MediaColumns.DISPLAY_NAME,
                    safeName
                )

                put(
                    MediaStore.MediaColumns.MIME_TYPE,
                    incomingFileMimeType(safeName)
                )

                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS
                )

                // Dosya doğrulanana kadar görünür olmasın.
                put(
                    MediaStore.MediaColumns.IS_PENDING,
                    1
                )
            }

            val target = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values
            )

            if (target != null) {
                incomingFileTargetCreated = true
                incomingFileTargetPending = true
                return target
            }
        }

        return null
    }

    private fun requestIncomingFileSave(
        fileName: String,
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        try {
            incomingFileSaveResult?.error(
                "SAVE_BUSY",
                "Başka bir dosya kayıt işlemi devam ediyor.",
                null
            )

            incomingFileSaveResult = result

            try {
                incomingFileOutputStream?.close()
            } catch (_: Exception) {}

            incomingFileOutputStream = null
            incomingFileBytesWritten = 0L
            incomingFileUri = null
            incomingFileTargetCreated = false
            incomingFileTargetPending = false

            incomingFileTempFile?.delete()
            incomingFileTempFile = null

            // Artık ACTION_CREATE_DOCUMENT açılmıyor.
            // Hedef doğrudan seçili klasör veya Downloads.
            val targetUri = createIncomingFileTarget(fileName)
                ?: throw IllegalStateException(
                    "Dosya için kayıt hedefi oluşturulamadı."
                )

            incomingFileUri = targetUri

            val tempFile = File.createTempFile(
                "zerolog_transfer_",
                ".part",
                cacheDir
            )

            incomingFileTempFile = tempFile

            incomingFileOutputStream =
                FileOutputStream(tempFile)

            incomingFileBytesWritten = 0L

            result.success(
                mapOf(
                    "uri" to targetUri.toString(),
                    "size" to 0L,
                    "directory" to getFileSaveDirectoryLabel()
                )
            )

            incomingFileSaveResult = null
        } catch (e: Exception) {
            incomingFileSaveResult = null

            try {
                incomingFileOutputStream?.close()
            } catch (_: Exception) {}

            incomingFileOutputStream = null

            try {
                incomingFileTempFile?.delete()
            } catch (_: Exception) {}

            incomingFileTempFile = null
            incomingFileBytesWritten = 0L

            try {
                if (
                    incomingFileTargetCreated &&
                    incomingFileUri != null
                ) {
                    contentResolver.delete(
                        incomingFileUri!!,
                        null,
                        null
                    )
                }
            } catch (_: Exception) {}

            incomingFileUri = null
            incomingFileTargetCreated = false
            incomingFileTargetPending = false

            result.error(
                "SAVE_OPEN_FAILED",
                e.message ?: "Dosya kayıt hedefi açılamadı.",
                null
            )
        }
    }

    private fun getReceivedFileUri(fileId: String): Uri? {
        val prefs = getSharedPreferences(
            receivedFileIndexPrefsName,
            MODE_PRIVATE
        )
        val uriString = prefs.getString(
            "$receivedFileUriPrefix$fileId",
            null
        )?.trim()
        if (uriString.isNullOrEmpty()) return null
        return try { Uri.parse(uriString) } catch (_: Exception) { null }
    }

    private fun getReceivedLocalFile(fileId: String): File? {
        if (fileId.isBlank()) return null

        val file = File(
            File(filesDir, "received_files"),
            fileId.replace(Regex("[^A-Za-z0-9._-]"), "_")
        )

        return if (file.exists() && file.length() > 0L) file else null
    }

    private fun getReceivedImageInputStream(fileId: String): java.io.InputStream? {
        val localFile = getReceivedLocalFile(fileId)

        if (localFile != null) {
            try {
                return localFile.inputStream()
            } catch (_: Exception) {}
        }

        val uri = getReceivedFileUri(fileId) ?: return null

        return try {
            contentResolver.openInputStream(uri)
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Received URI input stream failed",
                e
            )
            null
        }
    }

    private fun getReceivedImageThumbnail(
        fileId: String,
        maxSize: Int
    ): ByteArray? {
        if (fileId.isBlank()) return null

        return try {
            val bounds = android.graphics.BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }

            getReceivedImageInputStream(fileId)?.use { input ->
                android.graphics.BitmapFactory.decodeStream(
                    input,
                    null,
                    bounds
                )
            } ?: return null

            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                return null
            }

            var sample = 1

            while (
                bounds.outWidth / sample > maxSize * 2 ||
                bounds.outHeight / sample > maxSize * 2
            ) {
                sample *= 2
            }

            val options = android.graphics.BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = android.graphics.Bitmap.Config.RGB_565
            }

            val bitmap = getReceivedImageInputStream(fileId)?.use { input ->
                android.graphics.BitmapFactory.decodeStream(
                    input,
                    null,
                    options
                )
            } ?: return null

            if (bitmap.width <= 0 || bitmap.height <= 0) {
                bitmap.recycle()
                return null
            }

            val scale = minOf(
                1f,
                maxSize.toFloat() /
                    maxOf(bitmap.width, bitmap.height).toFloat()
            )

            val resized = if (scale < 1f) {
                android.graphics.Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * scale)
                        .roundToInt()
                        .coerceAtLeast(1),
                    (bitmap.height * scale)
                        .roundToInt()
                        .coerceAtLeast(1),
                    true
                )
            } else {
                bitmap
            }

            val stream = java.io.ByteArrayOutputStream()

            resized.compress(
                android.graphics.Bitmap.CompressFormat.JPEG,
                82,
                stream
            )

            if (resized !== bitmap) {
                resized.recycle()
            }

            bitmap.recycle()

            stream.toByteArray()
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Thumbnail generation failed",
                e
            )
            null
        }
    }

    private fun readReceivedImageBytes(fileId: String): ByteArray? {
        if (fileId.isBlank()) return null

        return try {
            getReceivedLocalFile(fileId)?.inputStream()?.use {
                it.readBytes()
            } ?: getReceivedFileUri(fileId)?.let { uri ->
                contentResolver.openInputStream(uri)?.use { input ->
                    input.readBytes()
                }
            }
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Received image read failed",
                e
            )
            null
        }
    }

    private fun deleteReceivedFile(fileId: String): Boolean {
        val uri = getReceivedFileUri(fileId)

        return try {
            var deleted = false

            if (uri != null) {
                deleted = try {
                    contentResolver.delete(uri, null, null) > 0
                } catch (_: Exception) {
                    false
                }
            }

            val localFile = getReceivedLocalFile(fileId)
            if (localFile != null) {
                deleted = localFile.delete() || deleted
            }

            getSharedPreferences(receivedFileIndexPrefsName, MODE_PRIVATE)
                .edit()
                .remove("$receivedFileUriPrefix$fileId")
                .apply()

            deleted
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Received file delete failed",
                e
            )
            false
        }
    }

    private fun openReceivedFile(
        fileId: String,
        fileName: String
    ): Boolean {
        return try {
            val prefs = getSharedPreferences(
                receivedFileIndexPrefsName,
                MODE_PRIVATE
            )

            val uriString = prefs.getString(
                "$receivedFileUriPrefix$fileId",
                null
            )?.trim()

            val uri = if (!uriString.isNullOrEmpty()) {
                Uri.parse(uriString)
            } else {
                val localFile = getReceivedLocalFile(fileId)
                    ?: return false

                FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    localFile
                )
            }

            val extensionMime = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(
                    fileName.substringAfterLast('.', "")
                )

            val providerMime = contentResolver.getType(uri)

            val mimeType = when {
                extensionMime != null -> extensionMime
                !providerMime.isNullOrBlank() -> providerMime
                else -> "application/octet-stream"
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                clipData = android.content.ClipData.newRawUri("ZeroLog", uri)
            }

            startActivity(intent)
            true
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Received file open failed",
                e
            )
            false
        }
    }

    private fun writeIncomingFile(bytes: ByteArray): Boolean {
        return try {
            val stream = incomingFileOutputStream ?: return false

            stream.write(bytes)
            incomingFileBytesWritten += bytes.size.toLong()

            true
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Incoming file write failed",
                e
            )
            false
        }
    }

    private fun getIncomingFileSha256(): String? {
        val file = incomingFileTempFile ?: return null

        return try {
            if (!file.exists()) {
                throw IllegalStateException(
                    "Geçici alınan dosya bulunamadı."
                )
            }

            val actualSize = file.length()

            if (actualSize != incomingFileBytesWritten) {
                throw IllegalStateException(
                    "Dosya boyutu uyuşmuyor: " +
                        "$actualSize / $incomingFileBytesWritten"
                )
            }

            if (actualSize <= 0L) {
                throw IllegalStateException(
                    "Alınan dosya boş."
                )
            }

            val digest = MessageDigest.getInstance("SHA-256")

            file.inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)

                while (true) {
                    val count = input.read(buffer)
                    if (count <= 0) break
                    digest.update(buffer, 0, count)
                }
            }

            digest.digest().joinToString("") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            }
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Incoming file SHA-256 calculation failed",
                e
            )
            null
        }
    }

    private fun finalizeIncomingFile(
        fileId: String
    ): String? {
        val tempFile = incomingFileTempFile ?: return null
        val targetUri = incomingFileUri ?: return null

        return try {
            // writeIncomingFile() tamamlandıktan sonra stream burada
            // kesin olarak kapatılır. closeIncomingFile() daha önce
            // çağrılmış olsa bile ikinci kez close edilmez.
            if (incomingFileOutputStream != null) {
                incomingFileOutputStream?.flush()
                incomingFileOutputStream?.close()
                incomingFileOutputStream = null
            }

            if (!tempFile.exists()) {
                throw IllegalStateException(
                    "Geçici alınan dosya bulunamadı."
                )
            }

            if (incomingFileBytesWritten <= 0L) {
                throw IllegalStateException(
                    "Alınan dosya boş."
                )
            }

            // Sohbet önizleme/okuma için uygulama içinde kalıcı bir
            // kopya tutuyoruz. Kullanıcının seçtiği hedef URI'sinden
            // bağımsız olarak çalışır ve history reload sonrasında da
            // fileId üzerinden bulunabilir.
            val receivedDir = File(filesDir, "received_files")
            if (!receivedDir.exists() && !receivedDir.mkdirs()) {
                throw IllegalStateException(
                    "ZeroLog alınan dosya klasörü oluşturulamadı."
                )
            }

            val localReceivedFile = File(
                receivedDir,
                fileId.replace(Regex("[^A-Za-z0-9._-]"), "_")
            )

            tempFile.inputStream().use { input ->
                localReceivedFile.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)

                    while (true) {
                        val count = input.read(buffer)

                        if (count <= 0) break

                        output.write(buffer, 0, count)
                    }

                    output.flush()
                }
            }

            if (!localReceivedFile.exists() || localReceivedFile.length() != tempFile.length()) {
                localReceivedFile.delete()
                throw IllegalStateException(
                    "ZeroLog yerel alınan dosya kopyası doğrulanamadı."
                )
            }

            contentResolver.openOutputStream(
                targetUri,
                "w"
            )?.use { output ->
                tempFile.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)

                    while (true) {
                        val count = input.read(buffer)

                        if (count <= 0) break

                        output.write(
                            buffer,
                            0,
                            count
                        )
                    }

                    output.flush()
                }
            } ?: throw IllegalStateException(
                "Hedef dosya için yazma akışı açılamadı."
            )

            // MediaStore pending kaydını görünür hale getir.
            if (incomingFileTargetPending) {
                val values = ContentValues().apply {
                    put(
                        MediaStore.MediaColumns.IS_PENDING,
                        0
                    )
                }

                contentResolver.update(
                    targetUri,
                    values,
                    null,
                    null
                )
            }

            tempFile.delete()
            incomingFileTempFile = null

            if (fileId.isNotBlank()) {
                getSharedPreferences(
                    receivedFileIndexPrefsName,
                    MODE_PRIVATE
                ).edit()
                    .putString(
                        "$receivedFileUriPrefix$fileId",
                        targetUri.toString()
                    )
                    .apply()
            }

            incomingFileTargetCreated = false
            incomingFileTargetPending = false
            incomingFileBytesWritten = 0L
            incomingFileUri = null

            targetUri.toString()
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Incoming file finalize failed",
                e
            )

            try {
                incomingFileOutputStream?.close()
            } catch (_: Exception) {}

            incomingFileOutputStream = null

            try {
                incomingFileTempFile?.delete()
            } catch (_: Exception) {}

            incomingFileTempFile = null

            try {
                if (incomingFileTargetCreated) {
                    contentResolver.delete(
                        targetUri,
                        null,
                        null
                    )
                }
            } catch (_: Exception) {}

            try {
                getReceivedLocalFile(fileId)?.delete()
            } catch (_: Exception) {}

            incomingFileTargetCreated = false
            incomingFileTargetPending = false
            incomingFileBytesWritten = 0L
            incomingFileUri = null

            null
        }
    }

    private fun closeIncomingFile(): Boolean {
        return try {
            val stream = incomingFileOutputStream

            if (stream != null) {
                stream.flush()
                stream.close()
                incomingFileOutputStream = null
            }

            true
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Incoming file close failed",
                e
            )
            incomingFileOutputStream = null
            false
        }
    }

    private fun discardIncomingFile(): Boolean {
        return try {
            try {
                incomingFileOutputStream?.close()
            } catch (_: Exception) {}

            incomingFileOutputStream = null

            incomingFileTempFile?.delete()
            incomingFileTempFile = null

            if (
                incomingFileTargetCreated &&
                incomingFileUri != null
            ) {
                try {
                    contentResolver.delete(
                        incomingFileUri!!,
                        null,
                        null
                    )
                } catch (_: Exception) {}
            }

            incomingFileTargetCreated = false
            incomingFileTargetPending = false
            incomingFileBytesWritten = 0L
            incomingFileUri = null

            true
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogFile",
                "Incoming file discard failed",
                e
            )

            incomingFileOutputStream = null
            incomingFileTempFile = null
            incomingFileBytesWritten = 0L
            incomingFileUri = null

            false
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == chooseFileSaveDirectoryRequestCode) {
            val result = fileSaveDirectoryResult
            fileSaveDirectoryResult = null

            if (
                resultCode != RESULT_OK ||
                data?.data == null
            ) {
                result?.success(null)
                return
            }

            val uri = data.data!!

            try {
                val flags =
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION

                contentResolver.takePersistableUriPermission(
                    uri,
                    flags
                )

                val label =
                    DocumentsContract
                        .getTreeDocumentId(uri)
                        ?.substringAfterLast(':')
                        ?.replace('_', ' ')
                        ?.trim()
                        .orEmpty()
                        .ifEmpty {
                            "Özel klasör"
                        }

                getSharedPreferences(
                    fileStoragePrefsName,
                    MODE_PRIVATE
                )
                    .edit()
                    .putString(
                        fileStorageTreeUriKey,
                        uri.toString()
                    )
                    .putString(
                        fileStorageLabelKey,
                        label
                    )
                    .apply()

                result?.success(label)
            } catch (e: Exception) {
                result?.error(
                    "SAVE_DIRECTORY_FAILED",
                    e.message ?: "Klasör kaydedilemedi.",
                    null
                )
            }

            return
        }

        if (requestCode != createDocumentRequestCode) {
            return
        }

        val result = incomingFileSaveResult
        incomingFileSaveResult = null

        if (resultCode != RESULT_OK || data?.data == null) {
            incomingFileOutputStream = null
            incomingFileBytesWritten = 0L
            incomingFileUri = null

            incomingFileTempFile?.delete()
            incomingFileTempFile = null

            result?.success(null)
            return
        }

        val uri = data.data!!

        try {
            incomingFileUri = uri

            val tempFile = File.createTempFile(
                "zerolog_transfer_",
                ".part",
                cacheDir
            )

            incomingFileTempFile = tempFile

            incomingFileOutputStream =
                FileOutputStream(tempFile)

            incomingFileBytesWritten = 0L

            result?.success(
                mapOf(
                    "uri" to uri.toString(),
                    "size" to 0L
                )
            )
        } catch (e: Exception) {
            try {
                incomingFileOutputStream?.close()
            } catch (_: Exception) {}

            incomingFileOutputStream = null
            incomingFileBytesWritten = 0L
            incomingFileUri = null

            incomingFileTempFile?.delete()
            incomingFileTempFile = null

            result?.error(
                "SAVE_OPEN_FAILED",
                e.message ?: "Dosya açılamadı.",
                null
            )
        }
    }

    private fun requestFullScreenIntentPermission(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            result.success(true)
            return
        }

        try {
            val notificationManager =
                getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager

            if (notificationManager.canUseFullScreenIntent()) {
                result.success(true)
                return
            }

            val intent = Intent(
                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(intent)

            // Android 14+ requires the user to explicitly allow
            // USE_FULL_SCREEN_INTENT for call notifications.
            result.success(false)
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Failed to open full-screen intent permission settings",
                e
            )
            result.success(false)
        }
    }

    private fun requestMiuiCallPermissionSetup(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        // Bu akış yalnızca Xiaomi + Android 11 ve altı için çalışır.
        // Android 12+ cihazlarda hiçbir davranış değişmez.
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.R) {
            result.success(true)
            return
        }

        val manufacturer = Build.MANUFACTURER
            .lowercase(Locale.ROOT)

        if (!manufacturer.contains("xiaomi")) {
            result.success(true)
            return
        }

        val setupPrefs = getSharedPreferences(
            "zerolog_miui_setup",
            MODE_PRIVATE
        )

        if (setupPrefs.getBoolean("prompted", false)) {
            result.success(true)
            return
        }

        android.app.AlertDialog.Builder(this)
            .setTitle("Çağrı izinleri")
            .setMessage(
                "Gelen çağrıların kilit ekranında tam ekran gösterilebilmesi " +
                    "için bu cihazda bazı ek izinlerin açılması gerekiyor.\n\n" +
                    "Bir sonraki ekranda \"Kilit ekranında görüntüle\" ve " +
                    "\"Arka planda çalışırken açılır pencereleri görüntüle\" " +
                    "izinlerini açın."
            )
            .setNegativeButton("Şimdi değil", null)
            .setPositiveButton("İzinleri aç") { _, _ ->
                setupPrefs
                    .edit()
                    .putBoolean("prompted", true)
                    .apply()

                openMiuiPermissionSettings()
            }
            .show()

        // Bu izin diyaloğu startup akışını BLOKLAMAMALI.
        // Özellikle MIUI Android 11'de native dialog görünmezse
        // Flutter'ın beyaz ekranda kalmasını önlemek için sonucu
        // dialog açıldıktan hemen sonra döndürüyoruz.
        result.success(true)
    }

    private fun openMiuiPermissionSettings(): Boolean {
        val intents = listOf(
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity"
                )
                putExtra("extra_pkgname", packageName)
            },
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.AppPermissionsEditorActivity"
                )
                putExtra("extra_pkgname", packageName)
            },
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )

        for (intent in intents) {
            try {
                startActivity(intent)

                android.util.Log.d(
                    "ZeroLogCall",
                    "MIUI permission settings opened"
                )

                return true
            } catch (_: Exception) {
                // MIUI sürümüne göre activity adı değişebilir.
                // Bir sonraki güvenli fallback denenir.
            }
        }

        android.util.Log.e(
            "ZeroLogCall",
            "Unable to open MIUI permission settings"
        )

        return false
    }

    private fun requestStartupPermissions(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        startupPermissionResult = result

        val permissions = mutableListOf<String>()

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (permissions.isEmpty()) {
            startupPermissionResult = null
            result.success(true)
            return
        }

        requestPermissions(
            permissions.toTypedArray(),
            startupPermissionRequestCode
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (requestCode == startupPermissionRequestCode) {
            val result = startupPermissionResult
            startupPermissionResult = null

            if (result != null) {
                result.success(true)
            }
        }

        if (requestCode == callPermissionRequestCode) {
            val result = callPermissionResult
            callPermissionResult = null

            if (result != null) {
                val granted = grantResults.isNotEmpty() &&
                    grantResults.all {
                        it == PackageManager.PERMISSION_GRANTED
                    }

                result.success(granted)
            }
        }
    }

    private fun requestCallPermissions(
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        callPermissionResult = result

        val permissions = mutableListOf<String>()

        if (
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.RECORD_AUDIO)
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }

        if (permissions.isEmpty()) {
            callPermissionResult = null
            result.success(true)
            return
        }

        requestPermissions(
            permissions.toTypedArray(),
            callPermissionRequestCode
        )
    }

    private fun startOutgoingCallTone() {
        stopOutgoingCallTone()

        try {
            val audioManager =
                getSystemService(AUDIO_SERVICE) as AudioManager

            outgoingCallAudioManager = audioManager
            outgoingCallPreviousMode = audioManager.mode
            outgoingCallPreviousSpeaker = audioManager.isSpeakerphoneOn

            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioManager.isSpeakerphoneOn = false

            outgoingCallPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(
                            AudioAttributes.USAGE_VOICE_COMMUNICATION
                        )
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SONIFICATION
                        )
                        .build()
                )

                setDataSource(
                    this@MainActivity,
                    Uri.parse(
                        "android.resource://${packageName}/${R.raw.zerolog_call}"
                    )
                )

                isLooping = true
                setVolume(0.85f, 0.85f)
                prepare()
                start()
            }
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Outgoing call tone failed",
                e
            )
            stopOutgoingCallTone()
        }
    }

    private fun clearCallLockScreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(false)
                setTurnScreenOn(false)
            }

            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            )

            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )

            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Failed to clear call lock-screen state",
                e
            )
        }
    }

    private fun stopOutgoingCallTone() {
        try {
            outgoingCallPlayer?.stop()
        } catch (_: Exception) {}

        try {
            outgoingCallPlayer?.release()
        } catch (_: Exception) {}

        outgoingCallPlayer = null

        try {
            val audioManager = outgoingCallAudioManager

            if (audioManager != null) {
                outgoingCallPreviousMode?.let {
                    audioManager.mode = it
                }

                outgoingCallPreviousSpeaker?.let {
                    audioManager.isSpeakerphoneOn = it
                }
            }
        } catch (_: Exception) {}

        outgoingCallAudioManager = null
        outgoingCallPreviousMode = null
        outgoingCallPreviousSpeaker = null
    }

    private fun persistIncomingCallIntent(incomingIntent: Intent?) {
        if (incomingIntent?.action != "zerolog.incoming_call" &&
            incomingIntent?.getBooleanExtra("zerolog_call", false) != true
        ) {
            return
        }

        val from = incomingIntent.getStringExtra("from")?.trim().orEmpty()
        val to = incomingIntent.getStringExtra("to")?.trim().orEmpty()
        val callId = incomingIntent.getStringExtra("callId")?.trim().orEmpty()

        if (from.isEmpty() || to.isEmpty() || callId.isEmpty()) return

        getSharedPreferences("zerolog_native_call", MODE_PRIVATE)
            .edit()
            .putString("from", from)
            .putString("to", to)
            .putString("callId", callId)
            .apply()
    }

    private fun applyIncomingCallLockScreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            }

            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            )

            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )

            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogCall",
                "Failed to enable call lock-screen state",
                e
            )
        }
    }

    private fun persistMessageIntent(incomingIntent: Intent?) {
        if (incomingIntent?.action != "zerolog.message") {
            return
        }

        val from = incomingIntent.getStringExtra("from")?.trim().orEmpty()
        val to = incomingIntent.getStringExtra("to")?.trim().orEmpty()
        val text = incomingIntent.getStringExtra("text")?.trim().orEmpty()
        val id = incomingIntent.getStringExtra("id")?.trim().orEmpty()
        val clientMessageId =
            incomingIntent.getStringExtra("clientMessageId")?.trim().orEmpty()

        val fileId =
            incomingIntent.getStringExtra("fileId")?.trim().orEmpty()
        val fileName =
            incomingIntent.getStringExtra("fileName")?.trim().orEmpty()
        val fileSize =
            incomingIntent.getStringExtra("fileSize")?.trim().orEmpty()

        if (from.isEmpty()) return

        // Normal mesaj veya dosya bildirimi.
        // Dosya bildiriminde text zorunlu değildir.
        if (text.isEmpty() && fileId.isEmpty()) return

        val prefs =
            getSharedPreferences("zerolog_native_message", MODE_PRIVATE)

        val existing = prefs.getString("queue", "[]") ?: "[]"

        try {
            val queue = org.json.JSONArray(existing)

            val item = org.json.JSONObject()
                .put(
                    "type",
                    if (fileId.isNotEmpty()) {
                        "privateFileMessage"
                    } else {
                        "privateMessage"
                    }
                )
                .put("from", from)
                .put("to", to)
                .put("text", text)
                .put("id", id)
                .put("clientMessageId", clientMessageId)
                .put("fileId", fileId)
                .put("fileName", fileName)
                .put("fileSize", fileSize)

            queue.put(item)

            // Koruyucu sınır: bozuk/sonsuz büyüyen pending kuyruğu
            // uygulamanın depolamasını tüketmesin.
            while (queue.length() > 100) {
                queue.remove(0)
            }

            prefs.edit()
                .putString("queue", queue.toString())
                .apply()
        } catch (e: Exception) {
            android.util.Log.e(
                "ZeroLogMessage",
                "Failed to persist pending message",
                e
            )
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        if (
            intent?.action == "zerolog.incoming_call" ||
            intent?.getBooleanExtra("zerolog_call", false) == true
        ) {
            applyIncomingCallLockScreen()
        }

        persistIncomingCallIntent(intent)
        persistMessageIntent(intent)

        if (
            intent?.action != "zerolog.incoming_call" &&
            intent?.getBooleanExtra("zerolog_call", false) != true
        ) {
            clearCallLockScreen()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val isIncomingCall =
            intent.action == "zerolog.incoming_call" ||
                intent.getBooleanExtra("zerolog_call", false)

        if (isIncomingCall) {
            applyIncomingCallLockScreen()
        }

        persistIncomingCallIntent(intent)
        persistMessageIntent(intent)

        if (isIncomingCall) {
            val from = intent.getStringExtra("from")?.trim().orEmpty()
            val to = intent.getStringExtra("to")?.trim().orEmpty()
            val callId = intent.getStringExtra("callId")?.trim().orEmpty()

            if (from.isNotEmpty() && to.isNotEmpty() && callId.isNotEmpty()) {
                try {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, channelName).invokeMethod(
                            "incomingCallIntent",
                            mapOf(
                                "type" to "callInvite",
                                "from" to from,
                                "to" to to,
                                "callId" to callId,
                            ),
                        )
                    }

                    android.util.Log.d(
                        "ZeroLogCall",
                        "Incoming call forwarded to Flutter: callId=$callId"
                    )
                } catch (e: Exception) {
                    android.util.Log.e(
                        "ZeroLogCall",
                        "Failed to forward incoming call to Flutter",
                        e
                    )
                }
            }
        }

        if (!isIncomingCall) {
            clearCallLockScreen()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                  "startFileTransferForegroundService" -> {
                      startFileTransferForegroundService()
                      result.success(true)
                  }

                  "stopFileTransferForegroundService" -> {
                      stopFileTransferForegroundService()
                      result.success(true)
                  }

                                  "getReceivedImageThumbnail" -> {
                      val fileId = call.argument<String>("fileId")?.trim().orEmpty()
                      val maxSize = (call.argument<Int>("maxSize") ?: 640).coerceIn(96, 1280)
                      result.success(if (fileId.isEmpty()) null else getReceivedImageThumbnail(fileId, maxSize))
                  }

                  "readReceivedImageBytes" -> {
                      val fileId = call.argument<String>("fileId")?.trim().orEmpty()
                      result.success(if (fileId.isEmpty()) null else readReceivedImageBytes(fileId))
                  }

                  "deleteReceivedFile" -> {
                      val fileId = call.argument<String>("fileId")?.trim().orEmpty()
                      result.success(if (fileId.isEmpty()) false else deleteReceivedFile(fileId))
                  }

                  "openReceivedFile" -> {
                      val fileId =
                          call.argument<String>("fileId")
                              ?.trim()
                              .orEmpty()

                      val fileName =
                          call.argument<String>("fileName")
                              ?.trim()
                              ?.ifEmpty { "received_file" }
                              ?: "received_file"

                      result.success(
                          openReceivedFile(
                              fileId,
                              fileName
                          )
                      )
                  }

                  "requestIncomingFileSave" -> {
                      val fileName =
                          call.argument<String>("fileName")
                              ?.trim()
                              ?.ifEmpty { "received_file" }
                              ?: "received_file"

                      requestIncomingFileSave(fileName, result)
                  }

                  "writeIncomingFile" -> {
                      val bytes = call.arguments as? ByteArray

                      if (bytes == null) {
                          result.success(false)
                      } else {
                          result.success(writeIncomingFile(bytes))
                      }
                  }

                  "closeIncomingFile" -> {
                      result.success(closeIncomingFile())
                  }

                  "discardIncomingFile" -> {
                      result.success(discardIncomingFile())
                  }

                  "getIncomingFileSha256" -> {
                      result.success(getIncomingFileSha256())
                  }

                  "finalizeIncomingFile" -> {
                      val fileId =
                          call.argument<String>("fileId")
                              ?.trim()
                              .orEmpty()

                      result.success(
                          finalizeIncomingFile(fileId)
                      )
                  }

                  "chooseFileSaveDirectory" -> {
                      requestFileSaveDirectory(result)
                  }

                  "getFileSaveDirectory" -> {
                      result.success(
                          getFileSaveDirectoryLabel()
                      )
                  }

                  "resetFileSaveDirectory" -> {
                      clearCustomFileSaveDirectory()
                      result.success(
                          defaultFileSaveLabel()
                      )
                  }

                  "getTurnUsername" -> {
                      result.success(
                          getSharedPreferences(
                              "zerolog_turn",
                              MODE_PRIVATE
                          ).getString("username", "")
                      )
                  }

                  "getTurnPassword" -> {
                      result.success(
                          getSharedPreferences(
                              "zerolog_turn",
                              MODE_PRIVATE
                          ).getString("password", "")
                      )
                  }

"getIncomingCallIntent" -> {
                    // Cold start + notification tap + singleTop/onNewIntent
                    // durumlarının tamamında aynı pending-call kaynağını kullan.
                    persistIncomingCallIntent(intent)

                    val prefs =
                        getSharedPreferences("zerolog_native_call", MODE_PRIVATE)

                    val currentIntent = intent

                    val hasCallIntent =
                        currentIntent?.action == "zerolog.incoming_call" ||
                        currentIntent?.getBooleanExtra("zerolog_call", false) == true

                    val from = if (hasCallIntent) {
                        currentIntent?.getStringExtra("from")?.trim().orEmpty()
                    } else {
                        prefs.getString("from", "")?.trim().orEmpty()
                    }

                    val to = if (hasCallIntent) {
                        currentIntent?.getStringExtra("to")?.trim().orEmpty()
                    } else {
                        prefs.getString("to", "")?.trim().orEmpty()
                    }

                    val callId = if (hasCallIntent) {
                        currentIntent?.getStringExtra("callId")?.trim().orEmpty()
                    } else {
                        prefs.getString("callId", "")?.trim().orEmpty()
                    }

                    val data =
                        if (from.isNotEmpty() &&
                            to.isNotEmpty() &&
                            callId.isNotEmpty()
                        ) {
                            prefs.edit().clear().apply()

                            mapOf(
                                "type" to "callInvite",
                                "from" to from,
                                "to" to to,
                                "callId" to callId,
                            )
                        } else {
                            null
                        }

                    result.success(data)
                }
                "getPendingMessageIntent" -> {
                    val prefs =
                        getSharedPreferences("zerolog_native_message", MODE_PRIVATE)

                    val rawQueue =
                        prefs.getString("queue", "[]") ?: "[]"

                    try {
                        val queue = org.json.JSONArray(rawQueue)

                        if (queue.length() == 0) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val item = queue.optJSONObject(0)

                        if (item == null) {
                            queue.remove(0)
                            prefs.edit()
                                .putString("queue", queue.toString())
                                .apply()

                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val type =
                            item.optString("type", "privateMessage")
                                .trim()

                        val from =
                            item.optString("from", "").trim()

                        val to =
                            item.optString("to", "").trim()

                        val text =
                            item.optString("text", "").trim()

                        val id =
                            item.optString("id", "").trim()

                        val clientMessageId =
                            item.optString("clientMessageId", "").trim()

                        val fileId =
                            item.optString("fileId", "").trim()

                        val fileName =
                            item.optString("fileName", "").trim()

                        val fileSize =
                            item.optString("fileSize", "").trim()

                        val isFile = type == "privateFileMessage"

                        val valid = from.isNotEmpty() &&
                            if (isFile) {
                                fileId.isNotEmpty()
                            } else {
                                text.isNotEmpty()
                            }

                        // Sadece tüketilen ilk kaydı kuyruktan çıkar.
                        // Diğer pending mesajlar korunur.
                        queue.remove(0)

                        prefs.edit()
                            .putString("queue", queue.toString())
                            .apply()

                        val data =
                            if (valid) {
                                buildMap<String, Any> {
                                    put("type", type)
                                    put("from", from)
                                    put("to", to)
                                    put("text", text)
                                    put("id", id)
                                    put("clientMessageId", clientMessageId)

                                    if (isFile) {
                                        put("fileId", fileId)
                                        put("fileName", fileName)
                                        put("fileSize", fileSize)
                                    }
                                }
                            } else {
                                null
                            }

                        result.success(data)
                    } catch (e: Exception) {
                        android.util.Log.e(
                            "ZeroLogMessage",
                            "Failed to read pending message queue",
                            e
                        )

                        result.success(null)
                    }
                }

                "requestStartupPermissions" -> {
                    requestStartupPermissions(result)
                }

                "requestMiuiCallPermissionSetup" -> {
                    requestMiuiCallPermissionSetup(result)
                }

                "requestFullScreenIntentPermission" -> {
                    requestFullScreenIntentPermission(result)
                }

                "requestCallPermissions" -> {
                    requestCallPermissions(result)
                }

                "startOutgoingCallTone" -> {
                    startOutgoingCallTone()
                    result.success(true)
                }

                "startIncomingCallTone" -> {
                    ZeroLogFirebaseMessagingService
                        .startIncomingCallTone(this)

                    result.success(true)
                }

                "stopOutgoingCallTone" -> {
                    stopOutgoingCallTone()
                    result.success(true)
                }

                "stopIncomingCallTone" -> {
                    ZeroLogFirebaseMessagingService
                        .stopIncomingCallToneAndNotification(this)
                    result.success(true)
                }

                "clearCallLockScreen" -> {
                    clearCallLockScreen()
                    result.success(true)
                }

                "getDefaultRingtoneUri" -> {
                    try {
                        val uri: Uri? = RingtoneManager.getActualDefaultRingtoneUri(
                            this,
                            RingtoneManager.TYPE_RINGTONE
                        )

                        result.success(uri?.toString())
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopOutgoingCallTone()

        val incomingCallActive =
            intent?.action == "zerolog.incoming_call" ||
                intent?.getBooleanExtra("zerolog_call", false) == true

        if (!incomingCallActive) {
            clearCallLockScreen()
        }

        super.onDestroy()
    }

}
