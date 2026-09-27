package page.suchi.companion

import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.File

class StorageChannel(private val activity: MainActivity) {
    private companion object {
        const val CHANNEL_NAME = "page.suchi.companion/storage"
    }

    private var channel: MethodChannel? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("bad_storage_path", "Storage path is required.", null)
            return
        }
        try {
            val root = activity.filesDir.canonicalFile
            val directory = File(path).canonicalFile
            val contained = directory == root || directory.path.startsWith(root.path + File.separator)
            if (!directory.isDirectory || !contained) {
                result.error(
                    "bad_storage_path",
                    "Storage path must be an app files directory.",
                    null,
                )
                return
            }
            when (call.method) {
                "protectDirectory" -> {
                    // Android backup and device-transfer rules exclude the complete app data tree.
                    result.success(null)
                }
                "availableBytes" -> result.success(WritableStorage.availableBytes(directory))
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("storage_protection_failed", "Storage check failed.", null)
        }
    }
}

internal class LowStorageException : IOException("minimum free storage reserve unavailable")

internal object WritableStorage {
    const val MINIMUM_FREE_BYTES = 512L * 1024 * 1024

    fun availableBytes(directory: File): Long = StatFs(directory.path).availableBytes

    fun canWrite(availableBytes: Long, byteCount: Long): Boolean =
        byteCount >= 0 && availableBytes - byteCount >= MINIMUM_FREE_BYTES

    fun requireCapacity(directory: File, byteCount: Long) {
        if (!canWrite(availableBytes(directory), byteCount)) {
            throw LowStorageException()
        }
    }
}
