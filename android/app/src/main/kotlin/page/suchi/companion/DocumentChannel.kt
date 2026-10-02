package page.suchi.companion

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DocumentExportProvider : FileProvider()

internal data class DocumentRoot(val directory: File, val operationPrefix: String)

internal object DocumentExport {
    private val committedOfflineName = Regex(
        "^offline-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    )
    private val savedPayloadName = Regex("^document-[1-9][0-9]*\\.[a-z0-9]+$")

    fun file(roots: List<DocumentRoot>, path: String): File {
        val requested = File(path).absoluteFile
        val requestedParent = requireNotNull(requested.parentFile)
        val file = requested.canonicalFile
        val parent = requireNotNull(file.parentFile)
        require(
            requested.name == file.name &&
                requestedParent.canonicalFile == parent &&
                requestedParent.name == parent.name &&
                requestedParent.parentFile?.canonicalFile == parent.parentFile,
        )
        require(file.isFile && file.length() in 1..(64L * 1024 * 1024))
        require(
            roots.any { candidate ->
                parent.parentFile == candidate.directory.canonicalFile &&
                    parent.name.startsWith(candidate.operationPrefix) &&
                    !parent.name.endsWith(".part") &&
                    (candidate.operationPrefix != "offline-" ||
                        (committedOfflineName.matches(parent.name) &&
                            savedPayloadName.matches(file.name)))
            },
        )
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

internal object DocumentLinkShare {
    fun intent(text: String): Intent {
        require(
            text.isNotBlank() &&
                text.toByteArray(Charsets.UTF_8).size <= 8 * 1024 &&
                text.none { (it.code < 0x20 && it != '\n') || it.code == 0x7f },
        )
        return Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
    }
}

class DocumentChannel(private val activity: MainActivity) {
    private var channel: MethodChannel? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "page.suchi.companion/documents",
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
        if (call.method == "share_link") {
            val text = call.argument<String>("text")
            try {
                val intent = DocumentLinkShare.intent(requireNotNull(text))
                activity.startActivity(Intent.createChooser(intent, "Share Suchi link"))
                result.success(null)
            } catch (_: ActivityNotFoundException) {
                result.error("share_unavailable", "The share sheet is unavailable.", null)
            } catch (_: Exception) {
                result.error("bad_document", "The share link handoff is invalid.", null)
            }
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
                listOf(
                    DocumentRoot(
                        File(activity.filesDir, "suchi-document-exports"),
                        "document-",
                    ),
                    DocumentRoot(
                        File(activity.filesDir, "suchi-offline-documents"),
                        "offline-",
                    ),
                ),
                path,
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
