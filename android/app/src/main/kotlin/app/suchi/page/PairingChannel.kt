package app.suchi.page

import android.os.Build
import android.provider.Settings

import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class PairingChannel(private val activity: MainActivity) {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(
            engine.dartExecutor.binaryMessenger, "app.suchi.page/pairing",
        ).also {
            it.setMethodCallHandler { call, result ->
                when {
                    call.method == "deviceName" -> result.success(deviceName())
                    call.method != "scan" -> result.notImplemented()
                    pending != null -> result.error("scan_busy", "A pairing scan is already open.", null)
                    else -> scan(result)
                }
            }
        }
    }

    fun close() {
        pending?.success(null)
        pending = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun deviceName(): String {
        val name = try {
            Settings.Global.getString(activity.contentResolver, Settings.Global.DEVICE_NAME)
        } catch (_: SecurityException) {
            null
        }
        return name?.trim()?.takeIf { it.isNotEmpty() } ?: Build.MODEL
    }

    private fun scan(result: MethodChannel.Result) {
        pending = result
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
        GmsBarcodeScanning.getClient(activity, options).startScan()
            .addOnSuccessListener { barcode ->
                val value = barcode.rawValue
                if (value.isNullOrEmpty() || value.toByteArray(Charsets.UTF_8).size > 4096) {
                    fail("invalid_pairing_code", "This code could not be read. Use Paste pairing link.")
                } else {
                    pending?.success(value)
                    pending = null
                }
            }
            .addOnCanceledListener {
                pending?.success(null)
                pending = null
            }
            .addOnFailureListener {
                fail("scan_unavailable", "QR scanning is unavailable. Use Paste pairing link or enter your server and account details.")
            }
    }

    private fun fail(code: String, message: String) {
        pending?.error(code, message, null)
        pending = null
    }
}
