package page.suchi.companion

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

class PhotoCaptureProvider : FileProvider()

internal object PhotoCapture {
    fun intent(uri: Uri): Intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
        putExtra(MediaStore.EXTRA_OUTPUT, uri)
        clipData = ClipData.newRawUri("Photo", uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
    }
}

internal object ScanResultPayload {
    fun cancelled(): Map<String, Any?> =
        mapOf(
            "cancelled" to true,
            "pdf_path" to null,
            "page_count" to 0,
            "pages" to emptyList<Map<String, String>>(),
        )

    fun completed(
        pdfPath: String?,
        pageCount: Int,
        pagePaths: List<String>,
    ): Map<String, Any?> {
        require(pageCount > 0)
        require(pagePaths.size <= pageCount)
        return mapOf(
            "cancelled" to false,
            "pdf_path" to pdfPath,
            "page_count" to pageCount,
            "pages" to pagePaths.map { mapOf("path" to it) },
        )
    }

    fun recognitionUnavailable(pagePaths: List<String>): List<Map<String, Any?>> =
        pagePaths.map { path ->
            mapOf(
                "path" to path,
                "text" to "",
                "confidence" to null,
                "language" to null,
                "error_code" to "recognition_unavailable",
            )
        }
}

class ScanChannel(private val activity: FlutterActivity) {
    private companion object {
        const val CHANNEL_NAME = "page.suchi.companion/scan"
        const val CAPTURE_REQUEST = 4711
        const val PHOTO_REQUEST = 4712
        const val STORE_NAME = "suchi-scanner-captures"
        const val MANIFEST_VERSION = 1
    }

