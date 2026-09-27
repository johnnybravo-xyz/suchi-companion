package page.suchi.companion

import android.content.Intent
import android.graphics.Color
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var scanChannel: ScanChannel? = null
    private var shareChannel: ShareChannel? = null
    private var storageChannel: StorageChannel? = null
    private var documentChannel: DocumentChannel? = null
    private var pairingChannel: PairingChannel? = null
    private var privacyCover: TextView? = null
    private var privacyBlur: RenderEffect? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Older Recents can snapshot before onUserLeaveHint or onPause runs.
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onCreate(savedInstanceState)
    }

    override fun onUserLeaveHint() {
        showPrivacyCover()
        super.onUserLeaveHint()
    }

    override fun onPause() {
        showPrivacyCover()
        super.onPause()
    }

    private fun showPrivacyCover() {
        val canBlur = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        if (canBlur) {
            val blur = privacyBlur ?: RenderEffect.createBlurEffect(
                32f, 32f, Shader.TileMode.CLAMP,
            ).also { privacyBlur = it }
            window.decorView.findViewById<View>(android.R.id.content)?.setRenderEffect(blur)
        }
        val cover = privacyCover ?: TextView(this).apply {
            if (!canBlur) {
                text = "Suchi Companion"
                textSize = 24f
                setTextColor(Color.rgb(23, 24, 26))
                gravity = Gravity.CENTER
            }
            setBackgroundColor(
                if (canBlur) Color.argb(102, 250, 250, 248) else Color.rgb(250, 250, 248),
            )
        }.also { privacyCover = it }
        if (cover.parent == null) {
            (window.decorView as ViewGroup).addView(
                cover,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    override fun onResume() {
        super.onResume()
        scanChannel?.onResume()
        privacyCover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            window.decorView.findViewById<View>(android.R.id.content)?.setRenderEffect(null)
        }
    }

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
