package com.bainatna.chat

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

// الجولة الثانية: منع لقطات الشاشة، حساس القرب، إبقاء الشاشة مضيئة، استقبال المشاركة من تطبيقات ثانية
object R2Native {
    private var pending: HashMap<String, Any?>? = null
    private var prox: PowerManager.WakeLock? = null

    fun register(a: Activity, m: BinaryMessenger) {
        MethodChannel(m, "bainatna/r2").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "secure" -> {
                        if (call.arguments == true) {
                            a.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            a.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "keepOn" -> {
                        if (call.arguments == true) {
                            a.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            a.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "proximity" -> {
                        proximity(a, call.arguments == true)
                        result.success(null)
                    }
                    "takeShare" -> {
                        val p = pending
                        pending = null
                        result.success(p)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("r2", e.message, null)
            }
        }
    }

    private fun proximity(a: Activity, on: Boolean) {
        val pm = a.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (on) {
            if (prox == null && pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                prox = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "bainatna:prox")
            }
            val w = prox
            if (w != null && !w.isHeld) w.acquire(3 * 60 * 60 * 1000L)
        } else {
            val w = prox
            if (w != null && w.isHeld) w.release()
        }
    }

    fun handleIntent(a: Activity, i: Intent?) {
        if (i == null) return
        val act = i.action
        if (act == "com.bainatna.chat.THINK") {
            pending = hashMapOf("think" to true)
            return
        }
        if (act != Intent.ACTION_SEND) return
        val type = i.type ?: return
        val map = HashMap<String, Any?>()
        val text = i.getStringExtra(Intent.EXTRA_TEXT)
        if (text != null) map["text"] = text
        if (type.startsWith("image/")) {
            @Suppress("DEPRECATION")
            val uri = i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri != null) {
                try {
                    val ext = if (type.contains("png")) "png" else if (type.contains("webp")) "webp" else if (type.contains("gif")) "gif" else "jpg"
                    val f = File(a.cacheDir, "share_" + System.currentTimeMillis() + "." + ext)
                    a.contentResolver.openInputStream(uri)?.use { ins ->
                        f.outputStream().use { out -> ins.copyTo(out) }
                    }
                    map["file"] = f.absolutePath
                    map["mime"] = type
                } catch (e: Exception) {
                }
            }
        }
        if (map.isNotEmpty()) pending = map
    }
}

// بلاطة الإعدادات السريعة: «أفكر فيك»
class ThinkTile : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val t = qsTile
        if (t != null) {
            t.state = Tile.STATE_INACTIVE
            t.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val i = Intent(this, MainActivity::class.java)
        i.action = "com.bainatna.chat.THINK"
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(i)
        }
    }
}