    private val scanner =
        GmsDocumentScanning.getClient(
            GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(true)
                .setResultFormats(
                    GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
                    GmsDocumentScannerOptions.RESULT_FORMAT_PDF,
                )
                .setPageLimit(NativeIntakeLimits.MAX_CAPTURE_PAGES)
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .build(),
        )
    private var pendingCapture: MethodChannel.Result? = null
    // A fixed private output survives activity recreation; only a successful camera result is retained.
    private val photoFile get() = File(activity.filesDir, "suchi-photo-capture/pending.jpg")
    private fun photoUri() = FileProvider.getUriForFile(
        activity, "${activity.packageName}.photo-capture", photoFile,
    )

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(::onMethodCall)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == PHOTO_REQUEST) {
            val result = pendingCapture
            pendingCapture = null
            try {
                activity.revokeUriPermission(
                    photoUri(),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                when (resultCode) {
                    Activity.RESULT_CANCELED -> {
                        photoFile.delete()
                        result?.success(ScanResultPayload.cancelled())
                    }
                    Activity.RESULT_OK -> retainPendingPhoto(result)
                    else -> {
                        photoFile.delete()
                        result?.error("capture_failed", "The camera did not complete.", null)
                    }
                }
            } catch (_: Exception) {
                result?.error("capture_failed", "The photo could not be retained. Try again.", mapOf("retryable" to true))
            }
            return true
        }
        if (requestCode != CAPTURE_REQUEST) return false
        val result = pendingCapture
        pendingCapture = null
        if (resultCode == Activity.RESULT_CANCELED) {
            result?.success(ScanResultPayload.cancelled())
            return true
        }
        if (resultCode != Activity.RESULT_OK) {
            result?.error("scan_failed", "The document scanner did not complete.", null)
            return true
        }
        val scan = GmsDocumentScanningResult.fromActivityResultIntent(data)
        if (scan == null) {
            result?.error("invalid_native_result", "The document scanner returned no result.", null)
            return true
        }
        retainCapture(
            scan.pages.orEmpty().map { it.imageUri },
            scan.pdf?.uri,
            maxOf(scan.pages.orEmpty().size, scan.pdf?.pageCount ?: 0),
            result,
        )
        return true
    }

    fun onResume() {
        if (pendingCapture == null && photoFile.exists()) {
            retainPendingPhoto(null)
        }
    }

    private fun retainPendingPhoto(result: MethodChannel.Result?) {
        if (!isRecoverablePhoto(photoFile)) {
            photoFile.delete()
            result?.error(
                "capture_failed",
                "The camera returned an invalid photo. Try again.",
                mapOf("retryable" to true),
            )
            return
        }
        if (retainCapture(listOf(photoFile.toUri()), null, 1, result)) {
            photoFile.delete()
        }
    }

    private fun isRecoverablePhoto(file: File): Boolean {
        if (
            !file.isFile ||
                file.length() <= 0 ||
                file.length() > NativeIntakeLimits.MAX_CAPTURE_PAGE_BYTES
        ) {
            return false
        }
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, options)
        return options.outWidth > 0 &&
            options.outHeight > 0 &&
            options.outMimeType == "image/jpeg"
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> {
                when (call.argument<String>("mode") ?: "scanner") {
                    "scanner" -> capture(result)
                    "photo" -> capturePhoto(result)
                    else -> result.error("bad_capture_mode", "Unknown camera mode.", null)
                }
            }
            "recognizeText" -> recognizeText(call, result)
            "discardCapture" -> discardCapture(call, result)
            "openSettings" -> openSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun recognizeText(call: MethodCall, result: MethodChannel.Result) {
        val rawPaths = call.argument<List<*>>("paths")
        if (rawPaths == null || rawPaths.size > NativeIntakeLimits.MAX_CAPTURE_PAGES) {
            result.error("bad_page_path", "OCR page paths are invalid.", null)
            return
        }
        val paths = rawPaths.map { value ->
            value as? String ?: run {
                result.error("bad_page_path", "OCR page paths are invalid.", null)
                return
            }
        }
        if (paths.any { validatedCaptureFile(it) == null }) {
            result.error("bad_page_path", "OCR page paths are invalid.", null)
            return
        }
        result.success(ScanResultPayload.recognitionUnavailable(paths))
    }

    private fun openSettings(result: MethodChannel.Result) {
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    "package:${activity.packageName}".toUri(),
                ),
            )
            result.success(null)
        } catch (_: Exception) {
            result.error(
                "settings_unavailable",
                "Application settings could not be opened.",
                mapOf("retryable" to false),
            )
        }
    }

    private fun capture(result: MethodChannel.Result) {
        if (pendingCapture != null) {
            result.error("scan_busy", "A document scan is already active.", null)
            return
        }
        if (!reserveCaptureStorage(result)) return
        pendingCapture = result
        scanner.getStartScanIntent(activity)
            .addOnSuccessListener { sender ->
                try {
                    activity.startIntentSenderForResult(
                        sender,
                        CAPTURE_REQUEST,
                        null,
                        0,
                        0,
                        0,
                    )
                } catch (_: Exception) {
                    pendingCapture = null
                    result.error(
                        "scan_unavailable",
                        "The document scanner could not start.",
                        mapOf("retryable" to false),
                    )
                }
            }
            .addOnFailureListener { error ->
                pendingCapture = null
                sendScannerFailure(result, error)
            }
    }

    private fun capturePhoto(result: MethodChannel.Result) {
        if (pendingCapture != null) {
            result.error("scan_busy", "A capture is already active.", null)
            return
        }
        if (!reserveCaptureStorage(result)) return
        try {
            val directory = photoFile.parentFile!!
            if (!directory.isDirectory && !directory.mkdirs()) throw IOException("photo directory unavailable")
            activity.revokeUriPermission(
                photoUri(),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            if (photoFile.exists() && !photoFile.delete()) throw IOException("photo cleanup failed")
            if (!photoFile.createNewFile()) throw IOException("photo output unavailable")
            pendingCapture = result
            activity.startActivityForResult(PhotoCapture.intent(photoUri()), PHOTO_REQUEST)
        } catch (_: ActivityNotFoundException) {
            pendingCapture = null
            photoFile.delete()
            result.error("camera_unavailable", "No camera app is available. Try Scanner mode.", mapOf("retryable" to false))
        } catch (_: Exception) {
            pendingCapture = null
            photoFile.delete()
            result.error("camera_unavailable", "The camera could not open. Try again or use Scanner mode.", mapOf("retryable" to true))
        }
    }

    private fun reserveCaptureStorage(result: MethodChannel.Result): Boolean =
        try {
            WritableStorage.requireCapacity(
                activity.filesDir,
                NativeIntakeLimits.MAX_CAPTURE_WORKING_BYTES,
            )
            true
        } catch (_: IOException) {
            result.error(
                "storage_unavailable",
                "Free at least 512 MiB of device storage before capturing documents.",
                mapOf("retryable" to true),
            )
            false
        }

    private fun retainCapture(
        pageUris: List<Uri>,
        pdfUri: Uri?,
        pageCount: Int,
        result: MethodChannel.Result?,
    ): Boolean {
        val root = File(activity.filesDir, STORE_NAME)
        val captureDirectory = File(root, UUID.randomUUID().toString())
        try {
            if (!root.isDirectory && !root.mkdirs()) {
                throw IOException("capture root unavailable")
            }
            WritableStorage.requireCapacity(
                root,
                NativeIntakeLimits.MAX_CAPTURE_WORKING_BYTES,
            )
            if (!captureDirectory.mkdirs()) {
                throw IOException("capture directory unavailable")
            }
            if (pageCount <= 0 || pageCount > NativeIntakeLimits.MAX_CAPTURE_PAGES) {
                throw IntakeLimitExceededException()
            }
            val captureBudget = BoundedByteCounter(NativeIntakeLimits.MAX_CAPTURE_WORKING_BYTES)
            val pageFiles = pageUris.mapIndexed { index, uri ->
                copyAtomically(
                    uri,
                    File(captureDirectory, "page-${index.toString().padStart(3, '0')}.jpg"),
                    captureBudget,
                    NativeIntakeLimits.MAX_CAPTURE_PAGE_BYTES,
                )
            }
            val pdfFile = pdfUri?.let { uri ->
                copyAtomically(
                    uri,
                    File(captureDirectory, "document.pdf"),
                    captureBudget,
                    NativeIntakeLimits.MAX_DOCUMENT_BYTES,
                )
            }
            if (pageFiles.isEmpty() && pdfFile == null) {
                throw IOException("capture contained no pages")
            }
            writeManifest(captureDirectory, pageCount, pageFiles, pdfFile)
            result?.success(
                ScanResultPayload.completed(
                    pdfPath = pdfFile?.absolutePath,
                    pageCount = pageCount,
                    pagePaths = pageFiles.map(File::getAbsolutePath),
                ),
            )
            return true
        } catch (_: IntakeLimitExceededException) {
            captureDirectory.deleteRecursively()
            result?.error(
                "capture_too_large",
                NativeIntakeLimits.CAPTURE_LIMIT_MESSAGE,
                mapOf("retryable" to false),
            )
            return false
        } catch (_: Exception) {
            captureDirectory.deleteRecursively()
            result?.error(
                "storage_unavailable",
                "Captured files could not be retained.",
                mapOf("retryable" to true),
            )
            return false
        }
    }

    private fun discardCapture(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths")
        if (paths.isNullOrEmpty() || paths.size > 100) {
            result.error("bad_capture_paths", "Capture paths are invalid.", null)
            return
        }
        try {
            val files = paths.map { path ->
                validatedCaptureFile(path) ?: throw IOException("invalid capture path")
            }
            val directory = files.first().parentFile?.canonicalFile
                ?: throw IOException("missing capture directory")
            val root = File(activity.filesDir, STORE_NAME).canonicalFile
            if (
                files.any { it.parentFile?.canonicalFile != directory } ||
                    directory.parentFile?.canonicalFile != root
            ) {
                throw IOException("capture paths do not share a capture directory")
            }
            directory.deleteRecursively()
            if (directory.exists()) throw IOException("capture cleanup failed")
            result.success(null)
        } catch (_: Exception) {
            result.error(
                "capture_cleanup_failed",
                "Captured files could not be removed.",
                mapOf("retryable" to true),
            )
        }
    }

    private fun validatedCaptureFile(path: String): File? {
        return try {
            val root = File(activity.filesDir, STORE_NAME).canonicalFile
            val file = File(path).canonicalFile
            val prefix = root.path + File.separator
            file.takeIf { it.isFile && it.path.startsWith(prefix) }
        } catch (_: IOException) {
            null
        }
    }

    private fun copyAtomically(
        uri: Uri,
        destination: File,
        captureBudget: BoundedByteCounter,
        maximumBytes: Long,
    ): File {
        val part = File(destination.parentFile, destination.name + ".part")
        val itemBudget = BoundedByteCounter(maximumBytes)
        WritableStorage.requireCapacity(destination.parentFile!!, maximumBytes)
        activity.contentResolver.openInputStream(uri).use { input ->
            if (input == null) throw IOException("capture stream unavailable")
            FileOutputStream(part).use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    itemBudget.add(count)
                    captureBudget.add(count)
                    output.write(buffer, 0, count)
                }
                output.fd.sync()
            }
        }
        if (itemBudget.consumed == 0L) {
            part.delete()
            throw IOException("capture stream was empty")
        }
        if (!part.renameTo(destination)) {
            part.delete()
            throw IOException("capture rename failed")
        }
        return destination
    }

    private fun writeManifest(
        directory: File,
        pageCount: Int,
        pages: List<File>,
        pdf: File?,
    ) {
        val json =
            JSONObject()
                .put("version", MANIFEST_VERSION)
                .put("created_at", System.currentTimeMillis())
                .put("page_count", pageCount)
                .put("pdf_path", pdf?.name ?: JSONObject.NULL)
                .put("pages", JSONArray(pages.map(File::getName)))
        val destination = File(directory, "manifest.json")
        val part = File(directory, "manifest.json.part")
        val encoded = json.toString().toByteArray(Charsets.UTF_8)
        WritableStorage.requireCapacity(directory, encoded.size.toLong())
        FileOutputStream(part).use { output ->
            output.write(encoded)
            output.fd.sync()
        }
        if (!part.renameTo(destination)) {
            part.delete()
            throw IOException("manifest rename failed")
        }
    }

    private fun sendScannerFailure(result: MethodChannel.Result, error: Exception) {
        val nativeCode = (error as? MlKitException)?.errorCode
        val retryable = nativeCode in setOf(
            MlKitException.DEADLINE_EXCEEDED,
            MlKitException.RESOURCE_EXHAUSTED,
            MlKitException.INTERNAL,
            MlKitException.UNAVAILABLE,
            MlKitException.DATA_LOSS,
        )
        result.error(
            if (retryable) "scan_temporarily_unavailable" else "scan_unavailable",
            if (retryable) {
                "The document scanner is temporarily unavailable."
            } else {
                "Document scanning is unavailable on this device."
            },
            mapOf("retryable" to retryable, "native_code" to nativeCode),
        )
    }

}
