package page.suchi.companion

import android.os.Build
import android.provider.Settings

import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallClient
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class PairingChannel(private val activity: MainActivity) {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var installClient: ModuleInstallClient? = null
    private var installListener: InstallStatusListener? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(
            engine.dartExecutor.binaryMessenger, "page.suchi.companion/pairing",
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
        clearInstallListener()
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
        val scanner = GmsBarcodeScanning.getClient(activity, options)
        val client = ModuleInstall.getClient(activity)
        client.areModulesAvailable(scanner)
            .addOnSuccessListener { availability ->
                if (pending !== result) {
                    return@addOnSuccessListener
                }
                if (availability.areModulesAvailable()) {
                    startScanner(scanner, result)
                } else {
                    installScannerModule(client, scanner, result)
                }
            }
            .addOnFailureListener {
                if (pending === result) {
                    failUnavailable()
                }
            }
    }

    private fun installScannerModule(
        client: ModuleInstallClient,
        scanner: GmsBarcodeScanner,
        result: MethodChannel.Result,
    ) {
        lateinit var listener: InstallStatusListener
        listener = InstallStatusListener { update ->
            if (installListener !== listener || pending !== result) {
                return@InstallStatusListener
            }
            when (update.installState) {
                ModuleInstallStatusUpdate.InstallState.STATE_COMPLETED -> {
                    clearInstallListener()
                    startScanner(scanner, result)
                }
                ModuleInstallStatusUpdate.InstallState.STATE_CANCELED,
                ModuleInstallStatusUpdate.InstallState.STATE_FAILED,
                -> {
                    clearInstallListener()
                    failUnavailable()
                }
            }
        }
        installClient = client
        installListener = listener
        val request = ModuleInstallRequest.newBuilder()
            .addApi(scanner)
            .setListener(listener)
            .build()
        client.installModules(request)
            .addOnSuccessListener { response ->
                if (installListener !== listener || pending !== result) {
                    return@addOnSuccessListener
                }
                if (response.areModulesAlreadyInstalled()) {
                    clearInstallListener()
                    startScanner(scanner, result)
                }
            }
            .addOnFailureListener {
                if (installListener === listener && pending === result) {
                    clearInstallListener()
                    failUnavailable()
                }
            }
    }

    private fun startScanner(scanner: GmsBarcodeScanner, result: MethodChannel.Result) {
        if (pending !== result) {
            return
        }
        scanner.startScan()
            .addOnSuccessListener { barcode ->
                if (pending !== result) {
                    return@addOnSuccessListener
                }
                val value = barcode.rawValue
                if (value.isNullOrEmpty() || value.toByteArray(Charsets.UTF_8).size > 4096) {
                    fail("invalid_pairing_code", "This code could not be read. Use Paste pairing link.")
                } else {
                    result.success(value)
                    pending = null
                }
            }
            .addOnCanceledListener {
                if (pending === result) {
                    result.success(null)
                    pending = null
                }
            }
            .addOnFailureListener {
                if (pending === result) {
                    failUnavailable()
                }
            }
    }

    private fun clearInstallListener() {
        val client = installClient
        val listener = installListener
        installClient = null
        installListener = null
        if (client != null && listener != null) {
            client.unregisterListener(listener)
        }
    }

    private fun failUnavailable() {
        fail(
            "scan_unavailable",
            "QR scanning is unavailable. Use Paste pairing link or enter your server and account details.",
        )
    }

    private fun fail(code: String, message: String) {
        pending?.error(code, message, null)
        pending = null
    }
}
