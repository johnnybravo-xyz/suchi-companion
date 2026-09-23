package app.suchi.page

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DocumentExportProvider : FileProvider()

internal object DocumentExport {
    fun file(root: File, path: String): File {
        val directory = root.canonicalFile
        val file = File(path).canonicalFile
        require(file.isFile && file.length() in 1..(64L * 1024 * 1024))
        require(file.parentFile?.parentFile == directory)
        require(file.parentFile?.name?.startsWith("document-") == true)
        return file
    }

    fun intent(uri: android.net.Uri, mimeType: String, share: Boolean): Intent =
        Intent(if (share) Intent.ACTION_SEND else Intent.ACTION_VIEW).apply {
            if (share) {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
            } else {
                setDataAndType(uri, mimeType)
            }
            clipData = ClipData.newRawUri("Document", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
}

class DocumentChannel(private val activity: MainActivity) {
    private var channel: MethodChannel? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "app.suchi.page/documents",
        ).also { it.setMethodCallHandler(::handle) }
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "dismiss") {
            result.success(null)
            return
        }
        if (call.method != "open" && call.method != "share") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val mimeType = call.argument<String>("mime_type")
        if (path == null || mimeType == null ||
            !mimeType.matches(Regex("^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$"))
        ) {
            result.error("bad_document", "The document handoff is invalid.", null)
            return
        }
        try {
            val file = DocumentExport.file(
                File(activity.filesDir, "suchi-document-exports"), path,
            )
            val uri = FileProvider.getUriForFile(
                activity, "${activity.packageName}.document-exports", file,
            )
            val intent = DocumentExport.intent(uri, mimeType, call.method == "share")
            activity.startActivity(
                if (call.method == "share") Intent.createChooser(intent, "Share document")
                else intent,
            )
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error(
                "viewer_unavailable",
                "No app can open this document type. Install a compatible viewer or use Share.",
                null,
            )
        } catch (_: Exception) {
            result.error("document_unavailable", "The document could not be opened or shared.", null)
        }
    }
}
