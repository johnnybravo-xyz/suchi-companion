package app.suchi.page

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var scanChannel: ScanChannel? = null
    private var shareChannel: ShareChannel? = null
    private var storageChannel: StorageChannel? = null
    private var documentChannel: DocumentChannel? = null
    private var pairingChannel: PairingChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        scanChannel = ScanChannel(this).also { it.register(flutterEngine) }
        shareChannel = ShareChannel(this).also {
            it.register(flutterEngine)
            it.acceptIntent(intent)
        }
        storageChannel = StorageChannel(this).also { it.register(flutterEngine) }
        documentChannel = DocumentChannel(this).also { it.register(flutterEngine) }
        pairingChannel = PairingChannel(this).also { it.register(flutterEngine) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (scanChannel?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        if (shareChannel?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shareChannel?.acceptIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        scanChannel = null
        shareChannel?.close()
        shareChannel = null
        storageChannel?.close()
        storageChannel = null
        documentChannel?.close()
        documentChannel = null
        pairingChannel?.close()
        pairingChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
