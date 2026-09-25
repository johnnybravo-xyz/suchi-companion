package page.suchi.companion

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
        if (call.method != "protectDirectory") {
            result.notImplemented()
            return
        }
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
            // Android backup and device-transfer rules exclude the complete app data tree.
            result.success(null)
        } catch (_: Exception) {
            result.error("storage_protection_failed", "Storage protection failed.", null)
        }
    }
}
