package com.volcano.emberdrift

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity for the Flutter engine.
 *
 * Bridges the WebView's `<input type="file">` chooser to the system's
 * ACTION_GET_CONTENT flow through a dedicated MethodChannel. Doing it
 * natively keeps us off `file_picker` (whose 10.x line collides with
 * Flutter's Kotlin Gradle plugin, see the pitfalls guide § file_picker).
 *
 * The channel name is project-unique — every gray-flow shell must ship
 * its own identifier so the compiled Dart symbol table doesn't overlap.
 */
class MainActivity : FlutterActivity() {

    // Unique to this project. If it changes here it also has to change
    // inside StreamScene's MethodChannel constructor on the Dart side.
    private val bridgeName: String = "emberdrift.volcano/pickfile"
    private val pickCode: Int = 0x4E27
    private var pendingReply: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, bridgeName)
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "pick" -> {
                        val allowMany = call.argument<Boolean>("multiple") ?: false
                        val mimes = call.argument<List<String>>("mimeTypes") ?: emptyList()
                        launchChooser(allowMany, mimes, reply)
                    }
                    else -> reply.notImplemented()
                }
            }
    }

    private fun launchChooser(
        allowMany: Boolean,
        mimes: List<String>,
        reply: MethodChannel.Result,
    ) {
        // Release any prior in-flight pick — the WebView may re-open its
        // chooser before the previous call resolves.
        pendingReply?.success(emptyList<String>())
        pendingReply = reply

        val cleanMimes = mimes.filter { it.contains("/") }
        val payload = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMany)
            when {
                cleanMimes.isEmpty() -> type = "*/*"
                cleanMimes.size == 1 -> type = cleanMimes[0]
                else -> {
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, cleanMimes.toTypedArray())
                }
            }
        }

        try {
            startActivityForResult(Intent.createChooser(payload, null), pickCode)
        } catch (_: Exception) {
            pendingReply = null
            reply.success(emptyList<String>())
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickCode) return

        val reply = pendingReply
        pendingReply = null
        if (reply == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            reply.success(emptyList<String>())
            return
        }

        val out = ArrayList<String>()
        val clip = data.clipData
        if (clip != null) {
            var i = 0
            while (i < clip.itemCount) {
                out.add(clip.getItemAt(i).uri.toString())
                i++
            }
        } else {
            data.data?.let { out.add(it.toString()) }
        }
        reply.success(out)
    }
}
